// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuPremium} from "./IBiuBiuPremium.sol";

/**
 * @title INFTFactory
 * @notice Interface for NFTFactory ERC721 NFT collection creation
 * @dev Stable API for frontend and other contracts to interact with NFTFactory
 */
interface INFTFactory {
    // ============ Events ============

    event NFTCreated(
        address indexed nftAddress,
        address indexed creator,
        string name,
        string symbol,
        string description,
        uint8 usageType
    );
    event ReferralPaid(address indexed referrer, address indexed payer, uint256 amount);
    event FeePaid(address indexed payer, uint256 amount);

    // ============ Constants ============

    function USAGE_FREE() external view returns (uint8);
    function USAGE_PREMIUM() external view returns (uint8);
    function USAGE_PAID() external view returns (uint8);

    // ============ State Variables ============

    function PREMIUM_CONTRACT() external view returns (IBiuBiuPremium);
    function VAULT() external view returns (address);
    function NON_MEMBER_FEE() external view returns (uint256);
    function totalFreeUsage() external view returns (uint256);
    function totalPremiumUsage() external view returns (uint256);
    function totalPaidUsage() external view returns (uint256);

    // ============ Main Functions ============

    /**
     * @notice Create ERC721 NFT Collection (paid version)
     * @param name Collection name
     * @param symbol Collection symbol
     * @param description Collection description
     * @param externalURL Project website URL
     * @param referrer Referrer address for fee sharing
     * @return NFT contract address
     */
    function createERC721(
        string memory name,
        string memory symbol,
        string memory description,
        string memory externalURL,
        address referrer
    ) external payable returns (address);

    /**
     * @notice Create ERC721 NFT Collection (free version)
     * @param name Collection name
     * @param symbol Collection symbol
     * @param description Collection description
     * @param externalURL Project website URL
     * @return NFT contract address
     */
    function createERC721Free(
        string memory name,
        string memory symbol,
        string memory description,
        string memory externalURL
    ) external returns (address);

    // ============ Query Functions ============

    /**
     * @notice Get total number of NFTs created
     */
    function allNFTsLength() external view returns (uint256);

    /**
     * @notice Get number of NFTs created by a specific user
     */
    function userNFTsLength(address user) external view returns (uint256);

    /**
     * @notice Get all NFTs created by a specific user
     */
    function getUserNFTs(address user) external view returns (address[] memory);

    /**
     * @notice Get all NFTs created through this factory
     */
    function getAllNFTs() external view returns (address[] memory);

    /**
     * @notice Get user NFTs with pagination
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nfts Array of NFT addresses
     * @return total Total number of NFTs for this user
     */
    function getUserNFTsPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total);

    /**
     * @notice Get all NFTs with pagination
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nfts Array of NFT addresses
     * @return total Total number of NFTs
     */
    function getAllNFTsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total);

    /**
     * @notice Get NFT address at index
     */
    function allNFTs(uint256 index) external view returns (address);

    /**
     * @notice Get user NFT address at index
     */
    function userNFTs(address user, uint256 index) external view returns (address);
}
