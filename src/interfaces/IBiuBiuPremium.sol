// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBiuBiuPremium
 * @notice Interface for BiuBiuPremium subscription NFT contract
 * @dev Stable API for frontend and other contracts to interact with BiuBiuPremium
 */
interface IBiuBiuPremium {
    // ============ Enums ============

    enum SubscriptionTier {
        Monthly, // 30 days
        Yearly // 365 days
    }

    // ============ Events ============

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
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
    event NonMemberFeeUpdated(uint256 fee);

    // ============ Pricing (mutable by admin) ============

    function MONTHLY_PRICE() external view returns (uint256);
    function YEARLY_PRICE() external view returns (uint256);
    function MONTHLY_DURATION() external view returns (uint256);
    function YEARLY_DURATION() external view returns (uint256);
    function NON_MEMBER_FEE() external view returns (uint256);
    function VAULT() external view returns (address);
    function admin() external view returns (address);

    // ============ Admin Functions ============

    function setNonMemberFee(uint256 fee) external;

    // ============ ERC721 Standard ============

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function tokenURI(uint256 tokenId) external view returns (string memory);

    // ============ Subscription Functions ============

    function subscribe(SubscriptionTier tier, address referrer) external payable;
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
        returns (uint256 mintedAt, address mintedBy, uint256 renewalCount);

    function getTokenLockedPrices(uint256 tokenId)
        external
        view
        returns (uint256 lockedMonthlyPrice, uint256 lockedYearlyPrice);

    function nextTokenId() external view returns (uint256);
    function subscriptionExpiry(uint256 tokenId) external view returns (uint256);
    function activeSubscription(address user) external view returns (uint256);
}
