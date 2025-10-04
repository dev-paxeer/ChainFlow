// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Math.sol";
import "../libraries/SafetyChecks.sol";
import "../libraries/PositionManager.sol";
import "../synthetics/OracleRegistry.sol";
import "../reputation/ReputationNFT.sol";

/**
 * @title EvaluationManager
 * @notice Manages trader evaluations with virtual trading
 * @dev Enforces profit targets, drawdown limits, and mints NFTs on success
 */
contract EvaluationManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafetyChecks for uint256;
    using PositionManager for PositionManager.Position;

    /// @notice Evaluation rules structure
    struct EvaluationRules {
        uint256 virtualBalance;      // Starting balance (e.g., 10000 USDC)
        uint256 profitTargetBps;     // Required profit in bps (e.g., 1000 = 10%)
        uint256 maxDrawdownBps;      // Max drawdown in bps (e.g., 500 = 5%)
        uint256 minTrades;           // Minimum trades required
        uint256 evaluationPeriod;    // Max time allowed (seconds)
        uint256 evaluationFee;       // Entry fee in USDC
    }

    /// @notice Evaluation state for a trader
    struct Evaluation {
        address trader;
        uint256 startTime;
        uint256 virtualBalance;
        uint256 highWaterMark;
        uint256 currentDrawdown;
        uint256 tradeCount;
        bool isActive;
        bool passed;
        bool failed;
        uint256 evaluationId;
    }

    /// @notice Virtual position structure
    struct VirtualPosition {
        uint256 positionId;
        string symbol;              // Asset symbol (e.g., "BTC/USD")
        uint256 entryPrice;
        uint256 size;
        bool isLong;
        uint256 collateral;
        uint256 openTime;
    }

    /// @notice Collateral token (USDC)
    IERC20 public immutable collateralToken;

    /// @notice Oracle registry
    OracleRegistry public oracleRegistry;

    /// @notice Reputation NFT contract
    ReputationNFT public reputationNFT;

    /// @notice Evaluation rules
    EvaluationRules public rules;

    /// @notice Evaluation counter
    uint256 public evaluationCounter;

    /// @notice Active evaluations by trader
    mapping(address => Evaluation) public evaluations;

    /// @notice Positions by trader
    mapping(address => mapping(uint256 => VirtualPosition)) public positions;

    /// @notice Position counter per trader
    mapping(address => uint256) public positionCounter;

    /// @notice Fee collector address
    address public feeCollector;

    /// Events
    event EvaluationStarted(
        address indexed trader,
        uint256 indexed evaluationId,
        uint256 virtualBalance,
        uint256 timestamp
    );

    event VirtualTradeExecuted(
        address indexed trader,
        uint256 indexed positionId,
        string symbol,
        uint256 size,
        bool isLong,
        uint256 entryPrice
    );

    event VirtualTradeClosed(
        address indexed trader,
        uint256 indexed positionId,
        uint256 exitPrice,
        int256 pnl,
        uint256 newBalance
    );

    event EvaluationPassed(
        address indexed trader,
        uint256 indexed evaluationId,
        uint256 finalBalance,
        uint256 profitAchieved
    );

    event EvaluationFailed(
        address indexed trader,
        uint256 indexed evaluationId,
        string reason,
        uint256 finalBalance
    );

    event RulesUpdated(
        uint256 virtualBalance,
        uint256 profitTarget,
        uint256 maxDrawdown,
        uint256 minTrades
    );

    /**
     * @notice Constructor
     * @param _collateralToken USDC token address
     * @param _oracleRegistry Oracle registry address
     * @param _reputationNFT Reputation NFT address
     * @param _initialOwner Initial owner
     */
    constructor(
        address _collateralToken,
        address _oracleRegistry,
        address _reputationNFT,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_collateralToken != address(0), "EvaluationManager: Invalid token");
        require(_oracleRegistry != address(0), "EvaluationManager: Invalid registry");
        require(_reputationNFT != address(0), "EvaluationManager: Invalid NFT");

        collateralToken = IERC20(_collateralToken);
        oracleRegistry = OracleRegistry(_oracleRegistry);
        reputationNFT = ReputationNFT(_reputationNFT);
        feeCollector = _initialOwner;

        // Set default rules
        rules = EvaluationRules({
            virtualBalance: 10000 * 1e6,     // 10,000 USDC
            profitTargetBps: 1000,           // 10%
            maxDrawdownBps: 500,             // 5%
            minTrades: 5,                    // Minimum 5 trades
            evaluationPeriod: 30 days,       // 30 days max
            evaluationFee: 100 * 1e6         // 100 USDC fee
        });
    }

    /**
     * @notice Start a new evaluation
     */
    function startEvaluation() external nonReentrant whenNotPaused {
        require(!evaluations[msg.sender].isActive, "EvaluationManager: Already in evaluation");
        require(
            !reputationNFT.hasCredential(msg.sender),
            "EvaluationManager: Already has credential"
        );

        // Collect fee
        if (rules.evaluationFee > 0) {
            collateralToken.safeTransferFrom(msg.sender, feeCollector, rules.evaluationFee);
        }

        evaluationCounter++;

        // Initialize evaluation
        evaluations[msg.sender] = Evaluation({
            trader: msg.sender,
            startTime: block.timestamp,
            virtualBalance: rules.virtualBalance,
            highWaterMark: rules.virtualBalance,
            currentDrawdown: 0,
            tradeCount: 0,
            isActive: true,
            passed: false,
            failed: false,
            evaluationId: evaluationCounter
        });

        emit EvaluationStarted(msg.sender, evaluationCounter, rules.virtualBalance, block.timestamp);
    }

    /**
     * @notice Execute a virtual trade
     * @param symbol Asset symbol (e.g., "BTC/USD")
     * @param size Position size
     * @param isLong True for long, false for short
     */
    function executeVirtualTrade(
        string calldata symbol,
        uint256 size,
        bool isLong
    ) external nonReentrant whenNotPaused {
        Evaluation storage eval = evaluations[msg.sender];
        require(eval.isActive, "EvaluationManager: No active evaluation");
        require(!_isEvaluationExpired(eval), "EvaluationManager: Evaluation expired");
        require(size > 0, "EvaluationManager: Invalid size");

        // Get current price
        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(symbol);
        require(currentPrice > 0, "EvaluationManager: Invalid price");

        // For virtual trading, size is the position value in USDC
        // With 10x leverage, margin required is size / 10
        uint256 leverage = 10;
        uint256 requiredMargin = size / leverage;
        
        require(
            requiredMargin <= eval.virtualBalance,
            "EvaluationManager: Insufficient virtual balance"
        );

        // Create position
        positionCounter[msg.sender]++;
        uint256 positionId = positionCounter[msg.sender];

        positions[msg.sender][positionId] = VirtualPosition({
            positionId: positionId,
            symbol: symbol,
            entryPrice: currentPrice,
            size: size,
            isLong: isLong,
            collateral: requiredMargin,
            openTime: block.timestamp
        });

        // Lock collateral
        eval.virtualBalance -= requiredMargin;

        emit VirtualTradeExecuted(msg.sender, positionId, symbol, size, isLong, currentPrice);
    }

    /**
     * @notice Close a virtual trade
     * @param positionId Position ID to close
     */
    function closeVirtualTrade(uint256 positionId) external nonReentrant whenNotPaused {
        Evaluation storage eval = evaluations[msg.sender];
        require(eval.isActive, "EvaluationManager: No active evaluation");

        VirtualPosition storage position = positions[msg.sender][positionId];
        require(position.positionId != 0, "EvaluationManager: Position not found");

        // Get current price
        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(position.symbol);
        require(currentPrice > 0, "EvaluationManager: Invalid price");

        // Calculate PnL: size is in USDC, so PnL = size * price_change / entry_price
        int256 pnl;
        if (position.isLong) {
            // Long: profit when price increases
            int256 priceChange = int256(currentPrice) - int256(position.entryPrice);
            pnl = (priceChange * int256(position.size)) / int256(position.entryPrice);
        } else {
            // Short: profit when price decreases
            int256 priceChange = int256(position.entryPrice) - int256(currentPrice);
            pnl = (priceChange * int256(position.size)) / int256(position.entryPrice);
        }

        // Release collateral and apply PnL
        uint256 collateralReturn = position.collateral;
        
        if (pnl > 0) {
            eval.virtualBalance += collateralReturn + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            if (loss >= collateralReturn) {
                // Total loss of collateral
                eval.virtualBalance += 0;
            } else {
                eval.virtualBalance += collateralReturn - loss;
            }
        }

        // Update high water mark
        if (eval.virtualBalance > eval.highWaterMark) {
            eval.highWaterMark = eval.virtualBalance;
        }

        // Calculate current drawdown
        eval.currentDrawdown = Math.calculateDrawdown(eval.virtualBalance, eval.highWaterMark);

        // Increment trade count
        eval.tradeCount++;

        // Delete position
        delete positions[msg.sender][positionId];

        emit VirtualTradeClosed(msg.sender, positionId, currentPrice, pnl, eval.virtualBalance);

        // Check evaluation status
        _checkEvaluationStatus(msg.sender);
    }

    /**
     * @notice Check and update evaluation status
     * @param trader Trader address
     */
    function _checkEvaluationStatus(address trader) private {
        Evaluation storage eval = evaluations[trader];
        
        // Check if expired
        if (_isEvaluationExpired(eval)) {
            _failEvaluation(trader, "Time expired");
            return;
        }

        // Check if drawdown exceeded
        if (eval.currentDrawdown > rules.maxDrawdownBps) {
            _failEvaluation(trader, "Drawdown limit exceeded");
            return;
        }

        // Check if profit target reached
        uint256 profitTarget = rules.virtualBalance + 
            Math.applyBasisPoints(rules.virtualBalance, rules.profitTargetBps);

        if (eval.virtualBalance >= profitTarget && eval.tradeCount >= rules.minTrades) {
            _passEvaluation(trader);
            return;
        }
    }

    /**
     * @notice Pass evaluation and mint credential
     * @param trader Trader address
     */
    function _passEvaluation(address trader) private {
        Evaluation storage eval = evaluations[trader];
        
        eval.isActive = false;
        eval.passed = true;

        uint256 profitAchieved = eval.virtualBalance - rules.virtualBalance;

        // Calculate win rate (simplified - you'd track wins/losses separately)
        uint256 winRate = 5000; // Placeholder: 50%

        // Mint reputation NFT
        reputationNFT.mint(
            trader,
            eval.evaluationId,
            eval.virtualBalance,
            profitAchieved,
            eval.currentDrawdown,
            eval.tradeCount,
            winRate
        );

        emit EvaluationPassed(trader, eval.evaluationId, eval.virtualBalance, profitAchieved);
    }

    /**
     * @notice Fail evaluation
     * @param trader Trader address
     * @param reason Failure reason
     */
    function _failEvaluation(address trader, string memory reason) private {
        Evaluation storage eval = evaluations[trader];
        
        eval.isActive = false;
        eval.failed = true;

        emit EvaluationFailed(trader, eval.evaluationId, reason, eval.virtualBalance);
    }

    /**
     * @notice Check if evaluation is expired
     * @param eval Evaluation struct
     * @return bool True if expired
     */
    function _isEvaluationExpired(Evaluation memory eval) private view returns (bool) {
        return block.timestamp > eval.startTime + rules.evaluationPeriod;
    }

    /**
     * @notice Update evaluation rules (admin only)
     * @param _virtualBalance New virtual balance
     * @param _profitTargetBps New profit target
     * @param _maxDrawdownBps New max drawdown
     * @param _minTrades New minimum trades
     * @param _evaluationPeriod New evaluation period
     * @param _evaluationFee New evaluation fee
     */
    function setEvaluationRules(
        uint256 _virtualBalance,
        uint256 _profitTargetBps,
        uint256 _maxDrawdownBps,
        uint256 _minTrades,
        uint256 _evaluationPeriod,
        uint256 _evaluationFee
    ) external onlyOwner {
        require(_virtualBalance > 0, "EvaluationManager: Invalid balance");
        require(
            SafetyChecks.validateEvaluationRules(_profitTargetBps, _maxDrawdownBps),
            "EvaluationManager: Invalid rules"
        );

        rules = EvaluationRules({
            virtualBalance: _virtualBalance,
            profitTargetBps: _profitTargetBps,
            maxDrawdownBps: _maxDrawdownBps,
            minTrades: _minTrades,
            evaluationPeriod: _evaluationPeriod,
            evaluationFee: _evaluationFee
        });

        emit RulesUpdated(_virtualBalance, _profitTargetBps, _maxDrawdownBps, _minTrades);
    }

    /**
     * @notice Set fee collector address
     * @param _feeCollector New fee collector
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "EvaluationManager: Invalid address");
        feeCollector = _feeCollector;
    }

    /**
     * @notice Emergency stop evaluation (admin only)
     * @param trader Trader address
     * @param reason Reason for stopping
     */
    function emergencyStopEvaluation(
        address trader,
        string calldata reason
    ) external onlyOwner {
        require(evaluations[trader].isActive, "EvaluationManager: No active evaluation");
        _failEvaluation(trader, reason);
    }

    /**
     * @notice Get evaluation details
     * @param trader Trader address
     * @return Evaluation struct
     */
    function getEvaluation(address trader) external view returns (Evaluation memory) {
        return evaluations[trader];
    }

    /**
     * @notice Get position details
     * @param trader Trader address
     * @param positionId Position ID
     * @return VirtualPosition struct
     */
    function getPosition(
        address trader,
        uint256 positionId
    ) external view returns (VirtualPosition memory) {
        return positions[trader][positionId];
    }

    /**
     * @notice Calculate current unrealized PnL for a position
     * @param trader Trader address
     * @param positionId Position ID
     * @return pnl Unrealized PnL
     */
    function calculateCurrentPnL(
        address trader,
        uint256 positionId
    ) external view returns (int256 pnl) {
        VirtualPosition memory position = positions[trader][positionId];
        require(position.positionId != 0, "EvaluationManager: Position not found");

        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(position.symbol);
        require(currentPrice > 0, "EvaluationManager: Invalid price");

        return Math.calculatePnL(
            position.entryPrice,
            currentPrice,
            position.size,
            position.isLong
        );
    }

    /**
     * @notice Pause evaluations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause evaluations
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
