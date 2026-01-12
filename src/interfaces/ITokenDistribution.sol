// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWETH} from "./IWETH.sol";

/**
 * @title ITokenDistribution
 * @notice Interface for TokenDistribution batch token distribution
 * @dev Stable API for frontend and other contracts to interact with TokenDistribution
 */

struct Recipient {
    address to;
    uint256 value; // ERC20/ETH/ERC1155: amount, ERC721: tokenId
}

struct DistributionAuth {
    bytes32 uuid;
    address token;
    uint8 tokenType;
    uint256 tokenId; // ERC1155 only
    uint256 totalAmount;
    uint256 totalBatches;
    bytes32 merkleRoot;
    uint256 deadline;
}

struct FailedTransfer {
    address to;
    uint256 value;
    bytes reason;
}

interface ITokenDistribution {
    // ============ Events ============

    event Distributed(
        address indexed sender,
        address indexed token,
        uint8 tokenType,
        uint256 recipientCount,
        uint256 totalAmount,
        uint8 usageType
    );
    event DistributedWithAuth(
        bytes32 indexed uuid,
        address indexed signer,
        uint256 batchId,
        uint256 recipientCount,
        uint256 batchAmount,
        uint8 usageType
    );
    event TransferSkipped(address indexed recipient, uint256 value, bytes reason);
    event Refunded(address indexed to, uint256 amount);
    event FeeCollected(address indexed payer, uint256 amount);
    event ReferralPaid(address indexed referrer, uint256 amount);

    // ============ Constants ============

    function MAX_BATCH_SIZE() external view returns (uint256);
    function TOKEN_TYPE_WETH() external view returns (uint8);
    function TOKEN_TYPE_ERC20() external view returns (uint8);
    function TOKEN_TYPE_ERC721() external view returns (uint8);
    function TOKEN_TYPE_ERC1155() external view returns (uint8);
    function USAGE_FREE() external view returns (uint8);
    function USAGE_PAID() external view returns (uint8);
    function VAULT() external view returns (address);
    function NON_MEMBER_FEE() external view returns (uint256);
    function DOMAIN_TYPEHASH() external view returns (bytes32);
    function DISTRIBUTION_AUTH_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ============ State Variables ============

    function WETH() external view returns (IWETH);
    function totalFreeUsage() external view returns (uint256);
    function totalPaidUsage() external view returns (uint256);
    function totalFreeAuthUsage() external view returns (uint256);
    function totalPaidAuthUsage() external view returns (uint256);

    // ============ Main Functions ============

    /**
     * @notice Self-execute distribution (owner sends transaction) - paid version
     * @param token Token address (address(0) for native ETH)
     * @param tokenType Token type (0=WETH not allowed here, 1=ERC20, 2=ERC721, 3=ERC1155)
     * @param tokenId ERC1155 token ID (0 for others)
     * @param recipients List of recipients (max 100)
     * @param referrer Referrer address for fee sharing
     * @return totalDistributed Total amount successfully distributed
     * @return failed Array of failed transfers with details (address, value, reason)
     */
    function distribute(
        address token,
        uint8 tokenType,
        uint256 tokenId,
        Recipient[] calldata recipients,
        address referrer
    ) external payable returns (uint256 totalDistributed, FailedTransfer[] memory failed);

    /**
     * @notice Self-execute distribution (free version)
     * @param token Token address (address(0) for native ETH)
     * @param tokenType Token type (0=WETH not allowed here, 1=ERC20, 2=ERC721, 3=ERC1155)
     * @param tokenId ERC1155 token ID (0 for others)
     * @param recipients List of recipients (max 100)
     * @return totalDistributed Total amount successfully distributed
     * @return failed Array of failed transfers with details (address, value, reason)
     */
    function distributeFree(address token, uint8 tokenType, uint256 tokenId, Recipient[] calldata recipients)
        external
        payable
        returns (uint256 totalDistributed, FailedTransfer[] memory failed);

    /**
     * @notice Delegated execute distribution (executor sends transaction on behalf of owner) - paid version
     * @param auth Authorization struct signed by owner
     * @param signature Owner's EIP-712 signature
     * @param batchId Batch number to execute
     * @param recipients Recipients for this batch
     * @param proofs Flattened Merkle proofs for all recipients
     * @param proofLengths Length of each recipient's proof
     * @param referrer Referrer address for fee sharing
     * @return batchAmount Total amount successfully distributed in this batch
     * @return failed Array of failed transfers with details (address, value, reason)
     */
    function distributeWithAuth(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths,
        address referrer
    ) external payable returns (uint256 batchAmount, FailedTransfer[] memory failed);

    /**
     * @notice Delegated execute distribution (free version)
     * @param auth Authorization struct signed by owner
     * @param signature Owner's EIP-712 signature
     * @param batchId Batch number to execute
     * @param recipients Recipients for this batch
     * @param proofs Flattened Merkle proofs for all recipients
     * @param proofLengths Length of each recipient's proof
     * @return batchAmount Total amount successfully distributed in this batch
     * @return failed Array of failed transfers with details (address, value, reason)
     */
    function distributeWithAuthFree(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths
    ) external payable returns (uint256 batchAmount, FailedTransfer[] memory failed);

    // ============ Query Functions ============

    /**
     * @notice Query if a batch has been executed
     * @param uuid Distribution UUID
     * @param batchId Batch ID
     * @return True if batch has been executed
     */
    function isBatchExecuted(bytes32 uuid, uint256 batchId) external view returns (bool);

    /**
     * @notice Query distribution progress
     * @param uuid Distribution UUID
     * @return executedBatches Number of batches executed
     * @return _totalBatches Total number of batches
     * @return _distributedAmount Total amount distributed
     */
    function getProgress(bytes32 uuid)
        external
        view
        returns (uint256 executedBatches, uint256 _totalBatches, uint256 _distributedAmount);

    /**
     * @notice Query batch execution status storage
     */
    function batchExecuted(bytes32 uuid, uint256 batchId) external view returns (bool);

    /**
     * @notice Query executed batch count storage
     */
    function executedBatchCount(bytes32 uuid) external view returns (uint256);

    /**
     * @notice Query distributed amount storage
     */
    function distributedAmount(bytes32 uuid) external view returns (uint256);

    /**
     * @notice Query total batches storage
     */
    function totalBatches(bytes32 uuid) external view returns (uint256);
}
