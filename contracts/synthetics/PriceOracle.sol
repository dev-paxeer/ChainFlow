// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/SafetyChecks.sol";
import "../libraries/Math.sol";

/**
 * @title PriceOracle
 * @notice Price oracle for a specific synthetic asset with TWAP and safety checks
 * @dev One oracle per asset (BTC/USD, ETH/USD, etc.)
 */
contract PriceOracle is Ownable, Pausable {
    using SafetyChecks for uint256;
    using Math for uint256;

    /// @notice Price data structure
    struct PriceData {
        uint256 price;          // Price scaled by 1e8
        uint256 timestamp;      // Update timestamp
        uint256 roundId;        // Incremental counter
    }

    /// @notice Asset symbol (e.g., "BTC/USD")
    string public symbol;

    /// @notice Latest price data
    PriceData public latestPrice;

    /// @notice Historical prices for TWAP (limited size for gas efficiency)
    PriceData[] public priceHistory;

    /// @notice Maximum history length
    uint256 public constant MAX_HISTORY_LENGTH = 100;

    /// @notice Authorized price feeders
    mapping(address => bool) public authorizedFeeders;

    /// @notice Maximum allowed price deviation in basis points (e.g., 500 = 5%)
    uint256 public maxPriceDeviation;

    /// @notice Heartbeat timeout in seconds (max staleness allowed)
    uint256 public heartbeatTimeout;

    /// @notice Minimum time between price updates (anti-spam)
    uint256 public minUpdateInterval;

    /// @notice Last update time for rate limiting
    uint256 public lastUpdateTime;

    /// Events
    event PriceUpdated(
        uint256 indexed roundId,
        uint256 price,
        uint256 timestamp,
        address indexed feeder
    );
    
    event FeederAuthorized(address indexed feeder, bool authorized);
    event MaxDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    event HeartbeatUpdated(uint256 oldTimeout, uint256 newTimeout);
    event PricesFrozen(uint256 timestamp);

    /**
     * @notice Constructor
     * @param _symbol Asset symbol
     * @param _initialPrice Initial price
     * @param _initialOwner Initial owner
     */
    constructor(
        string memory _symbol,
        uint256 _initialPrice,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(bytes(_symbol).length > 0, "PriceOracle: Invalid symbol");
        require(_initialPrice > 0, "PriceOracle: Invalid price");

        symbol = _symbol;
        maxPriceDeviation = 500; // 5% default
        heartbeatTimeout = 60; // 60 seconds default
        minUpdateInterval = 1; // 1 second minimum

        // Set initial price
        latestPrice = PriceData({
            price: _initialPrice,
            timestamp: block.timestamp,
            roundId: 1
        });

        priceHistory.push(latestPrice);

        emit PriceUpdated(1, _initialPrice, block.timestamp, msg.sender);
    }

    /**
     * @notice Update price (only authorized feeders)
     * @param newPrice New price to set
     */
    function updatePrice(uint256 newPrice) external whenNotPaused {
        require(authorizedFeeders[msg.sender], "PriceOracle: Not authorized");
        require(newPrice > 0, "PriceOracle: Invalid price");
        
        // Check minimum update interval
        require(
            block.timestamp >= lastUpdateTime + minUpdateInterval,
            "PriceOracle: Too frequent"
        );

        // Validate price deviation
        if (latestPrice.price > 0) {
            require(
                SafetyChecks.validatePriceDeviation(
                    latestPrice.price,
                    newPrice,
                    maxPriceDeviation
                ),
                "PriceOracle: Price deviation too large"
            );
        }

        // Update latest price
        uint256 newRoundId = latestPrice.roundId + 1;
        latestPrice = PriceData({
            price: newPrice,
            timestamp: block.timestamp,
            roundId: newRoundId
        });

        // Add to history
        _addToHistory(latestPrice);

        lastUpdateTime = block.timestamp;

        emit PriceUpdated(newRoundId, newPrice, block.timestamp, msg.sender);
    }

    /**
     * @notice Get latest price with staleness check
     * @return price Current price
     * @return timestamp Price timestamp
     */
    function getLatestPrice() external view returns (uint256 price, uint256 timestamp) {
        _checkStale();
        
        return (latestPrice.price, latestPrice.timestamp);
    }

    /**
     * @notice Get TWAP over a specified period
     * @param period Time period in seconds
     * @return twap Time-weighted average price
     */
    function getTWAP(uint256 period) external view returns (uint256 twap) {
        require(period > 0, "PriceOracle: Invalid period");
        require(priceHistory.length >= 2, "PriceOracle: Insufficient data");

        uint256 currentTime = block.timestamp;
        uint256 startTime = currentTime > period ? currentTime - period : 0;

        uint256[] memory prices = new uint256[](priceHistory.length);
        uint256[] memory timestamps = new uint256[](priceHistory.length);

        for (uint256 i = 0; i < priceHistory.length; i++) {
            prices[i] = priceHistory[i].price;
            timestamps[i] = priceHistory[i].timestamp;
        }

        return Math.calculateTWAP(prices, timestamps, period);
    }

    /**
     * @notice Get price at a specific round
     * @param roundId Round ID to query
     * @return price Price at that round
     * @return timestamp Timestamp of that round
     */
    function getPriceAtRound(uint256 roundId) external view returns (uint256 price, uint256 timestamp) {
        require(roundId > 0 && roundId <= latestPrice.roundId, "PriceOracle: Invalid round");
        
        // Search through history (most recent first)
        for (uint256 i = priceHistory.length; i > 0; i--) {
            if (priceHistory[i - 1].roundId == roundId) {
                return (priceHistory[i - 1].price, priceHistory[i - 1].timestamp);
            }
        }
        
        revert("PriceOracle: Round not found");
    }

    /**
     * @notice Add/remove authorized feeder
     * @param feeder Feeder address
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedFeeder(address feeder, bool authorized) external onlyOwner {
        require(feeder != address(0), "PriceOracle: Invalid feeder");
        
        authorizedFeeders[feeder] = authorized;

        emit FeederAuthorized(feeder, authorized);
    }

    /**
     * @notice Set maximum price deviation
     * @param _maxPriceDeviation New max deviation in basis points
     */
    function setMaxDeviation(uint256 _maxPriceDeviation) external onlyOwner {
        require(_maxPriceDeviation > 0 && _maxPriceDeviation <= 10000, "PriceOracle: Invalid deviation");
        
        uint256 oldDeviation = maxPriceDeviation;
        maxPriceDeviation = _maxPriceDeviation;

        emit MaxDeviationUpdated(oldDeviation, _maxPriceDeviation);
    }

    /**
     * @notice Set heartbeat timeout
     * @param _heartbeatTimeout New timeout in seconds
     */
    function setHeartbeatTimeout(uint256 _heartbeatTimeout) external onlyOwner {
        require(_heartbeatTimeout > 0, "PriceOracle: Invalid timeout");
        
        uint256 oldTimeout = heartbeatTimeout;
        heartbeatTimeout = _heartbeatTimeout;

        emit HeartbeatUpdated(oldTimeout, _heartbeatTimeout);
    }

    /**
     * @notice Set minimum update interval
     * @param _minUpdateInterval New minimum interval in seconds
     */
    function setMinUpdateInterval(uint256 _minUpdateInterval) external onlyOwner {
        minUpdateInterval = _minUpdateInterval;
    }

    /**
     * @notice Emergency freeze prices
     */
    function freezePrices() external onlyOwner {
        _pause();
        emit PricesFrozen(block.timestamp);
    }

    /**
     * @notice Unfreeze prices
     */
    function unfreezePrices() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Check if price is stale
     * @return bool True if stale
     */
    function isPriceStale() public view returns (bool) {
        return SafetyChecks.isPriceStale(latestPrice.timestamp, heartbeatTimeout);
    }

    /**
     * @notice Get price history length
     * @return uint256 History length
     */
    function getHistoryLength() external view returns (uint256) {
        return priceHistory.length;
    }

    /**
     * @notice Internal function to add price to history
     * @param priceData Price data to add
     */
    function _addToHistory(PriceData memory priceData) private {
        priceHistory.push(priceData);

        // Trim history if too long (keep recent prices)
        if (priceHistory.length > MAX_HISTORY_LENGTH) {
            // Remove oldest entry
            for (uint256 i = 0; i < priceHistory.length - 1; i++) {
                priceHistory[i] = priceHistory[i + 1];
            }
            priceHistory.pop();
        }
    }

    /**
     * @notice Internal function to check if price is stale
     */
    function _checkStale() private view {
        require(!isPriceStale(), "PriceOracle: Price is stale");
    }
}
