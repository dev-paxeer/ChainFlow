// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PriceOracle.sol";

/**
 * @title OracleRegistry
 * @notice Central registry for all price oracles
 * @dev Maps asset symbols to oracle contracts and provides validation
 */
contract OracleRegistry is Ownable {
    
    /// @notice Mapping from asset symbol to oracle address
    mapping(string => address) public oracles;

    /// @notice List of all registered symbols
    string[] public registeredSymbols;

    /// @notice Mapping to check if symbol is registered
    mapping(string => bool) public isRegistered;

    /// Events
    event OracleRegistered(string indexed symbol, address indexed oracle);
    event OracleUpdated(string indexed symbol, address indexed oldOracle, address indexed newOracle);
    event OracleRemoved(string indexed symbol, address indexed oracle);

    /**
     * @notice Constructor
     * @param _initialOwner Initial owner address
     */
    constructor(address _initialOwner) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "OracleRegistry: Invalid owner");
    }

    /**
     * @notice Register a new oracle
     * @param symbol Asset symbol (e.g., "BTC/USD")
     * @param oracle Oracle contract address
     */
    function registerOracle(string calldata symbol, address oracle) external onlyOwner {
        require(bytes(symbol).length > 0, "OracleRegistry: Invalid symbol");
        require(oracle != address(0), "OracleRegistry: Invalid oracle");
        require(!isRegistered[symbol], "OracleRegistry: Already registered");

        oracles[symbol] = oracle;
        isRegistered[symbol] = true;
        registeredSymbols.push(symbol);

        emit OracleRegistered(symbol, oracle);
    }

    /**
     * @notice Update an existing oracle
     * @param symbol Asset symbol
     * @param newOracle New oracle address
     */
    function updateOracle(string calldata symbol, address newOracle) external onlyOwner {
        require(isRegistered[symbol], "OracleRegistry: Not registered");
        require(newOracle != address(0), "OracleRegistry: Invalid oracle");

        address oldOracle = oracles[symbol];
        oracles[symbol] = newOracle;

        emit OracleUpdated(symbol, oldOracle, newOracle);
    }

    /**
     * @notice Remove an oracle
     * @param symbol Asset symbol
     */
    function removeOracle(string calldata symbol) external onlyOwner {
        require(isRegistered[symbol], "OracleRegistry: Not registered");

        address oracle = oracles[symbol];
        delete oracles[symbol];
        isRegistered[symbol] = false;

        // Remove from registeredSymbols array
        for (uint256 i = 0; i < registeredSymbols.length; i++) {
            if (keccak256(bytes(registeredSymbols[i])) == keccak256(bytes(symbol))) {
                registeredSymbols[i] = registeredSymbols[registeredSymbols.length - 1];
                registeredSymbols.pop();
                break;
            }
        }

        emit OracleRemoved(symbol, oracle);
    }

    /**
     * @notice Get oracle address for a symbol
     * @param symbol Asset symbol
     * @return address Oracle address
     */
    function getOracle(string calldata symbol) external view returns (address) {
        require(isRegistered[symbol], "OracleRegistry: Oracle not found");
        return oracles[symbol];
    }

    /**
     * @notice Get latest price from an oracle
     * @param symbol Asset symbol
     * @return price Latest price
     * @return timestamp Price timestamp
     */
    function getLatestPrice(string calldata symbol) external view returns (uint256 price, uint256 timestamp) {
        require(isRegistered[symbol], "OracleRegistry: Oracle not found");
        
        PriceOracle oracle = PriceOracle(oracles[symbol]);
        return oracle.getLatestPrice();
    }

    /**
     * @notice Validate oracle health
     * @param symbol Asset symbol
     * @return bool True if oracle is healthy
     */
    function validateOracle(string calldata symbol) external view returns (bool) {
        if (!isRegistered[symbol]) return false;
        
        PriceOracle oracle = PriceOracle(oracles[symbol]);
        
        // Check if oracle is not paused
        if (oracle.paused()) return false;
        
        // Check if price is not stale
        if (oracle.isPriceStale()) return false;
        
        // Check if latest price is valid
        (uint256 price, ) = oracle.getLatestPrice();
        if (price == 0) return false;
        
        return true;
    }

    /**
     * @notice Get all registered symbols
     * @return string[] Array of symbols
     */
    function getAllSymbols() external view returns (string[] memory) {
        return registeredSymbols;
    }

    /**
     * @notice Get number of registered oracles
     * @return uint256 Count
     */
    function getOracleCount() external view returns (uint256) {
        return registeredSymbols.length;
    }

    /**
     * @notice Check if oracle exists and is healthy
     * @param oracle Oracle address
     * @return bool True if valid
     */
    function isValidOracle(address oracle) external view returns (bool) {
        if (oracle == address(0)) return false;

        // Check if oracle is registered
        for (uint256 i = 0; i < registeredSymbols.length; i++) {
            if (oracles[registeredSymbols[i]] == oracle) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Get TWAP from oracle
     * @param symbol Asset symbol
     * @param period Time period for TWAP
     * @return twap Time-weighted average price
     */
    function getTWAP(string calldata symbol, uint256 period) external view returns (uint256 twap) {
        require(isRegistered[symbol], "OracleRegistry: Oracle not found");
        
        PriceOracle oracle = PriceOracle(oracles[symbol]);
        return oracle.getTWAP(period);
    }
}
