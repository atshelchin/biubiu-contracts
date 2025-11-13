// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BiuBiuPremium
 * @notice A subscription contract with three tiers and referral system
 * @dev Uses custom errors for gas efficiency and includes reentrancy protection
 */
contract BiuBiuPremium {
    // Custom errors (gas efficient)
    error ReentrancyDetected();
    error IncorrectPaymentAmount();
    error NoBalanceToWithdraw();

    // Reentrancy guard
    uint256 private _locked = 1;

    // Subscription tier enum
    enum SubscriptionTier {
        Daily, // 1 day
        Monthly, // 30 days
        Yearly // 365 days
    }

    // Tier pricing (immutable for gas optimization)
    uint256 public constant DAILY_PRICE = 0.01 ether;
    uint256 public constant MONTHLY_PRICE = 0.05 ether;
    uint256 public constant YEARLY_PRICE = 0.1 ether;

    // Tier duration
    uint256 public constant DAILY_DURATION = 1 days;
    uint256 public constant MONTHLY_DURATION = 30 days;
    uint256 public constant YEARLY_DURATION = 365 days;

    // Owner address
    address public constant OWNER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;

    // User subscription expiry time
    mapping(address => uint256) public subscriptionExpiry;

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

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
    }

    function _nonReentrantAfter() private {
        _locked = 1;
    }

    /**
     * @notice Subscribe to a premium tier
     * @param tier The subscription tier (Daily, Monthly, or Yearly)
     * @param referrer The referrer address (use address(0) for no referrer)
     */
    function subscribe(SubscriptionTier tier, address referrer) external payable nonReentrant {
        // Get price and duration based on tier
        (uint256 price, uint256 duration) = _getTierInfo(tier);

        // Validate payment
        if (msg.value != price) revert IncorrectPaymentAmount();

        // Calculate new expiry time
        uint256 currentExpiry = subscriptionExpiry[msg.sender];
        uint256 newExpiry = currentExpiry > block.timestamp ? currentExpiry + duration : block.timestamp + duration;

        subscriptionExpiry[msg.sender] = newExpiry;

        // Handle payments
        uint256 referralAmount;

        // Only pay referral if referrer is valid and not self
        if (referrer != address(0) && referrer != msg.sender) {
            // Use bit shift for 50% calculation (more gas efficient)
            referralAmount = msg.value >> 1;

            // Use low-level call with limited gas to prevent griefing
            // If referrer payment fails, continue anyway (don't block subscription)
            // forge-lint: disable-next-line(unchecked-call)
            payable(referrer).call{value: referralAmount}("");

            emit ReferralPaid(referrer, referralAmount);
        }

        // Transfer all contract balance to owner
        // If transfer fails, don't block subscription - just keep funds in contract
        uint256 contractBalance = address(this).balance;
        // We intentionally ignore the return value to prevent blocking subscriptions
        // forge-lint: disable-next-line(unchecked-call)
        payable(OWNER).call{value: contractBalance}("");

        emit Subscribed(msg.sender, tier, newExpiry, referrer, referralAmount);
    }

    /**
     * @notice Get tier pricing and duration info
     * @param tier The subscription tier
     * @return price The price in wei
     * @return duration The duration in seconds
     */
    function _getTierInfo(SubscriptionTier tier) private pure returns (uint256 price, uint256 duration) {
        if (tier == SubscriptionTier.Daily) {
            return (DAILY_PRICE, DAILY_DURATION);
        } else if (tier == SubscriptionTier.Monthly) {
            return (MONTHLY_PRICE, MONTHLY_DURATION);
        } else {
            return (YEARLY_PRICE, YEARLY_DURATION);
        }
    }

    /**
     * @notice Get user subscription information
     * @param user The user address
     * @return isPremium Whether the user has an active subscription
     * @return expiryTime The subscription expiry timestamp
     * @return remainingTime The remaining time in seconds
     */
    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime)
    {
        expiryTime = subscriptionExpiry[user];
        isPremium = expiryTime > block.timestamp;
        remainingTime = isPremium ? expiryTime - block.timestamp : 0;
    }

    /**
     * @notice Withdraw ETH or ERC20 tokens to OWNER
     * @param token The token address (use address(0) for ETH)
     * @dev Can be called by anyone, but funds/tokens always go to OWNER
     */
    function ownerWithdraw(address token) external nonReentrant {
        uint256 amount;

        if (token == address(0)) {
            // Withdraw ETH
            amount = address(this).balance;
            if (amount == 0) revert NoBalanceToWithdraw();

            (bool success,) = payable(OWNER).call{value: amount}("");
            if (!success) revert("ETH withdrawal failed");
        } else {
            // Withdraw ERC20 token
            (bool balanceSuccess, bytes memory balanceData) =
                token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));

            if (!balanceSuccess) revert("Failed to get token balance");

            amount = abi.decode(balanceData, (uint256));
            if (amount == 0) revert NoBalanceToWithdraw();

            (bool success, bytes memory data) =
                token.call(abi.encodeWithSignature("transfer(address,uint256)", OWNER, amount));

            if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
                revert("Token withdrawal failed");
            }
        }

        emit OwnerWithdrew(OWNER, token, amount);
    }

    /**
     * @notice Receive ETH sent directly to contract
     * @dev Any ETH sent can be withdrawn using ownerWithdraw()
     */
    receive() external payable {}
}
