// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TreasuryManager
 * @notice Manages the firm's capital pool and allocations to trader vaults
 * @dev Handles USDC deposits, vault funding, and profit collection
 */
contract TreasuryManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice USDC token address
    IERC20 public immutable collateralToken;

    /// @notice Authorized factory that can allocate capital
    address public vaultFactory;

    /// @notice Total capital allocated to active vaults
    uint256 public totalAllocated;

    /// @notice Total profit received from vaults
    uint256 public totalProfitCollected;

    /// @notice Mapping of vault address to allocated amount
    mapping(address => uint256) public vaultAllocations;

    /// @notice Mapping of authorized allocators
    mapping(address => bool) public authorizedAllocators;

    /// Events
    event CapitalDeposited(address indexed depositor, uint256 amount);
    event CapitalWithdrawn(address indexed recipient, uint256 amount);
    event CapitalAllocated(address indexed vault, uint256 amount);
    event ProfitReceived(address indexed vault, uint256 amount);
    event VaultFactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event AllocatorAuthorized(address indexed allocator, bool authorized);

    /**
     * @notice Constructor
     * @param _collateralToken USDC token address
     * @param _initialOwner Initial owner address
     */
    constructor(
        address _collateralToken,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_collateralToken != address(0), "TreasuryManager: Invalid token");
        require(_initialOwner != address(0), "TreasuryManager: Invalid owner");

        collateralToken = IERC20(_collateralToken);
    }

    /**
     * @notice Deposit capital into treasury
     * @param amount Amount of USDC to deposit
     */
    function depositCapital(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "TreasuryManager: Invalid amount");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        emit CapitalDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw capital from treasury (owner only)
     * @param amount Amount to withdraw
     * @param recipient Recipient address
     */
    function withdrawCapital(
        uint256 amount,
        address recipient
    ) external onlyOwner nonReentrant {
        require(amount > 0, "TreasuryManager: Invalid amount");
        require(recipient != address(0), "TreasuryManager: Invalid recipient");
        
        uint256 availableBalance = getAvailableBalance();
        require(amount <= availableBalance, "TreasuryManager: Insufficient available balance");

        collateralToken.safeTransfer(recipient, amount);

        emit CapitalWithdrawn(recipient, amount);
    }

    /**
     * @notice Allocate capital to a vault (only authorized allocators)
     * @param vault Vault address to fund
     * @param amount Amount to allocate
     */
    function allocateToVault(
        address vault,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(
            authorizedAllocators[msg.sender],
            "TreasuryManager: Not authorized"
        );
        require(vault != address(0), "TreasuryManager: Invalid vault");
        require(amount > 0, "TreasuryManager: Invalid amount");

        uint256 availableBalance = getAvailableBalance();
        require(amount <= availableBalance, "TreasuryManager: Insufficient balance");

        // Update tracking
        vaultAllocations[vault] += amount;
        totalAllocated += amount;

        // Transfer funds to vault
        collateralToken.safeTransfer(vault, amount);

        emit CapitalAllocated(vault, amount);
    }

    /**
     * @notice Receive profit from a vault
     * @param amount Profit amount
     * @dev Called by TraderVault contracts when profit is distributed
     */
    function receiveProfit(uint256 amount) external nonReentrant {
        require(amount > 0, "TreasuryManager: Invalid amount");
        require(vaultAllocations[msg.sender] > 0, "TreasuryManager: Unknown vault");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        totalProfitCollected += amount;

        emit ProfitReceived(msg.sender, amount);
    }

    /**
     * @notice Deallocate capital when a vault is closed
     * @param vault Vault address
     * @param amount Amount to deallocate
     */
    function deallocateFromVault(
        address vault,
        uint256 amount
    ) external {
        require(
            authorizedAllocators[msg.sender],
            "TreasuryManager: Not authorized"
        );
        require(vault != address(0), "TreasuryManager: Invalid vault");
        require(amount > 0, "TreasuryManager: Invalid amount");
        require(amount <= vaultAllocations[vault], "TreasuryManager: Invalid amount");

        vaultAllocations[vault] -= amount;
        totalAllocated -= amount;
    }

    /**
     * @notice Set authorized allocator (only owner)
     * @param allocator Address to authorize/deauthorize
     * @param authorized True to authorize, false to deauthorize
     */
    function setAuthorizedAllocator(
        address allocator,
        bool authorized
    ) external onlyOwner {
        require(allocator != address(0), "TreasuryManager: Invalid allocator");
        
        authorizedAllocators[allocator] = authorized;

        emit AllocatorAuthorized(allocator, authorized);
    }

    /**
     * @notice Set vault factory address (only owner)
     * @param _vaultFactory New factory address
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        require(_vaultFactory != address(0), "TreasuryManager: Invalid factory");
        
        address oldFactory = vaultFactory;
        
        // Revoke old factory authorization
        if (oldFactory != address(0)) {
            authorizedAllocators[oldFactory] = false;
        }
        
        // Authorize new factory
        vaultFactory = _vaultFactory;
        authorizedAllocators[_vaultFactory] = true;

        emit VaultFactoryUpdated(oldFactory, _vaultFactory);
        emit AllocatorAuthorized(_vaultFactory, true);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Get total treasury balance
     * @return uint256 Total balance
     */
    function getTreasuryBalance() external view returns (uint256) {
        return collateralToken.balanceOf(address(this));
    }

    /**
     * @notice Get available balance (total - allocated)
     * @return uint256 Available balance
     */
    function getAvailableBalance() public view returns (uint256) {
        uint256 totalBalance = collateralToken.balanceOf(address(this));
        return totalBalance > totalAllocated ? totalBalance - totalAllocated : 0;
    }

    /**
     * @notice Get allocation for a specific vault
     * @param vault Vault address
     * @return uint256 Allocated amount
     */
    function getVaultAllocation(address vault) external view returns (uint256) {
        return vaultAllocations[vault];
    }

    /**
     * @notice Emergency withdraw all funds (only owner, when paused)
     * @param recipient Recipient address
     */
    function emergencyWithdraw(address recipient) external onlyOwner whenPaused {
        require(recipient != address(0), "TreasuryManager: Invalid recipient");
        
        uint256 balance = collateralToken.balanceOf(address(this));
        require(balance > 0, "TreasuryManager: No balance");

        collateralToken.safeTransfer(recipient, balance);

        emit CapitalWithdrawn(recipient, balance);
    }
}
