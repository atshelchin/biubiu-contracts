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
    error InvalidPromoCode();
    error PromoCodeExpired();
    error PromoCodeMaxUsesReached();
    error PromoCodeAlreadyUsed();
    error PromoCodeChainNotValid();
    error PromoCodeNotAvailable();
    error InvalidDiscountBps();

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
        uint256 referralAmount,
        uint256 paidAmount,
        string source,
        string toolId,
        bytes32 promoId,
        uint256 discountBps
    );
    event ReferralPaid(address indexed referrer, uint256 amount);
    event Activated(address indexed user, uint256 indexed tokenId);
    event Deactivated(address indexed user, uint256 indexed tokenId);
    event PromoCodeUsed(bytes32 indexed promoId, address indexed user, uint256 discountBps, uint256 paidAmount);

    // ============ Pricing ============

    function MONTHLY_PRICE() external view returns (uint256);
    function YEARLY_PRICE() external view returns (uint256);
    function MONTHLY_DURATION() external view returns (uint256);
    function YEARLY_DURATION() external view returns (uint256);
    function VAULT() external view returns (address);

    // ============ Subscription Functions ============

    function subscribe(
        SubscriptionTier tier,
        address referrer,
        address recipient,
        string calldata source,
        string calldata toolId,
        bytes calldata promoCode
    ) external payable;
    function subscribeToToken(
        uint256 tokenId,
        SubscriptionTier tier,
        address referrer,
        string calldata source,
        string calldata toolId,
        bytes calldata promoCode
    ) external payable;
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

    // ============ Tracking Stats ============

    function sourceSubscribeCount(bytes32 sourceHash) external view returns (uint256);
    function toolSubscribeCount(bytes32 toolHash) external view returns (uint256);
    function sourceRevenue(bytes32 sourceHash) external view returns (uint256);
    function toolRevenue(bytes32 toolHash) external view returns (uint256);

    // ============ Promo Code State ============

    function promoCodeUsedCount(bytes32 promoId) external view returns (uint256);
    function promoCodeUsedBy(bytes32 promoId, address user) external view returns (bool);
    function getDiscountedPrice(SubscriptionTier tier, uint256 discountBps) external view returns (uint256);
    function PROMO_TYPEHASH() external view returns (bytes32);
    function validatePromoCode(bytes calldata promoCode, address user)
        external
        view
        returns (
            bool isValid,
            uint256 discountBps,
            uint256 expiry,
            uint256 maxUses,
            bool singleUse,
            uint256[] memory validChainIds,
            uint256 usedCount,
            bool usedByUser,
            string memory reason
        );

    // ============ Tool Proxy ============

    function callTool(address target, bytes calldata data) external payable returns (bytes memory result);
}
