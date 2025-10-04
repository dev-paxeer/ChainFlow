// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/SafetyChecks.sol";
import "../libraries/Math.sol";

/**
 * @title TradingVault
 * @notice Collateral pool for all synthetic trading positions
 * @dev Manages risk limits, exposure, and collateral allocation
 */
contract TradingVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafetyChecks for uint256;
    using Math for uint256;

    /// @notice Collateral token (USDC)
    IERC20 public immutable collateralToken;

    /// @notice Total collateral deposited
    uint256 public totalCollateral;

    /// @notice Total exposure across all positions
    uint256 public totalExposure;

    /// @notice Maximum exposure ratio in basis points (e.g., 8000 = 80%)
    uint256 public maxExposureRatio;

    /// @notice Minimum collateral ratio in basis points (e.g., 12000 = 120%)
    uint256 public minCollateralRatio;

    /// @notice Exposure per trader
    mapping(address => uint256) public traderExposure;

    /// @notice Collateral locked per trader
    mapping(address => uint256) public traderCollateral;

    /// @notice Authorized trader vaults
    mapping(address => bool) public authorizedTraders;

    /// @notice Authorized managers who can authorize traders (e.g., factory)
    mapping(address => bool) public authorizedManagers;

    /// Events
    event CollateralDeposited(address indexed depositor, uint256 amount);
    event CollateralWithdrawn(address indexed recipient, uint256 amount);
    event CollateralAllocated(address indexed trader, uint256 amount);
    event CollateralReleased(address indexed trader, uint256 amount);
    event ExposureUpdated(address indexed trader, uint256 oldExposure, uint256 newExposure);
    event TraderAuthorized(address indexed trader, bool authorized);
    event ExposureRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event CollateralRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event TradingPaused(uint256 timestamp, string reason);

    /**
     * @notice Constructor
     * @param _collateralToken USDC token address
     * @param _initialOwner Initial owner
     */
    constructor(
        address _collateralToken,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_collateralToken != address(0), "TradingVault: Invalid token");
        
        collateralToken = IERC20(_collateralToken);
        maxExposureRatio = 8000; // 80% default
        minCollateralRatio = 12000; // 120% default
    }

    /**
     * @notice Deposit collateral into vault
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TradingVault: Invalid amount");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        totalCollateral += amount;

        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw collateral (only unallocated)
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TradingVault: Invalid amount");
        
        uint256 available = getAvailableCollateral();
        require(amount <= available, "TradingVault: Insufficient available collateral");

        totalCollateral -= amount;
        collateralToken.safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Allocate collateral for a position
     * @param amount Collateral to allocate
     */
    function allocateCollateral(uint256 amount) external nonReentrant whenNotPaused {
        require(authorizedTraders[msg.sender], "TradingVault: Not authorized");
        require(amount > 0, "TradingVault: Invalid amount");

        uint256 available = getAvailableCollateral();
        require(amount <= available, "TradingVault: Insufficient collateral");

        traderCollateral[msg.sender] += amount;

        emit CollateralAllocated(msg.sender, amount);
    }

    /**
     * @notice Release collateral after closing position
     * @param amount Collateral to release
     */
    function releaseCollateral(uint256 amount) external nonReentrant {
        require(authorizedTraders[msg.sender], "TradingVault: Not authorized");
        require(amount > 0, "TradingVault: Invalid amount");
        require(amount <= traderCollateral[msg.sender], "TradingVault: Insufficient locked collateral");

        traderCollateral[msg.sender] -= amount;

        emit CollateralReleased(msg.sender, amount);
    }

    /**
     * @notice Update trader's exposure
     * @param newExposure New exposure amount
     */
    function updateExposure(uint256 newExposure) external whenNotPaused {
        require(authorizedTraders[msg.sender], "TradingVault: Not authorized");

        uint256 oldExposure = traderExposure[msg.sender];
        
        // Update total exposure
        if (newExposure > oldExposure) {
            uint256 increase = newExposure - oldExposure;
            totalExposure += increase;
        } else if (newExposure < oldExposure) {
            uint256 decrease = oldExposure - newExposure;
            totalExposure -= decrease;
        }

        // Check exposure limit
        uint256 maxExposure = (totalCollateral * maxExposureRatio) / Math.getBpsDenominator();
        require(totalExposure <= maxExposure, "TradingVault: Exposure limit exceeded");

        // Check collateralization ratio
        require(
            SafetyChecks.validateCollateralRatio(
                totalCollateral,
                totalExposure,
                minCollateralRatio
            ),
            "TradingVault: Insufficient collateralization"
        );

        traderExposure[msg.sender] = newExposure;

        emit ExposureUpdated(msg.sender, oldExposure, newExposure);
    }

    /**
     * @notice Settle PnL for a trader
     * @param trader Trader address
     * @param pnl Profit (positive) or loss (negative)
     */
    function settlePnL(address trader, int256 pnl) external onlyOwner nonReentrant {
        require(authorizedTraders[trader], "TradingVault: Not authorized trader");

        if (pnl > 0) {
            // Profit: increase trader's available balance
            // In practice, this would be tracked in TraderVault
            emit CollateralReleased(trader, uint256(pnl));
        } else if (pnl < 0) {
            // Loss: deduct from collateral
            uint256 loss = uint256(-pnl);
            require(traderCollateral[trader] >= loss, "TradingVault: Insufficient collateral for loss");
            
            traderCollateral[trader] -= loss;
            totalCollateral -= loss;
            
            emit CollateralAllocated(trader, loss);
        }
    }

    /**
     * @notice Authorize/deauthorize trader vault
     * @param trader Trader vault address
     * @param authorized Authorization status
     */
    function setAuthorizedTrader(address trader, bool authorized) external {
        require(
            msg.sender == owner() || authorizedManagers[msg.sender],
            "TradingVault: Not authorized"
        );
        require(trader != address(0), "TradingVault: Invalid trader");
        
        authorizedTraders[trader] = authorized;

        emit TraderAuthorized(trader, authorized);
    }

    /**
     * @notice Set authorized manager (only owner)
     * @param manager Manager address
     * @param authorized Authorization status
     */
    function setAuthorizedManager(address manager, bool authorized) external onlyOwner {
        require(manager != address(0), "TradingVault: Invalid manager");
        authorizedManagers[manager] = authorized;
    }

    /**
     * @notice Set maximum exposure ratio
     * @param _maxExposureRatio New ratio in basis points
     */
    function setMaxExposureRatio(uint256 _maxExposureRatio) external onlyOwner {
        require(_maxExposureRatio > 0 && _maxExposureRatio <= 10000, "TradingVault: Invalid ratio");
        
        uint256 oldRatio = maxExposureRatio;
        maxExposureRatio = _maxExposureRatio;

        emit ExposureRatioUpdated(oldRatio, _maxExposureRatio);
    }

    /**
     * @notice Set minimum collateral ratio
     * @param _minCollateralRatio New ratio in basis points
     */
    function setMinCollateralRatio(uint256 _minCollateralRatio) external onlyOwner {
        require(_minCollateralRatio >= 10000, "TradingVault: Ratio must be >= 100%");
        
        uint256 oldRatio = minCollateralRatio;
        minCollateralRatio = _minCollateralRatio;

        emit CollateralRatioUpdated(oldRatio, _minCollateralRatio);
    }

    /**
     * @notice Pause trading
     */
    function pauseTrading(string calldata reason) external onlyOwner {
        _pause();
        emit TradingPaused(block.timestamp, reason);
    }

    /**
     * @notice Unpause trading
     */
    function unpauseTrading() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Get available (unallocated) collateral
     * @return uint256 Available amount
     */
    function getAvailableCollateral() public view returns (uint256) {
        uint256 allocated = getTotalAllocated();
        return totalCollateral > allocated ? totalCollateral - allocated : 0;
    }

    /**
     * @notice Get total allocated collateral
     * @return uint256 Total allocated
     */
    function getTotalAllocated() public view returns (uint256) {
        // This is simplified; in production, you'd sum all trader collateral
        // For gas efficiency, we track this separately
        return totalCollateral - collateralToken.balanceOf(address(this));
    }

    /**
     * @notice Check current exposure metrics
     * @return currentExposure Current total exposure
     * @return maxAllowedExposure Maximum allowed exposure
     * @return utilizationBps Utilization in basis points
     */
    function checkExposure() external view returns (
        uint256 currentExposure,
        uint256 maxAllowedExposure,
        uint256 utilizationBps
    ) {
        currentExposure = totalExposure;
        maxAllowedExposure = (totalCollateral * maxExposureRatio) / Math.getBpsDenominator();
        
        if (maxAllowedExposure > 0) {
            utilizationBps = (currentExposure * Math.getBpsDenominator()) / maxAllowedExposure;
        } else {
            utilizationBps = 0;
        }
    }

    /**
     * @notice Get trader's collateral info
     * @param trader Trader address
     * @return locked Locked collateral
     * @return exposure Current exposure
     */
    function getTraderInfo(address trader) external view returns (
        uint256 locked,
        uint256 exposure
    ) {
        return (traderCollateral[trader], traderExposure[trader]);
    }

    /**
     * @notice Check if vault is healthy
     * @return bool True if collateralization is sufficient
     */
    function isHealthy() external view returns (bool) {
        if (totalExposure == 0) return true;
        
        return SafetyChecks.validateCollateralRatio(
            totalCollateral,
            totalExposure,
            minCollateralRatio
        );
    }

    /**
     * @notice Emergency withdraw (only when paused)
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address recipient, uint256 amount) external onlyOwner whenPaused nonReentrant {
        require(recipient != address(0), "TradingVault: Invalid recipient");
        require(amount > 0, "TradingVault: Invalid amount");

        uint256 balance = collateralToken.balanceOf(address(this));
        require(amount <= balance, "TradingVault: Insufficient balance");

        collateralToken.safeTransfer(recipient, amount);

        emit CollateralWithdrawn(recipient, amount);
    }
}
