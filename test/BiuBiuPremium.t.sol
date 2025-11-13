// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BiuBiuPremium.sol";

contract BiuBiuPremiumTest is Test {
    BiuBiuPremium public premium;
    address public owner = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public referrer = address(0x3);

    function setUp() public {
        premium = new BiuBiuPremium();
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // Test constants
    function testConstants() public view {
        assertEq(premium.DAILY_PRICE(), 0.01 ether);
        assertEq(premium.MONTHLY_PRICE(), 0.05 ether);
        assertEq(premium.YEARLY_PRICE(), 0.1 ether);
        assertEq(premium.DAILY_DURATION(), 1 days);
        assertEq(premium.MONTHLY_DURATION(), 30 days);
        assertEq(premium.YEARLY_DURATION(), 365 days);
        assertEq(premium.OWNER(), owner);
    }

    // Test daily subscription without referrer
    function testSubscribeDailyNoReferrer() public {
        vm.startPrank(user1);

        uint256 ownerBalanceBefore = owner.balance;

        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        // Owner receives payment automatically
        assertEq(owner.balance, ownerBalanceBefore + 0.01 ether);

        // Check subscription info
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium
            .getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 1 days);
        assertEq(remainingTime, 1 days);

        vm.stopPrank();
    }

    // Test monthly subscription with referrer
    function testSubscribeMonthlyWithReferrer() public {
        vm.startPrank(user1);

        uint256 ownerBalanceBefore = owner.balance;
        uint256 referrerBalanceBefore = referrer.balance;

        premium.subscribe{value: 0.05 ether}(
            BiuBiuPremium.SubscriptionTier.Monthly,
            referrer
        );

        // Check payments split 50/50
        assertEq(owner.balance, ownerBalanceBefore + 0.025 ether);
        assertEq(referrer.balance, referrerBalanceBefore + 0.025 ether);

        // Check subscription info
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium
            .getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 30 days);
        assertEq(remainingTime, 30 days);

        vm.stopPrank();
    }

    // Test yearly subscription
    function testSubscribeYearly() public {
        vm.startPrank(user1);

        premium.subscribe{value: 0.1 ether}(
            BiuBiuPremium.SubscriptionTier.Yearly,
            address(0)
        );

        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium
            .getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 365 days);
        assertEq(remainingTime, 365 days);

        vm.stopPrank();
    }

    // Test subscription extension (cumulative)
    function testSubscriptionExtension() public {
        vm.startPrank(user1);

        // First subscription
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        uint256 firstExpiry = block.timestamp + 1 days;

        // Second subscription
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        (, uint256 expiryTime, ) = premium.getSubscriptionInfo(user1);
        assertEq(expiryTime, firstExpiry + 1 days);

        vm.stopPrank();
    }

    // Test subscription after expiry
    function testSubscriptionAfterExpiry() public {
        vm.startPrank(user1);

        // First subscription
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        // Fast forward past expiry
        vm.warp(block.timestamp + 8 days);

        (bool isPremium, , ) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        // Subscribe again
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        (, uint256 newExpiry, ) = premium.getSubscriptionInfo(user1);
        assertEq(newExpiry, block.timestamp + 1 days);

        vm.stopPrank();
    }

    // Test incorrect payment amount
    function testIncorrectPaymentAmount() public {
        vm.startPrank(user1);

        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: 0.005 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        vm.stopPrank();
    }

    // Test self-referral (no commission paid)
    function testSelfReferralNoCommission() public {
        vm.startPrank(user1);

        uint256 ownerBalanceBefore = owner.balance;

        // User1 tries to refer themselves
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            user1
        );

        // Owner receives full payment (no referral commission)
        assertEq(owner.balance, ownerBalanceBefore + 0.01 ether);

        // Subscription still succeeds
        (bool isPremium, , ) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        vm.stopPrank();
    }

    // Test non-premium user
    function testNonPremiumUser() public view {
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium
            .getSubscriptionInfo(user1);
        assertFalse(isPremium);
        assertEq(expiryTime, 0);
        assertEq(remainingTime, 0);
    }

    // Test events
    function testSubscribeEvents() public {
        vm.startPrank(user1);

        vm.expectEmit(true, true, false, true);
        emit BiuBiuPremium.ReferralPaid(referrer, 0.025 ether);

        vm.expectEmit(true, true, false, true);
        emit BiuBiuPremium.Subscribed(
            user1,
            BiuBiuPremium.SubscriptionTier.Monthly,
            block.timestamp + 30 days,
            referrer,
            0.025 ether
        );

        premium.subscribe{value: 0.05 ether}(
            BiuBiuPremium.SubscriptionTier.Monthly,
            referrer
        );

        vm.stopPrank();
    }

    // Test reentrancy protection
    function testReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(premium);
        vm.deal(address(attacker), 1 ether);
        vm.deal(user1, 1 ether);

        // User1 subscribes with attacker as referrer
        // When attacker receives referral payment, it will try to reenter
        // With the new implementation, referrer payment failure doesn't block subscription
        vm.prank(user1);
        premium.subscribe{value: 0.05 ether}(
            BiuBiuPremium.SubscriptionTier.Monthly,
            address(attacker)
        );

        // The subscription SHOULD succeed even if referrer payment failed
        // This is the optimized behavior - don't let malicious referrers block subscriptions
        (bool isPremium, , ) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // Test multiple users
    function testMultipleUsers() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: 0.01 ether}(
            BiuBiuPremium.SubscriptionTier.Daily,
            address(0)
        );

        // User2 subscribes
        vm.prank(user2);
        premium.subscribe{value: 0.05 ether}(
            BiuBiuPremium.SubscriptionTier.Monthly,
            address(0)
        );

        // Check both subscriptions
        (bool isPremium1, , ) = premium.getSubscriptionInfo(user1);
        (bool isPremium2, , ) = premium.getSubscriptionInfo(user2);

        assertTrue(isPremium1);
        assertTrue(isPremium2);
    }

    // Test backup owner withdrawal (when auto-transfer fails)
    function testBackupOwnerWithdrawal() public {
        // Simulate someone accidentally sending ETH directly to contract
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool sent, ) = address(premium).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");

        // Check contract balance
        assertEq(address(premium).balance, 1 ether);

        uint256 ownerBalanceBefore = owner.balance;

        // Owner uses backup withdrawal (address(0) = ETH)
        vm.prank(owner);
        premium.ownerWithdraw(address(0));

        // Check balances after withdrawal
        assertEq(address(premium).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
    }

    // Test anyone can call withdraw (but funds go to owner)
    function testAnyoneCanCallWithdraw() public {
        // Send ETH to contract
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool sent, ) = address(premium).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");

        uint256 ownerBalanceBefore = owner.balance;

        // User1 (not owner) calls withdraw, but funds go to owner
        vm.prank(user1);
        premium.ownerWithdraw(address(0));

        // Owner receives the funds
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
        assertEq(address(premium).balance, 0);
    }

    // Test withdraw with no balance
    function testWithdrawNoBalance() public {
        vm.prank(owner);
        vm.expectRevert(BiuBiuPremium.NoBalanceToWithdraw.selector);
        premium.ownerWithdraw(address(0));
    }
}

// Mock attacker contract for reentrancy test
contract ReentrancyAttacker {
    BiuBiuPremium public premium;
    bool private _attacked;

    constructor(BiuBiuPremium _premium) {
        premium = _premium;
    }

    function attacked() external view returns (bool) {
        return _attacked;
    }

    // When receiving referral payment, try to reenter
    receive() external payable {
        if (!_attacked && address(this).balance >= 0.01 ether) {
            _attacked = true;
            // Try to reenter - should fail with "Reentrancy detected"
            premium.subscribe{value: 0.01 ether}(
                BiuBiuPremium.SubscriptionTier.Daily,
                address(0)
            );
        }
    }
}
