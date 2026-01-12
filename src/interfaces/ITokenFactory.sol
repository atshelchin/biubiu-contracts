// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITokenFactory
 * @notice Interface for TokenFactory ERC20 token creation
 * @dev Stable API for frontend and other contracts to interact with TokenFactory
 */

struct TokenInfo {
    address tokenAddress;
    string name;
    string symbol;
    uint8 decimals;
    uint256 totalSupply;
    bool mintable;
    address owner;
}

interface ITokenFactory {
    // ============ Events ============

    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        uint8 usageType
    );
    event ReferralPaid(address indexed referrer, address indexed payer, uint256 amount);
    event FeePaid(address indexed payer, uint256 amount);

    // ============ Constants ============

    function USAGE_FREE() external view returns (uint8);
    function USAGE_PAID() external view returns (uint8);
    function VAULT() external view returns (address);
    function NON_MEMBER_FEE() external view returns (uint256);

    // ============ State Variables ============

    function totalFreeUsage() external view returns (uint256);
    function totalPaidUsage() external view returns (uint256);

    // ============ Main Functions ============

    /**
     * @notice Create a new ERC20 token (paid version)
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals (usually 18)
     * @param initialSupply Initial token supply (will be minted to creator)
     * @param mintable Whether the token can be minted after deployment
     * @param referrer Referrer address for fee sharing
     * @return tokenAddress Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        address referrer
    ) external payable returns (address tokenAddress);

    /**
     * @notice Create a new ERC20 token (free version)
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals (usually 18)
     * @param initialSupply Initial token supply (will be minted to creator)
     * @param mintable Whether the token can be minted after deployment
     * @return tokenAddress Address of the newly created token
     */
    function createTokenFree(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable
    ) external returns (address tokenAddress);

    /**
     * @notice Predict the token address before deployment
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals
     * @param initialSupply Initial supply
     * @param mintable Whether mintable
     * @param owner Token owner (creator)
     * @return predictedAddress The address where the token will be deployed
     */
    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        address owner
    ) external view returns (address predictedAddress);

    // ============ Query Functions ============

    /**
     * @notice Get total number of tokens created
     */
    function allTokensLength() external view returns (uint256);

    /**
     * @notice Get number of tokens created by a specific user
     */
    function userTokensLength(address user) external view returns (uint256);

    /**
     * @notice Get all tokens created by a specific user
     */
    function getUserTokens(address user) external view returns (address[] memory);

    /**
     * @notice Get token info from token address
     * @param tokenAddress Token contract address
     * @return info TokenInfo struct with all token details
     */
    function getTokenInfo(address tokenAddress) external view returns (TokenInfo memory info);

    /**
     * @notice Get user tokens with pagination (addresses only)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokens Array of token addresses
     * @return total Total number of tokens for this user
     */
    function getUserTokensPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory tokens, uint256 total);

    /**
     * @notice Get user tokens with pagination (with full token info)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokenInfos Array of TokenInfo structs
     * @return total Total number of tokens for this user
     */
    function getUserTokensInfoPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory tokenInfos, uint256 total);

    /**
     * @notice Get all tokens created through this factory
     */
    function getAllTokens() external view returns (address[] memory);

    /**
     * @notice Get all tokens with pagination (addresses only)
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokens Array of token addresses
     * @return total Total number of tokens
     */
    function getAllTokensPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory tokens, uint256 total);

    /**
     * @notice Get all tokens with pagination (with full token info)
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokenInfos Array of TokenInfo structs
     * @return total Total number of tokens
     */
    function getAllTokensInfoPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory tokenInfos, uint256 total);

    /**
     * @notice Get token address at index
     */
    function allTokens(uint256 index) external view returns (address);

    /**
     * @notice Get user token address at index
     */
    function userTokens(address user, uint256 index) external view returns (address);
}
