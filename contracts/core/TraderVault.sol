// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Math.sol";
import "../libraries/SafetyChecks.sol";
import "../libraries/PositionManager.sol";
import "../synthetics/OracleRegistry.sol";
import "../synthetics/TradingVault.sol";
import "../governance/TreasuryManager.sol";

/**
 * @title TraderVault
 * @notice Individual vault for a funded trader with real capital
 * @dev Enforces risk limits, executes live trades, and handles profit distribution
 */
contract TraderVault is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafetyChecks for uint256;
    using PositionManager for PositionManager.Position;

    /// @notice Live position structure
    struct LivePosition {
        uint256 positionId;
        string symbol;
        uint256 entryPrice;
        uint256 size;
        bool isLong;
        uint256 collateralLocked;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 openTime;
        bool isOpen;
    }

    /// @notice Trader (owner) address
    address public immutable owner;

    /// @notice Admin address (can emergency pause)
    address public immutable admin;

    /// @notice Treasury manager
    TreasuryManager public immutable treasury;

    /// @notice Trading vault (collateral pool)
    TradingVault public immutable tradingVault;

    /// @notice Oracle registry
    OracleRegistry public immutable oracleRegistry;

    /// @notice Collateral token (USDC)
    IERC20 public immutable collateralToken;

    /// @notice Initial capital allocated
    uint256 public immutable initialCapital;

    /// @notice Current USDC balance
    uint256 public currentBalance;

    /// @notice High water mark for profit calculations
    uint256 public highWaterMark;

    /// @notice Total profit withdrawn
    uint256 public totalProfitWithdrawn;

    /// @notice Open positions
    mapping(uint256 => LivePosition) public positions;

    /// @notice Position counter
    uint256 public positionCounter;

    /// @notice Risk parameters
    uint256 public maxPositionSize;
    uint256 public maxDailyLoss;
    uint256 public profitSplitBps; // Trader's share (e.g., 8000 = 80%)

    /// @notice Daily loss tracking
    uint256 public currentDailyLoss;
    uint256 public lastResetTime;

    /// @notice Total locked collateral in open positions
    uint256 public totalLockedCollateral;

    /// Events
    event LiveTradeExecuted(
        uint256 indexed positionId,
        string symbol,
        uint256 size,
        bool isLong,
        uint256 entryPrice,
        uint256 stopLoss
    );

    event TradeClosed(
        uint256 indexed positionId,
        uint256 exitPrice,
        int256 pnl,
        uint256 newBalance
    );

    event PayoutExecuted(
        uint256 profit,
        uint256 traderShare,
        uint256 firmShare
    );

    event DailyLossLimitHit(uint256 loss, uint256 timestamp);
    event VaultPaused(uint256 timestamp, string reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "TraderVault: Not owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "TraderVault: Not admin");
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner || msg.sender == admin, "TraderVault: Not authorized");
        _;
    }

    /**
     * @notice Constructor
     * @param _owner Trader address
     * @param _admin Admin address
     * @param _treasury Treasury manager address
     * @param _tradingVault Trading vault address
     * @param _oracleRegistry Oracle registry address
     * @param _collateralToken USDC token address
     * @param _initialCapital Starting capital
     * @param _maxPositionSize Max single position size
     * @param _maxDailyLoss Max daily loss limit
     * @param _profitSplitBps Trader's profit share in bps
     */
    constructor(
        address _owner,
        address _admin,
        address _treasury,
        address _tradingVault,
        address _oracleRegistry,
        address _collateralToken,
        uint256 _initialCapital,
        uint256 _maxPositionSize,
        uint256 _maxDailyLoss,
        uint256 _profitSplitBps
    ) {
        require(_owner != address(0), "TraderVault: Invalid owner");
        require(_admin != address(0), "TraderVault: Invalid admin");
        require(_initialCapital > 0, "TraderVault: Invalid capital");

        owner = _owner;
        admin = _admin;
        treasury = TreasuryManager(_treasury);
        tradingVault = TradingVault(_tradingVault);
        oracleRegistry = OracleRegistry(_oracleRegistry);
        collateralToken = IERC20(_collateralToken);

        initialCapital = _initialCapital;
        currentBalance = _initialCapital;
        highWaterMark = _initialCapital;

        maxPositionSize = _maxPositionSize;
        maxDailyLoss = _maxDailyLoss;
        profitSplitBps = _profitSplitBps;

        lastResetTime = block.timestamp;
    }

    /**
     * @notice Execute a live trade
     * @param symbol Asset symbol
     * @param size Position size
     * @param isLong True for long, false for short
     * @param stopLoss Stop loss price (mandatory)
     * @param takeProfit Take profit price (optional)
     */
    function executeLiveTrade(
        string calldata symbol,
        uint256 size,
        bool isLong,
        uint256 stopLoss,
        uint256 takeProfit
    ) external onlyOwner nonReentrant whenNotPaused {
        // Reset daily loss if 24h passed
        _checkDailyLossReset();

        // Check daily loss limit
        require(
            !SafetyChecks.isDailyLossLimitExceeded(currentDailyLoss, maxDailyLoss),
            "TraderVault: Daily loss limit exceeded"
        );

        // Validate position size
        require(
            SafetyChecks.validatePosition(size, getAvailableBalance(), maxPositionSize),
            "TraderVault: Invalid position size"
        );

        // Get current price
        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(symbol);
        require(currentPrice > 0, "TraderVault: Invalid price");

        // Validate stop loss (mandatory)
        require(stopLoss > 0, "TraderVault: Stop loss required");
        if (isLong) {
            require(stopLoss < currentPrice, "TraderVault: Invalid stop loss for long");
        } else {
            require(stopLoss > currentPrice, "TraderVault: Invalid stop loss for short");
        }

        // Calculate required collateral (assume 10x max leverage)
        // Size is position value in USDC, so margin = size / leverage
        uint256 leverage = 10;
        uint256 requiredCollateral = size / leverage;

        require(
            requiredCollateral <= getAvailableBalance(),
            "TraderVault: Insufficient balance"
        );

        // Allocate collateral from trading vault
        tradingVault.allocateCollateral(requiredCollateral);

        // Create position
        positionCounter++;
        positions[positionCounter] = LivePosition({
            positionId: positionCounter,
            symbol: symbol,
            entryPrice: currentPrice,
            size: size,
            isLong: isLong,
            collateralLocked: requiredCollateral,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            openTime: block.timestamp,
            isOpen: true
        });

        totalLockedCollateral += requiredCollateral;

        emit LiveTradeExecuted(
            positionCounter,
            symbol,
            size,
            isLong,
            currentPrice,
            stopLoss
        );
    }

    /**
     * @notice Close a live trade
     * @param positionId Position ID to close
     */
    function closeLiveTrade(uint256 positionId) external onlyOwner nonReentrant whenNotPaused {
        LivePosition storage position = positions[positionId];
        require(position.isOpen, "TraderVault: Position not open");

        // Get current price
        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(position.symbol);
        require(currentPrice > 0, "TraderVault: Invalid price");

        _closePosition(positionId, currentPrice);
    }

    /**
     * @notice Check stop loss for a position (callable by anyone)
     * @param positionId Position ID to check
     */
    function checkStopLoss(uint256 positionId) external nonReentrant {
        LivePosition storage position = positions[positionId];
        require(position.isOpen, "TraderVault: Position not open");

        // Get current price
        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(position.symbol);
        require(currentPrice > 0, "TraderVault: Invalid price");

        // Check if stop loss triggered
        bool triggered = SafetyChecks.isStopLossTriggered(
            currentPrice,
            position.stopLoss,
            position.isLong
        );

        require(triggered, "TraderVault: Stop loss not triggered");

        _closePosition(positionId, currentPrice);
    }

    /**
     * @notice Internal function to close position
     * @param positionId Position ID
     * @param exitPrice Exit price
     */
    function _closePosition(uint256 positionId, uint256 exitPrice) private {
        LivePosition storage position = positions[positionId];

        // Calculate PnL: size is in USDC, so PnL = size * price_change / entry_price
        int256 pnl;
        if (position.isLong) {
            // Long: profit when price increases
            int256 priceChange = int256(exitPrice) - int256(position.entryPrice);
            pnl = (priceChange * int256(position.size)) / int256(position.entryPrice);
        } else {
            // Short: profit when price decreases
            int256 priceChange = int256(position.entryPrice) - int256(exitPrice);
            pnl = (priceChange * int256(position.size)) / int256(position.entryPrice);
        }

        // Release collateral from trading vault
        tradingVault.releaseCollateral(position.collateralLocked);
        totalLockedCollateral -= position.collateralLocked;

        // Apply PnL to balance
        if (pnl > 0) {
            // Profit
            currentBalance += uint256(pnl);
            
            // Update high water mark
            if (currentBalance > highWaterMark) {
                highWaterMark = currentBalance;
            }
        } else if (pnl < 0) {
            // Loss
            uint256 loss = uint256(-pnl);
            
            // Update daily loss
            currentDailyLoss += loss;
            
            // Check if daily loss limit hit
            if (SafetyChecks.isDailyLossLimitExceeded(currentDailyLoss, maxDailyLoss)) {
                _pause();
                emit DailyLossLimitHit(currentDailyLoss, block.timestamp);
            }
            
            // Deduct from balance
            if (loss >= currentBalance) {
                currentBalance = 0;
            } else {
                currentBalance -= loss;
            }
        }

        // Mark position as closed
        position.isOpen = false;

        emit TradeClosed(positionId, exitPrice, pnl, currentBalance);
    }

    /**
     * @notice Request profit payout
     */
    function requestPayout() external onlyOwner nonReentrant {
        require(currentBalance > highWaterMark, "TraderVault: No profit available");
        
        uint256 profit = currentBalance - highWaterMark;
        
        // Calculate split
        (uint256 traderShare, uint256 firmShare) = Math.splitProfit(profit, profitSplitBps);

        // Update tracking
        highWaterMark = currentBalance;
        totalProfitWithdrawn += traderShare;
        currentBalance -= profit;

        // Transfer trader's share
        collateralToken.safeTransfer(owner, traderShare);

        // Transfer firm's share to treasury
        collateralToken.forceApprove(address(treasury), firmShare);
        treasury.receiveProfit(firmShare);

        emit PayoutExecuted(profit, traderShare, firmShare);
    }

    /**
     * @notice Check and reset daily loss if needed
     */
    function _checkDailyLossReset() private {
        if (block.timestamp >= lastResetTime + 1 days) {
            currentDailyLoss = 0;
            lastResetTime = block.timestamp;
        }
    }

    /**
     * @notice Get available balance (total - locked)
     * @return uint256 Available balance
     */
    function getAvailableBalance() public view returns (uint256) {
        return currentBalance > totalLockedCollateral 
            ? currentBalance - totalLockedCollateral 
            : 0;
    }

    /**
     * @notice Get vault statistics
     * @return balance Current balance
     * @return locked Locked collateral
     * @return available Available balance
     * @return profit Unrealized profit
     * @return dailyLoss Current daily loss
     */
    function getVaultStats() external view returns (
        uint256 balance,
        uint256 locked,
        uint256 available,
        uint256 profit,
        uint256 dailyLoss
    ) {
        balance = currentBalance;
        locked = totalLockedCollateral;
        available = getAvailableBalance();
        profit = currentBalance > highWaterMark ? currentBalance - highWaterMark : 0;
        dailyLoss = currentDailyLoss;
    }

    /**
     * @notice Get unrealized PnL for all open positions
     * @return totalPnL Total unrealized PnL
     */
    function calculateUnrealizedPnL() external view returns (int256 totalPnL) {
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (positions[i].isOpen) {
                (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(positions[i].symbol);
                if (currentPrice > 0) {
                    int256 pnl;
                    if (positions[i].isLong) {
                        int256 priceChange = int256(currentPrice) - int256(positions[i].entryPrice);
                        pnl = (priceChange * int256(positions[i].size)) / int256(positions[i].entryPrice);
                    } else {
                        int256 priceChange = int256(positions[i].entryPrice) - int256(currentPrice);
                        pnl = (priceChange * int256(positions[i].size)) / int256(positions[i].entryPrice);
                    }
                    totalPnL += pnl;
                }
            }
        }
    }

    /**
     * @notice Get all open positions
     * @return openPositions Array of position IDs
     */
    function getOpenPositions() external view returns (uint256[] memory openPositions) {
        // Count open positions
        uint256 count = 0;
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (positions[i].isOpen) {
                count++;
            }
        }

        // Create array
        openPositions = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (positions[i].isOpen) {
                openPositions[index] = i;
                index++;
            }
        }
    }

    /**
     * @notice Pause trading (owner or admin)
     */
    function pauseTrading() external onlyOwnerOrAdmin {
        _pause();
        emit VaultPaused(block.timestamp, "Manual pause");
    }

    /**
     * @notice Unpause trading (owner only)
     */
    function unpauseTrading() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Force close position (admin only, emergency)
     * @param positionId Position ID
     */
    function forceClosePosition(uint256 positionId) external onlyAdmin nonReentrant {
        LivePosition storage position = positions[positionId];
        require(position.isOpen, "TraderVault: Position not open");

        (uint256 currentPrice, ) = oracleRegistry.getLatestPrice(position.symbol);
        require(currentPrice > 0, "TraderVault: Invalid price");

        _closePosition(positionId, currentPrice);
    }

    /**
     * @notice Emergency withdraw (admin only, when paused)
     * @param recipient Recipient address
     */
    function emergencyWithdraw(address recipient) external onlyAdmin whenPaused nonReentrant {
        require(recipient != address(0), "TraderVault: Invalid recipient");
        
        uint256 balance = collateralToken.balanceOf(address(this));
        if (balance > 0) {
            collateralToken.safeTransfer(recipient, balance);
        }
    }

    /**
     * @notice Sync balance with actual USDC holdings
     * @dev Called after initial funding from treasury
     */
    function syncBalance() external {
        uint256 actualBalance = collateralToken.balanceOf(address(this));
        if (actualBalance > currentBalance) {
            currentBalance = actualBalance;
            if (highWaterMark < currentBalance) {
                highWaterMark = currentBalance;
            }
        }
    }

    /**
     * @notice Receive USDC (for initial funding)
     */
    receive() external payable {
        revert("TraderVault: Use USDC transfers");
    }
}
