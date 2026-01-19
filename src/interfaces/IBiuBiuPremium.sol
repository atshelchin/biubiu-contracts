// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBiuBiuPremium
 * @notice Interface for BiuBiuPremium subscription NFT contract
 * @dev Stable API for frontend and other contracts to interact with BiuBiuPremium
 *      ERC721 functions are inherited from ERC721Base (which implements IERC721)
 */
interface IBiuBiuPremium {
    // ============ Custom Errors ============

    error IncorrectPaymentAmount();
    error NotPremiumMember();
    error InvalidTarget();
    error CallFailed();

    // ============ Enums ============

    enum SubscriptionTier {
        Monthly, // 30 days
        Yearly // 365 days
    }

    // ============ Structs ============

    struct TokenAttributes {
        uint256 mintedAt;
        address mintedBy;
        uint256 renewalCount;
        uint256 expiry;
    }

    // ============ Events ============

    event Subscribed(
        address indexed user,
        uint256 indexed tokenId,
        SubscriptionTier tier,
        uint256 expiryTime,
        address indexed referrer,
        uint256 referralAmount
    );
    event ReferralPaid(address indexed referrer, uint256 amount);
    event Activated(address indexed user, uint256 indexed tokenId);
    event Deactivated(address indexed user, uint256 indexed tokenId);

    // ============ Pricing ============

    function MONTHLY_PRICE() external view returns (uint256);
    function YEARLY_PRICE() external view returns (uint256);
    function MONTHLY_DURATION() external view returns (uint256);
    function YEARLY_DURATION() external view returns (uint256);
    function VAULT() external view returns (address);

    // ============ Subscription Functions ============

    function subscribe(SubscriptionTier tier, address referrer, address recipient) external payable;
    function subscribeToToken(uint256 tokenId, SubscriptionTier tier, address referrer) external payable;
    function activate(uint256 tokenId) external;

    // ============ View Functions ============

    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime);

    function getTokenSubscriptionInfo(uint256 tokenId)
        external
        view
        returns (uint256 expiryTime, bool isExpired, address tokenOwner);

    function getTokenAttributes(uint256 tokenId)
        external
        view
        returns (uint256 mintedAt, address mintedBy, uint256 renewalCount, uint256 expiry);

    function nextTokenId() external view returns (uint256);
    function subscriptionExpiry(uint256 tokenId) external view returns (uint256);
    function activeSubscription(address user) external view returns (uint256);

    // ============ Tool Proxy ============

    function callTool(address target, bytes calldata data) external returns (bytes memory result);
}
