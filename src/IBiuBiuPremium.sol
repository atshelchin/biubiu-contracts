// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBiuBiuPremium {
    // Custom errors
    error ReentrancyDetected();
    error IncorrectPaymentAmount();
    error NoBalanceToWithdraw();

    // Subscription tier enum
    enum SubscriptionTier {
        Daily,    // 1 day
        Monthly,  // 30 days
        Yearly    // 365 days
    }

    // Events
    event Subscribed(
        address indexed user,
        SubscriptionTier tier,
        uint256 expiryTime,
        address indexed referrer,
        uint256 referralAmount
    );
    event ReferralPaid(address indexed referrer, uint256 amount);
    event OwnerWithdrew(address indexed owner, address indexed token, uint256 amount);

    // Subscribe to a tier
    function subscribe(SubscriptionTier tier, address referrer) external payable;

    // Get user subscription info (isPremium, expiryTime, remainingTime)
    function getSubscriptionInfo(address user) external view returns (bool isPremium, uint256 expiryTime, uint256 remainingTime);

    // Withdraw ETH or ERC20 tokens
    function ownerWithdraw(address token) external;

    // Constants
    function DAILY_PRICE() external view returns (uint256);
    function MONTHLY_PRICE() external view returns (uint256);
    function YEARLY_PRICE() external view returns (uint256);
    function DAILY_DURATION() external view returns (uint256);
    function MONTHLY_DURATION() external view returns (uint256);
    function YEARLY_DURATION() external view returns (uint256);
    function OWNER() external view returns (address);

    // Mapping getter
    function subscriptionExpiry(address user) external view returns (uint256);
}
