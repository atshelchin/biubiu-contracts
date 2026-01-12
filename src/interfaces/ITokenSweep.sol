// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITokenSweep
 * @notice Interface for TokenSweep batch token collection
 * @dev Stable API for frontend and other contracts to interact with TokenSweep
 *
 * @dev IMPORTANT: Requires EIP-7702 (Set EOA account code)
 * Each wallet must delegate its code to TokenSweep via EIP-7702 before calling multicall.
 * See TokenSweep.sol for detailed documentation on the EIP-7702 dependency.
 */

struct Wallet {
    address wallet;
    bytes signature; // 65 bytes: r (32) + s (32) + v (1)
}

interface ITokenSweep {
    // ============ Events ============

    event ReferralPaid(address indexed referrer, address indexed caller, uint256 amount);
    event VaultPaid(address indexed vault, address indexed caller, uint256 amount);
    event MulticallExecuted(address indexed caller, address indexed recipient, uint256 walletsCount, uint8 usageType);

    // ============ Constants ============

    function VAULT() external view returns (address);
    function NON_MEMBER_FEE() external view returns (uint256);
    function USAGE_FREE() external view returns (uint8);
    function USAGE_PAID() external view returns (uint8);

    // ============ State Variables ============

    function totalFreeUsage() external view returns (uint256);
    function totalPaidUsage() external view returns (uint256);

    // ============ Main Functions ============

    /**
     * @notice Batch sweep tokens from multiple wallets to a single recipient
     * @param wallets Array of wallet addresses and their signatures
     * @param recipient Address to receive all tokens
     * @param tokens Array of token addresses to sweep
     * @param deadline Timestamp after which the operation is invalid
     * @param referrer Referrer address for fee split (or address(0))
     * @param signature Premium member signature for authorization (or empty)
     */
    function multicall(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        address referrer,
        bytes calldata signature
    ) external payable;

    /**
     * @notice Multicall free version (no payment required)
     * @param wallets Array of wallet addresses and their signatures
     * @param recipient Address to receive all tokens
     * @param tokens Array of token addresses to sweep
     * @param deadline Timestamp after which the operation is invalid
     * @param signature Premium member signature for authorization (or empty)
     */
    function multicallFree(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @notice Drain all tokens from the calling context to recipient
     * @dev Called by multicall on each EOA that delegated its code to TokenSweep via EIP-7702
     *
     * EIP-7702 Context:
     * - When called on a delegated EOA, `address(this)` is the EOA's address
     * - The signature must be signed by the EOA's private key (ecrecover == address(this))
     * - Token.transfer() operates on the EOA's token balances
     *
     * @param recipient Address to receive tokens
     * @param tokens Array of token addresses to sweep (address(0) entries are skipped)
     * @param deadline Timestamp after which the operation is invalid
     * @param signature EOA owner's signature authorizing the drain (EIP-191 personal_sign format)
     */
    function drainToAddress(address recipient, address[] calldata tokens, uint256 deadline, bytes calldata signature)
        external;

    // ============ Receiver Functions ============

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
