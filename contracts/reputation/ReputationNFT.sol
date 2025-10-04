// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ReputationNFT
 * @notice Non-transferable (Soulbound) NFT representing successful evaluation completion
 * @dev ERC-721 compliant but blocks all transfers except minting and burning
 */
contract ReputationNFT is ERC721, AccessControl, Pausable {

    /// @notice Role that can mint new reputation NFTs
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @notice Role for emergency admin functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Token ID counter
    uint256 private _tokenIdCounter;

    /// @notice Base URI for token metadata
    string private _baseTokenURI;

    /// @notice Metadata for each evaluation
    struct EvaluationMetadata {
        uint256 evaluationId;
        uint256 completionTime;
        uint256 finalBalance;
        uint256 profitAchieved;
        uint256 maxDrawdown;
        uint256 totalTrades;
        uint256 winRate; // In basis points (e.g., 6500 = 65%)
        bool isValid;
    }

    /// @notice Mapping from token ID to evaluation metadata
    mapping(uint256 => EvaluationMetadata) public tokenMetadata;

    /// @notice Mapping from trader address to token ID (one NFT per address)
    mapping(address => uint256) public traderToTokenId;

    /// @notice Mapping to check if address has credential
    mapping(address => bool) public hasCredential;

    /// Events
    event CredentialMinted(
        address indexed trader,
        uint256 indexed tokenId,
        uint256 evaluationId,
        uint256 profitAchieved
    );
    
    event CredentialRevoked(
        address indexed trader,
        uint256 indexed tokenId,
        string reason
    );

    event BaseURIUpdated(string newBaseURI);

    /**
     * @notice Constructor
     * @param admin Address with admin privileges
     * @param baseURI Base URI for token metadata
     */
    constructor(
        address admin,
        string memory baseURI
    ) ERC721("ChainProp Trader Credential", "CPTC") {
        require(admin != address(0), "ReputationNFT: Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _baseTokenURI = baseURI;
    }

    /**
     * @notice Mint a new reputation NFT to a trader
     * @param trader Address of the trader
     * @param evaluationId ID of the completed evaluation
     * @param finalBalance Final balance achieved
     * @param profitAchieved Profit amount achieved
     * @param maxDrawdown Maximum drawdown experienced
     * @param totalTrades Total number of trades executed
     * @param winRate Win rate in basis points
     * @return tokenId The minted token ID
     */
    function mint(
        address trader,
        uint256 evaluationId,
        uint256 finalBalance,
        uint256 profitAchieved,
        uint256 maxDrawdown,
        uint256 totalTrades,
        uint256 winRate
    ) external onlyRole(MINTER_ROLE) whenNotPaused returns (uint256 tokenId) {
        require(trader != address(0), "ReputationNFT: Invalid trader");
        require(!hasCredential[trader], "ReputationNFT: Trader already has credential");
        require(profitAchieved > 0, "ReputationNFT: Invalid profit");

        _tokenIdCounter++;
        tokenId = _tokenIdCounter;

        // Mint the token
        _safeMint(trader, tokenId);

        // Store metadata
        tokenMetadata[tokenId] = EvaluationMetadata({
            evaluationId: evaluationId,
            completionTime: block.timestamp,
            finalBalance: finalBalance,
            profitAchieved: profitAchieved,
            maxDrawdown: maxDrawdown,
            totalTrades: totalTrades,
            winRate: winRate,
            isValid: true
        });

        // Update mappings
        traderToTokenId[trader] = tokenId;
        hasCredential[trader] = true;

        emit CredentialMinted(trader, tokenId, evaluationId, profitAchieved);
    }

    /**
     * @notice Revoke a credential (burns the NFT)
     * @param trader Address of the trader
     * @param reason Reason for revocation
     */
    function revokeCredential(
        address trader,
        string calldata reason
    ) external onlyRole(ADMIN_ROLE) {
        require(hasCredential[trader], "ReputationNFT: No credential to revoke");
        
        uint256 tokenId = traderToTokenId[trader];
        
        // Mark as invalid
        tokenMetadata[tokenId].isValid = false;
        
        // Update mappings
        hasCredential[trader] = false;
        
        // Burn the token
        _burn(tokenId);

        emit CredentialRevoked(trader, tokenId, reason);
    }

    /**
     * @notice Get metadata for a token
     * @param tokenId Token ID to query
     * @return metadata The evaluation metadata
     */
    function getMetadata(uint256 tokenId) external view returns (EvaluationMetadata memory) {
        require(_ownerOf(tokenId) != address(0), "ReputationNFT: Token does not exist");
        return tokenMetadata[tokenId];
    }

    /**
     * @notice Get token ID for a trader
     * @param trader Trader address
     * @return tokenId The token ID (0 if none)
     */
    function getTokenId(address trader) external view returns (uint256) {
        return traderToTokenId[trader];
    }

    /**
     * @notice Check if an address has a valid credential
     * @param trader Trader address
     * @return bool True if trader has valid credential
     */
    function hasValidCredential(address trader) external view returns (bool) {
        if (!hasCredential[trader]) return false;
        
        uint256 tokenId = traderToTokenId[trader];
        return tokenMetadata[tokenId].isValid;
    }

    /**
     * @notice Set base URI for token metadata
     * @param baseURI New base URI
     */
    function setBaseURI(string calldata baseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Override to return base URI
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Block all transfers except minting and burning
     * @dev This makes the token soulbound (non-transferable)
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == address(0))
        // Allow burning (to == address(0))
        // Block all other transfers
        if (from != address(0) && to != address(0)) {
            revert("ReputationNFT: Token is non-transferable");
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Get total number of credentials minted
     * @return uint256 Total supply
     */
    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @notice Required override for AccessControl
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
