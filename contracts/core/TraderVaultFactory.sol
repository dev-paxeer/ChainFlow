// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./TraderVault.sol";
import "../reputation/ReputationNFT.sol";
import "../governance/TreasuryManager.sol";
import "../synthetics/TradingVault.sol";
import "../synthetics/OracleRegistry.sol";

/**
 * @title TraderVaultFactory
 * @notice Factory for deploying TraderVault contracts for funded traders
 * @dev Verifies ReputationNFT ownership before deployment and manages vault configuration
 */
contract TraderVaultFactory is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Vault configuration structure
    struct VaultConfig {
        uint256 initialCapital;      // Starting capital
        uint256 maxPositionSize;     // Max single position
        uint256 maxDailyLoss;        // Daily loss limit
        uint256 profitSplitBps;      // Trader's share (e.g., 8000 = 80%)
    }

    /// @notice Reputation NFT contract
    ReputationNFT public immutable reputationNFT;

    /// @notice Treasury manager
    TreasuryManager public immutable treasury;

    /// @notice Trading vault
    TradingVault public immutable tradingVault;

    /// @notice Oracle registry
    OracleRegistry public immutable oracleRegistry;

    /// @notice Collateral token (USDC)
    IERC20 public immutable collateralToken;

    /// @notice Default vault configuration
    VaultConfig public defaultConfig;

    /// @notice Mapping from trader to vault address
    mapping(address => address) public traderToVault;

    /// @notice Array of all deployed vaults
    address[] public allVaults;

    /// @notice Mapping to check if address is a vault
    mapping(address => bool) public isVault;

    /// Events
    event VaultDeployed(
        address indexed trader,
        address indexed vault,
        uint256 initialCapital,
        uint256 timestamp
    );

    event ConfigUpdated(
        uint256 initialCapital,
        uint256 maxPositionSize,
        uint256 maxDailyLoss,
        uint256 profitSplitBps
    );

    event VaultFunded(address indexed vault, uint256 amount);

    /**
     * @notice Constructor
     * @param _reputationNFT Reputation NFT address
     * @param _treasury Treasury manager address
     * @param _tradingVault Trading vault address
     * @param _oracleRegistry Oracle registry address
     * @param _collateralToken USDC token address
     * @param _initialOwner Initial owner
     */
    constructor(
        address _reputationNFT,
        address _treasury,
        address _tradingVault,
        address _oracleRegistry,
        address _collateralToken,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_reputationNFT != address(0), "Factory: Invalid NFT");
        require(_treasury != address(0), "Factory: Invalid treasury");
        require(_tradingVault != address(0), "Factory: Invalid trading vault");
        require(_oracleRegistry != address(0), "Factory: Invalid oracle");
        require(_collateralToken != address(0), "Factory: Invalid token");

        reputationNFT = ReputationNFT(_reputationNFT);
        treasury = TreasuryManager(_treasury);
        tradingVault = TradingVault(_tradingVault);
        oracleRegistry = OracleRegistry(_oracleRegistry);
        collateralToken = IERC20(_collateralToken);

        // Set default configuration
        defaultConfig = VaultConfig({
            initialCapital: 100000 * 1e6,    // 100,000 USDC
            maxPositionSize: 10000 * 1e6,    // 10,000 USDC
            maxDailyLoss: 2000 * 1e6,        // 2,000 USDC
            profitSplitBps: 8000             // 80% to trader
        });
    }

    /**
     * @notice Deploy a new trader vault
     * @dev Requires caller to hold ReputationNFT
     * @return vault Address of deployed vault
     */
    function deployVault() external nonReentrant whenNotPaused returns (address vault) {
        // Verify caller has ReputationNFT
        require(
            reputationNFT.hasValidCredential(msg.sender),
            "Factory: No valid credential"
        );

        // Verify no existing vault
        require(
            traderToVault[msg.sender] == address(0),
            "Factory: Vault already exists"
        );

        // Deploy new TraderVault
        vault = address(new TraderVault(
            msg.sender,                          // owner (trader)
            owner(),                             // admin
            address(treasury),                   // treasury
            address(tradingVault),               // trading vault
            address(oracleRegistry),             // oracle registry
            address(collateralToken),            // collateral token
            defaultConfig.initialCapital,        // initial capital
            defaultConfig.maxPositionSize,       // max position size
            defaultConfig.maxDailyLoss,          // max daily loss
            defaultConfig.profitSplitBps         // profit split
        ));

        // Store mapping
        traderToVault[msg.sender] = vault;
        allVaults.push(vault);
        isVault[vault] = true;

        // Authorize vault in TradingVault
        tradingVault.setAuthorizedTrader(vault, true);

        // Fund the vault from treasury
        treasury.allocateToVault(vault, defaultConfig.initialCapital);

        // Sync vault balance with received funds
        TraderVault(payable(vault)).syncBalance();

        emit VaultDeployed(msg.sender, vault, defaultConfig.initialCapital, block.timestamp);
        emit VaultFunded(vault, defaultConfig.initialCapital);

        return vault;
    }

    /**
     * @notice Deploy vault with custom configuration (admin only)
     * @param trader Trader address
     * @param config Custom vault configuration
     * @return vault Address of deployed vault
     */
    function deployVaultWithConfig(
        address trader,
        VaultConfig calldata config
    ) external onlyOwner nonReentrant whenNotPaused returns (address vault) {
        require(trader != address(0), "Factory: Invalid trader");
        require(
            reputationNFT.hasValidCredential(trader),
            "Factory: No valid credential"
        );
        require(
            traderToVault[trader] == address(0),
            "Factory: Vault already exists"
        );
        require(config.initialCapital > 0, "Factory: Invalid capital");
        require(config.profitSplitBps <= 10000, "Factory: Invalid split");

        // Deploy new TraderVault
        vault = address(new TraderVault(
            trader,
            owner(),
            address(treasury),
            address(tradingVault),
            address(oracleRegistry),
            address(collateralToken),
            config.initialCapital,
            config.maxPositionSize,
            config.maxDailyLoss,
            config.profitSplitBps
        ));

        // Store mapping
        traderToVault[trader] = vault;
        allVaults.push(vault);
        isVault[vault] = true;

        // Authorize vault
        tradingVault.setAuthorizedTrader(vault, true);

        // Fund the vault
        treasury.allocateToVault(vault, config.initialCapital);

        // Sync vault balance with received funds
        TraderVault(payable(vault)).syncBalance();

        emit VaultDeployed(trader, vault, config.initialCapital, block.timestamp);
        emit VaultFunded(vault, config.initialCapital);

        return vault;
    }

    /**
     * @notice Set default vault configuration
     * @param config New default configuration
     */
    function setDefaultConfig(VaultConfig calldata config) external onlyOwner {
        require(config.initialCapital > 0, "Factory: Invalid capital");
        require(config.profitSplitBps <= 10000, "Factory: Invalid split");

        defaultConfig = config;

        emit ConfigUpdated(
            config.initialCapital,
            config.maxPositionSize,
            config.maxDailyLoss,
            config.profitSplitBps
        );
    }

    /**
     * @notice Get vault address for a trader
     * @param trader Trader address
     * @return address Vault address (0 if none)
     */
    function getVaultByTrader(address trader) external view returns (address) {
        return traderToVault[trader];
    }

    /**
     * @notice Get all deployed vaults
     * @return address[] Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @notice Get number of deployed vaults
     * @return uint256 Total count
     */
    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @notice Get vault at index
     * @param index Array index
     * @return address Vault address
     */
    function getVaultAt(uint256 index) external view returns (address) {
        require(index < allVaults.length, "Factory: Index out of bounds");
        return allVaults[index];
    }

    /**
     * @notice Check if trader has a vault
     * @param trader Trader address
     * @return bool True if vault exists
     */
    function hasVault(address trader) external view returns (bool) {
        return traderToVault[trader] != address(0);
    }

    /**
     * @notice Get vault statistics
     * @param trader Trader address
     * @return exists True if vault exists
     * @return vault Vault address
     * @return balance Current balance
     * @return profit Available profit
     */
    function getVaultStats(address trader) external view returns (
        bool exists,
        address vault,
        uint256 balance,
        uint256 profit
    ) {
        vault = traderToVault[trader];
        exists = vault != address(0);

        if (exists) {
            TraderVault tv = TraderVault(payable(vault));
            (balance, , , profit, ) = tv.getVaultStats();
        }
    }

    /**
     * @notice Pause factory (stops new deployments)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause factory
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Calculate predictable vault address (CREATE2)
     * @param trader Trader address
     * @param salt Salt for deterministic deployment
     * @return address Predicted vault address
     */
    function predictVaultAddress(
        address trader,
        bytes32 salt
    ) external view returns (address) {
        bytes memory bytecode = type(TraderVault).creationCode;
        bytes memory constructorArgs = abi.encode(
            trader,
            owner(),
            address(treasury),
            address(tradingVault),
            address(oracleRegistry),
            address(collateralToken),
            defaultConfig.initialCapital,
            defaultConfig.maxPositionSize,
            defaultConfig.maxDailyLoss,
            defaultConfig.profitSplitBps
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(abi.encodePacked(bytecode, constructorArgs))
            )
        );

        return address(uint160(uint256(hash)));
    }
}
