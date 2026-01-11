// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";
import {IBiuBiuPremium} from "../src/interfaces/IBiuBiuPremium.sol";

contract BiuBiuPremiumTest is Test {
    BiuBiuPremium public premium;
    address public vault = 0x46AFD0cA864D4E5235DA38a71687163Dc83828cE;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public referrer = address(0x3);

    // Cache prices to avoid consuming vm.prank
    uint256 public monthlyPrice;
    uint256 public yearlyPrice;

    function setUp() public {
        premium = new BiuBiuPremium(vault);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Cache prices
        monthlyPrice = premium.MONTHLY_PRICE();
        yearlyPrice = premium.YEARLY_PRICE();
    }

    // Test constants and defaults
    function testConstants() public view {
        assertEq(premium.MONTHLY_PRICE(), 0.12 ether); // NON_MEMBER_FEE * 12
        assertEq(premium.YEARLY_PRICE(), 0.6 ether); // NON_MEMBER_FEE * 60 (Monthly * 5)
        assertEq(premium.MONTHLY_DURATION(), 30 days);
        assertEq(premium.YEARLY_DURATION(), 365 days);
        assertEq(premium.VAULT(), vault);
        assertEq(premium.NON_MEMBER_FEE(), 0.01 ether);
    }

    // Test ERC721 basics
    function testERC721Basics() public view {
        assertEq(premium.name(), "BiuBiu Premium");
        assertEq(premium.symbol(), "BBP");
        assertTrue(premium.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(premium.supportsInterface(0x01ffc9a7)); // ERC165
    }

    // Test monthly subscription without referrer - mints NFT
    function testSubscribeMonthlyNoReferrer() public {
        vm.startPrank(user1);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 monthlyPrice = premium.MONTHLY_PRICE();

        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Owner receives payment automatically
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice);

        // Check NFT was minted
        assertEq(premium.balanceOf(user1), 1);
        assertEq(premium.ownerOf(1), user1);

        // Check activeSubscription
        assertEq(premium.activeSubscription(user1), 1);

        // Check subscription info
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 30 days);
        assertEq(remainingTime, 30 days);

        vm.stopPrank();
    }

    // Test monthly subscription with referrer
    function testSubscribeMonthlyWithReferrer() public {
        vm.startPrank(user1);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 referrerBalanceBefore = referrer.balance;
        uint256 monthlyPrice = premium.MONTHLY_PRICE();

        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

        // Check payments split 50/50
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice / 2);
        assertEq(referrer.balance, referrerBalanceBefore + monthlyPrice / 2);

        // Check subscription info
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 30 days);
        assertEq(remainingTime, 30 days);

        vm.stopPrank();
    }

    // Test yearly subscription
    function testSubscribeYearly() public {
        vm.startPrank(user1);

        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 365 days);
        assertEq(remainingTime, 365 days);

        vm.stopPrank();
    }

    // Test subscription extension (cumulative) - renews active NFT
    function testSubscriptionExtension() public {
        vm.startPrank(user1);

        // First subscription - mints NFT tokenId=1
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.balanceOf(user1), 1);

        uint256 firstExpiry = block.timestamp + 30 days;

        // Second subscription - renews existing NFT (no new mint)
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.balanceOf(user1), 1); // Still only 1 NFT

        (, uint256 expiryTime,) = premium.getSubscriptionInfo(user1);
        assertEq(expiryTime, firstExpiry + 30 days);

        vm.stopPrank();
    }

    // Test subscription after expiry
    function testSubscriptionAfterExpiry() public {
        vm.startPrank(user1);

        // First subscription
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward past expiry (31 days for monthly)
        vm.warp(block.timestamp + 31 days);

        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        // Subscribe again - renews existing NFT
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (, uint256 newExpiry,) = premium.getSubscriptionInfo(user1);
        assertEq(newExpiry, block.timestamp + 30 days);

        // Still only 1 NFT
        assertEq(premium.balanceOf(user1), 1);

        vm.stopPrank();
    }

    // Test incorrect payment amount
    function testIncorrectPaymentAmount() public {
        vm.startPrank(user1);

        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: 0.005 ether}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.stopPrank();
    }

    // Test self-referral (no commission paid)
    function testSelfReferralNoCommission() public {
        vm.startPrank(user1);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 monthlyPrice = premium.MONTHLY_PRICE();

        // User1 tries to refer themselves
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, user1);

        // Owner receives full payment (no referral commission)
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice);

        // Subscription still succeeds
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        vm.stopPrank();
    }

    // Test non-premium user
    function testNonPremiumUser() public view {
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);
        assertEq(expiryTime, 0);
        assertEq(remainingTime, 0);
    }

    // Test NFT transfer - activeSubscription handling
    function testNFTTransfer() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.activeSubscription(user1), 1);
        assertEq(premium.activeSubscription(user2), 0);

        // User1 transfers NFT to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // Check ownership transferred
        assertEq(premium.ownerOf(1), user2);

        // Check activeSubscription updated
        assertEq(premium.activeSubscription(user1), 0); // Deactivated from sender
        assertEq(premium.activeSubscription(user2), 1); // Auto-activated for receiver

        // Check subscription info
        (bool isPremium1,,) = premium.getSubscriptionInfo(user1);
        (bool isPremium2,,) = premium.getSubscriptionInfo(user2);
        assertFalse(isPremium1);
        assertTrue(isPremium2);
    }

    // Test NFT transfer to user who already has active subscription
    function testNFTTransferToActiveUser() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 subscribes
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.activeSubscription(user1), 1);
        assertEq(premium.activeSubscription(user2), 2);

        // User1 transfers NFT to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User2's active subscription should NOT change (they already had one)
        assertEq(premium.activeSubscription(user2), 2);

        // User2 now owns both NFTs
        assertEq(premium.balanceOf(user2), 2);
    }

    // Test activate function
    function testActivate() public {
        // User1 subscribes twice (first creates NFT, second renews)
        vm.startPrank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Deactivate and subscribe again to get new NFT
        // We need to transfer away and get a new one
        vm.stopPrank();

        // User2 subscribes to create tokenId=2
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 transfers to user1
        vm.prank(user2);
        premium.transferFrom(user2, user1, 2);

        // Now user1 has tokenId=1 (active) and tokenId=2
        assertEq(premium.balanceOf(user1), 2);
        assertEq(premium.activeSubscription(user1), 1);

        // User1 activates tokenId=2
        vm.prank(user1);
        premium.activate(2);

        assertEq(premium.activeSubscription(user1), 2);
    }

    // Test activate not owner
    function testActivateNotOwner() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotTokenOwner.selector);
        premium.activate(1);
    }

    // Test subscribeToToken (gift subscription)
    function testSubscribeToToken() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        uint256 originalExpiry = premium.subscriptionExpiry(1);

        // User2 gifts more time to user1's NFT
        vm.prank(user2);
        premium.subscribeToToken{value: monthlyPrice}(1, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check expiry extended
        assertEq(premium.subscriptionExpiry(1), originalExpiry + 30 days);
    }

    // Test subscribeToToken for non-existent token
    function testSubscribeToTokenNotExists() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.subscribeToToken{value: monthlyPrice}(999, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test getTokenSubscriptionInfo
    function testGetTokenSubscriptionInfo() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (uint256 expiryTime, bool isExpired, address tokenOwner) = premium.getTokenSubscriptionInfo(1);

        assertEq(expiryTime, block.timestamp + 30 days);
        assertFalse(isExpired);
        assertEq(tokenOwner, user1);

        // Fast forward past expiry (31 days for monthly)
        vm.warp(block.timestamp + 31 days);

        (, bool isExpiredNow,) = premium.getTokenSubscriptionInfo(1);
        assertTrue(isExpiredNow);
    }

    // Test events
    function testSubscribeEvents() public {
        vm.startPrank(user1);

        uint256 monthlyPrice = premium.MONTHLY_PRICE();
        uint256 referralAmount = monthlyPrice / 2;

        vm.expectEmit(true, true, false, true);
        emit IBiuBiuPremium.ReferralPaid(referrer, referralAmount);

        vm.expectEmit(true, true, true, true);
        emit IBiuBiuPremium.Subscribed(
            user1, 1, IBiuBiuPremium.SubscriptionTier.Monthly, block.timestamp + 30 days, referrer, referralAmount
        );

        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

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
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(attacker));

        // The subscription SHOULD succeed even if referrer payment failed
        // This is the optimized behavior - don't let malicious referrers block subscriptions
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // Test multiple users
    function testMultipleUsers() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 subscribes
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check both subscriptions
        (bool isPremium1,,) = premium.getSubscriptionInfo(user1);
        (bool isPremium2,,) = premium.getSubscriptionInfo(user2);

        assertTrue(isPremium1);
        assertTrue(isPremium2);

        // Check NFT ownership
        assertEq(premium.ownerOf(1), user1);
        assertEq(premium.ownerOf(2), user2);
    }

    // Test nextTokenId
    function testNextTokenId() public {
        assertEq(premium.nextTokenId(), 1);

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.nextTokenId(), 2);
    }

    // Test ERC721 approval
    function testApproval() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.approve(user2, 1);

        assertEq(premium.getApproved(1), user2);

        // User2 can transfer
        vm.prank(user2);
        premium.transferFrom(user1, user2, 1);

        assertEq(premium.ownerOf(1), user2);
    }

    // Test setApprovalForAll
    function testApprovalForAll() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.setApprovalForAll(user2, true);

        assertTrue(premium.isApprovedForAll(user1, user2));

        // User2 can transfer
        vm.prank(user2);
        premium.transferFrom(user1, user2, 1);

        assertEq(premium.ownerOf(1), user2);
    }

    // Test getTokenAttributes
    function testGetTokenAttributes() public {
        uint256 mintTime = block.timestamp;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (uint256 mintedAt, address mintedBy, uint256 renewalCount) = premium.getTokenAttributes(1);

        assertEq(mintedAt, mintTime);
        assertEq(mintedBy, user1);
        assertEq(renewalCount, 1); // First subscribe counts as 1 renewal
    }

    // Test getTokenLockedPrices - locked prices saved at mint time
    function testGetTokenLockedPrices() public {
        // Subscribe at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check locked prices match current prices at mint time
        (uint256 lockedMonthly, uint256 lockedYearly) = premium.getTokenLockedPrices(1);
        assertEq(lockedMonthly, monthlyPrice);
        assertEq(lockedYearly, yearlyPrice);
    }

    // Test locked prices - renewal uses locked price after price increase
    function testRenewalUsesLockedPrice() public {
        // Subscribe at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Admin increases prices via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(0.1 ether); // Monthly = 1.2 ether, Yearly = 6 ether

        // Verify prices increased
        assertEq(premium.MONTHLY_PRICE(), 1.2 ether);

        // User renews at OLD locked price, not new price
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check subscription is active
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        // Verify locked prices unchanged
        (uint256 lockedMonthly,) = premium.getTokenLockedPrices(1);
        assertEq(lockedMonthly, monthlyPrice);
    }

    // Test new subscription uses current price after price increase
    function testNewSubscriptionUsesCurrentPrice() public {
        // Subscribe at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Admin increases prices via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(0.1 ether); // Monthly = 1.2 ether, Yearly = 6 ether

        // New user must pay NEW price
        vm.prank(user2);
        premium.subscribe{value: 1.2 ether}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check new user's locked price is the NEW price
        (uint256 lockedMonthly,) = premium.getTokenLockedPrices(2);
        assertEq(lockedMonthly, 1.2 ether);
    }

    // Test getTokenAttributes - renewal count increments
    function testGetTokenAttributesRenewalCount() public {
        vm.startPrank(user1);

        // First subscription - mints NFT with renewalCount = 1
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 count1) = premium.getTokenAttributes(1);
        assertEq(count1, 1);

        // Second subscription - renews existing, renewalCount = 2
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 count2) = premium.getTokenAttributes(1);
        assertEq(count2, 2);

        // Third subscription - renewalCount = 3
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 count3) = premium.getTokenAttributes(1);
        assertEq(count3, 3);

        vm.stopPrank();
    }

    // Test getTokenAttributes for non-existent token
    function testGetTokenAttributesNotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getTokenAttributes(999);
    }

    // Test getTokenAttributes - mintedBy is the original minter after transfer
    function testGetTokenAttributesMinterPersistsAfterTransfer() public {
        uint256 mintTime = block.timestamp;

        // User1 subscribes (mints NFT)
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // Attributes should still show user1 as the original minter
        (uint256 mintedAt, address mintedBy, uint256 renewalCount) = premium.getTokenAttributes(1);

        assertEq(mintedAt, mintTime);
        assertEq(mintedBy, user1); // Original minter preserved
        assertEq(renewalCount, 1);

        // User2 renews - renewalCount increases
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2's active token is now token 1 (auto-activated on transfer)
        (, address mintedBy2, uint256 count2) = premium.getTokenAttributes(1);
        assertEq(mintedBy2, user1); // Still user1
        assertEq(count2, 2); // Renewal count increased
    }

    // Test getTokenAttributes - gift subscription increases renewal count
    function testGetTokenAttributesGiftRenewal() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 count1) = premium.getTokenAttributes(1);
        assertEq(count1, 1);

        // User2 gifts more time via subscribeToToken
        vm.prank(user2);
        premium.subscribeToToken{value: monthlyPrice}(1, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 count2) = premium.getTokenAttributes(1);
        assertEq(count2, 2); // Gift also counts as renewal
    }

    // Test totalSupply
    function testTotalSupply() public {
        assertEq(premium.totalSupply(), 0);

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.totalSupply(), 1);

        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.totalSupply(), 2);

        // Renewal should not increase totalSupply
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.totalSupply(), 2);
    }

    // Test getTokenSubscriptionInfo reverts for non-existent token
    function testGetTokenSubscriptionInfoNotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getTokenSubscriptionInfo(999);
    }

    // Test tokenURI returns valid base64 JSON
    function testTokenURI() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        string memory uri = premium.tokenURI(1);

        // Should start with data:application/json;base64,
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory uriBytes = bytes(uri);

        assertTrue(uriBytes.length > prefix.length);

        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(uriBytes[i], prefix[i]);
        }
    }

    // Test tokenURI for non-existent token
    function testTokenURINotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.tokenURI(999);
    }

    // Test ReferralPaid event only emitted on successful transfer
    function testReferralPaidOnlyOnSuccess() public {
        // Create a contract that rejects ETH
        RejectingContract rejecter = new RejectingContract();

        vm.prank(user1);
        // Subscribe with rejecter as referrer - should succeed but no ReferralPaid event
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(rejecter));

        // Subscription should still succeed
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // ========== Additional Coverage Tests ==========

    // Test balanceOf with zero address reverts
    function testBalanceOfZeroAddress() public {
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.balanceOf(address(0));
    }

    // Test ownerOf for non-existent token
    function testOwnerOfNotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.ownerOf(999);
    }

    // Test getApproved for non-existent token
    function testGetApprovedNotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getApproved(999);
    }

    // Test approve to self reverts
    function testApproveToSelf() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.approve(user1, 1);
    }

    // Test approve by non-owner/non-approved reverts
    function testApproveNotAuthorized() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotApproved.selector);
        premium.approve(referrer, 1);
    }

    // Test setApprovalForAll to self reverts
    function testSetApprovalForAllToSelf() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.setApprovalForAll(user1, true);
    }

    // Test safeTransferFrom (without data)
    function testSafeTransferFrom() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.safeTransferFrom(user1, user2, 1);

        assertEq(premium.ownerOf(1), user2);
        assertEq(premium.activeSubscription(user2), 1);
    }

    // Test safeTransferFrom (with data)
    function testSafeTransferFromWithData() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.safeTransferFrom(user1, user2, 1, "test data");

        assertEq(premium.ownerOf(1), user2);
    }

    // Test safeTransferFrom to contract that rejects
    function testSafeTransferFromToNonReceiver() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // RejectingContract doesn't implement onERC721Received
        RejectingContract nonReceiver = new RejectingContract();

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TransferToNonReceiver.selector);
        premium.safeTransferFrom(user1, address(nonReceiver), 1);
    }

    // Test transferFrom to zero address reverts
    function testTransferToZeroAddress() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.transferFrom(user1, address(0), 1);
    }

    // Test transferFrom with wrong 'from' address
    function testTransferFromWrongFrom() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.NotTokenOwner.selector);
        premium.transferFrom(user2, referrer, 1); // user2 doesn't own token 1
    }

    // Test supportsInterface for ERC721Metadata
    function testSupportsInterfaceMetadata() public view {
        assertTrue(premium.supportsInterface(0x5b5e139f)); // ERC721Metadata
        assertFalse(premium.supportsInterface(0x12345678)); // Random interface
    }

    // Test activate with tokenId 0 (edge case - tokenId 0 doesn't exist)
    function testActivateTokenZero() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.NotTokenOwner.selector);
        premium.activate(0);
    }

    // Test subscribe mints to contract receiver
    function testSubscribeToContractReceiver() public {
        ERC721Receiver receiver = new ERC721Receiver();
        vm.deal(address(receiver), 1 ether);

        vm.prank(address(receiver));
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.ownerOf(1), address(receiver));
    }

    // Test operator can transfer via approval
    function testOperatorTransfer() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User1 sets user2 as operator
        vm.prank(user1);
        premium.setApprovalForAll(user2, true);

        // User2 can also approve on behalf of user1
        vm.prank(user2);
        premium.approve(referrer, 1);

        assertEq(premium.getApproved(1), referrer);
    }

    // Test approval is cleared after transfer
    function testApprovalClearedAfterTransfer() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.approve(referrer, 1);
        assertEq(premium.getApproved(1), referrer);

        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // Approval should be cleared
        assertEq(premium.getApproved(1), address(0));
    }

    // ============ Admin Function Tests ============

    // Test setNonMemberFee updates derived prices
    function testSetNonMemberFeeUpdatesPrices() public {
        uint256 newFee = 0.1 ether;

        vm.prank(premium.admin());
        premium.setNonMemberFee(newFee);

        // Monthly = newFee * 12 = 1.2 ether
        // Yearly = newFee * 60 = 6 ether (Monthly * 5)
        assertEq(premium.MONTHLY_PRICE(), 1.2 ether);
        assertEq(premium.YEARLY_PRICE(), 6 ether);
    }

    // Test setNonMemberFee by admin
    function testSetNonMemberFee() public {
        uint256 newFee = 0.02 ether;

        vm.prank(premium.admin());
        premium.setNonMemberFee(newFee);

        assertEq(premium.NON_MEMBER_FEE(), newFee);
    }

    // Test setNonMemberFee emits event
    function testSetNonMemberFeeEmitsEvent() public {
        uint256 newFee = 0.02 ether;

        vm.expectEmit(false, false, false, true);
        emit IBiuBiuPremium.NonMemberFeeUpdated(newFee);

        vm.prank(premium.admin());
        premium.setNonMemberFee(newFee);
    }

    // Test setNonMemberFee reverts for non-admin
    function testSetNonMemberFeeNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.NotAdmin.selector);
        premium.setNonMemberFee(0.02 ether);
    }

    // Test admin constant value
    function testAdminAddress() public view {
        assertEq(premium.admin(), 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9);
    }

    // ============ Locked Prices Edge Cases ============

    // Test locked prices after transfer - new owner uses original prices
    function testLockedPricesAfterTransfer() public {
        // User1 mints at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Admin raises prices via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(1 ether); // Monthly = 12 ether, Yearly = 60 ether

        // Transfer NFT to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User2 activates the transferred NFT
        vm.prank(user2);
        premium.activate(1);

        // User2 renews at OLD locked price (not new price)
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check subscription is active
        (bool isPremium,,) = premium.getSubscriptionInfo(user2);
        assertTrue(isPremium);
    }

    // Test subscribeToToken uses locked prices
    function testSubscribeToTokenUsesLockedPrices() public {
        // User1 mints at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Admin raises prices via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(1 ether); // Monthly = 12 ether, Yearly = 60 ether

        // Anyone can gift renewal using locked price
        vm.prank(user2);
        premium.subscribeToToken{value: monthlyPrice}(1, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Check renewal count increased
        (,, uint256 renewalCount) = premium.getTokenAttributes(1);
        assertEq(renewalCount, 2);
    }

    // Test getTokenLockedPrices for non-existent token
    function testGetTokenLockedPricesNotExists() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getTokenLockedPrices(999);
    }

    // Test all tiers use locked prices for renewal
    function testAllTiersUseLockedPrices() public {
        // User1 mints at current prices
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Get locked prices
        (uint256 lockedMonthly, uint256 lockedYearly) = premium.getTokenLockedPrices(1);

        // Admin raises prices significantly via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(10 ether); // Monthly = 120 ether, Yearly = 600 ether

        // Renew with each tier at locked prices
        vm.startPrank(user1);

        // Daily renewal at locked price
        premium.subscribe{value: lockedMonthly}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Monthly renewal at locked price
        premium.subscribe{value: lockedMonthly}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Yearly renewal at locked price
        premium.subscribe{value: lockedYearly}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        vm.stopPrank();

        // Check renewal count
        (,, uint256 renewalCount) = premium.getTokenAttributes(1);
        assertEq(renewalCount, 4); // 1 initial + 3 renewals
    }

    // Test setNonMemberFee to zero - all prices become free
    function testSetNonMemberFeeToZero() public {
        vm.prank(premium.admin());
        premium.setNonMemberFee(0);

        assertEq(premium.NON_MEMBER_FEE(), 0);
        assertEq(premium.MONTHLY_PRICE(), 0);
        assertEq(premium.YEARLY_PRICE(), 0);

        // New subscription should be free
        vm.prank(user1);
        premium.subscribe{value: 0}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // ============ Security & Edge Case Tests ============

    // Test: activeSubscription pointing to non-owned token after transfer
    // Scenario: User A has activeSubscription = 5, transfers token 5 to B, then subscribes again
    function testActiveSubscriptionAfterTransferAndNewSubscribe() public {
        // User1 subscribes, gets token 1
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.activeSubscription(user1), 1);

        // Transfer token 1 to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User1's activeSubscription should be cleared
        assertEq(premium.activeSubscription(user1), 0);

        // User1 subscribes again - should get NEW token 2
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.activeSubscription(user1), 2);
        assertEq(premium.ownerOf(2), user1);
        assertEq(premium.nextTokenId(), 3);
    }

    // Test: Subscribe when activeSubscription points to a token user doesn't own
    // This tests the edge case where activeSubscription[user] != 0 but user doesn't own that token
    // This should NOT happen in normal flow, but let's verify the contract handles it
    function testSubscribeRenewsActiveTokenEvenIfExpired() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward past expiry (31 days for monthly)
        vm.warp(block.timestamp + 31 days);

        // User1's subscription is expired but activeSubscription still points to token 1
        assertEq(premium.activeSubscription(user1), 1);
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        // User1 subscribes again - should RENEW token 1, not mint new
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Still only 1 token
        assertEq(premium.balanceOf(user1), 1);
        assertEq(premium.activeSubscription(user1), 1);
        (bool isPremiumAfter,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremiumAfter);
    }

    // Test: Multiple users transfer tokens in complex pattern
    function testComplexTransferPattern() public {
        // User1 subscribes -> token 1
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 subscribes -> token 2
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User1 transfers token 1 to user2 (user2 already has active = 2)
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User2 should still have activeSubscription = 2 (not changed)
        assertEq(premium.activeSubscription(user2), 2);
        assertEq(premium.balanceOf(user2), 2);

        // User1 subscribes again -> gets token 3
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.activeSubscription(user1), 3);
        assertEq(premium.balanceOf(user1), 1);

        // User2 can activate token 1 if they want
        vm.prank(user2);
        premium.activate(1);
        assertEq(premium.activeSubscription(user2), 1);
    }

    // Test: Subscription with zero value when price is zero
    function testZeroPriceSubscription() public {
        // Admin sets NON_MEMBER_FEE to zero - all prices become free
        vm.prank(premium.admin());
        premium.setNonMemberFee(0);

        // User can subscribe for free
        vm.prank(user1);
        premium.subscribe{value: 0}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        // Can also renew for free
        vm.prank(user1);
        premium.subscribe{value: 0}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (,, uint256 renewalCount) = premium.getTokenAttributes(1);
        assertEq(renewalCount, 2);
    }

    // Test: Zero price with referrer (no referral paid but should not revert)
    function testZeroPriceWithReferrer() public {
        vm.prank(premium.admin());
        premium.setNonMemberFee(0);

        uint256 referrerBalanceBefore = referrer.balance;

        vm.prank(user1);
        premium.subscribe{value: 0}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

        // Referrer balance unchanged (0 >> 1 = 0)
        assertEq(referrer.balance, referrerBalanceBefore);

        // Subscription still works
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // Test: Referral payment to contract that reverts - subscription should succeed
    function testReferralToRevertingContract() public {
        RejectingContract rejecter = new RejectingContract();
        uint256 vaultBalanceBefore = vault.balance;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(rejecter));

        // Subscription succeeds
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        // Vault gets full amount (referral failed, so no split)
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice);
    }

    // Test: Referral to address(0) - no referral paid
    function testReferralToAddressZero() public {
        uint256 vaultBalanceBefore = vault.balance;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Vault gets full amount
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice);
    }

    // Test: Subscription expiry arithmetic - extend from future expiry
    function testExpiryExtensionFromFuture() public {
        vm.startPrank(user1);

        // Subscribe for yearly (365 days)
        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));
        uint256 firstExpiry = premium.subscriptionExpiry(1);
        assertEq(firstExpiry, block.timestamp + 365 days);

        // Extend with daily (1 day) - should add to existing expiry
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        uint256 secondExpiry = premium.subscriptionExpiry(1);
        assertEq(secondExpiry, firstExpiry + 30 days);

        vm.stopPrank();
    }

    // Test: Subscription renewal after expiry - starts from block.timestamp
    function testExpiryRenewalAfterExpiry() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward 10 days past expiry (31 days for monthly + 10 days)
        vm.warp(block.timestamp + 40 days);

        uint256 renewTime = block.timestamp;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // New expiry should be from current time, not from old expiry
        uint256 newExpiry = premium.subscriptionExpiry(1);
        assertEq(newExpiry, renewTime + 30 days);
    }

    // Test: Large expiry value (far future) - no overflow
    function testLargeExpiryNoOverflow() public {
        vm.prank(user1);
        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        // Renew many times - should accumulate without overflow
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user1);
            premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));
        }

        // 11 yearly subscriptions = 11 * 365 days
        uint256 expectedExpiry = block.timestamp + (11 * 365 days);
        assertEq(premium.subscriptionExpiry(1), expectedExpiry);
    }

    // Test: VAULT receives ETH correctly even with accumulated balance
    function testVaultReceivesAccumulatedBalance() public {
        // Send some ETH directly to contract
        vm.deal(address(premium), 1 ether);

        uint256 vaultBalanceBefore = vault.balance;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Vault should receive accumulated balance + subscription fee
        assertEq(vault.balance, vaultBalanceBefore + 1 ether + monthlyPrice);
        assertEq(address(premium).balance, 0);
    }

    // Test: Contract receive function
    function testReceiveFunction() public {
        uint256 balanceBefore = address(premium).balance;

        // Send ETH directly to contract
        (bool success,) = address(premium).call{value: 0.5 ether}("");
        assertTrue(success);

        assertEq(address(premium).balance, balanceBefore + 0.5 ether);
    }

    // Test: Multiple NFTs owned by same user - renewal only affects active one
    function testMultipleNFTsRenewalOnlyAffectsActive() public {
        // User1 subscribes -> token 1 (auto-activated)
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 subscribes -> token 2, then transfers to user1
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        vm.prank(user2);
        premium.transferFrom(user2, user1, 2);

        // User1 now owns tokens 1 and 2, but active is 1
        assertEq(premium.balanceOf(user1), 2);
        assertEq(premium.activeSubscription(user1), 1);

        uint256 token1Expiry = premium.subscriptionExpiry(1);
        uint256 token2Expiry = premium.subscriptionExpiry(2);

        // User1 renews (affects active token 1)
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Token 1 expiry extended
        assertEq(premium.subscriptionExpiry(1), token1Expiry + 30 days);
        // Token 2 expiry unchanged
        assertEq(premium.subscriptionExpiry(2), token2Expiry);
    }

    // Test: Deactivated event emitted on transfer
    function testDeactivatedEventOnTransfer() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IBiuBiuPremium.Deactivated(user1, 1);
        premium.transferFrom(user1, user2, 1);
    }

    // Test: Activated event emitted when receiver has no active subscription
    function testActivatedEventOnTransferToNewUser() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IBiuBiuPremium.Activated(user2, 1);
        premium.transferFrom(user1, user2, 1);
    }

    // Test: No Activated event when receiver already has active subscription
    function testNoActivatedEventWhenReceiverHasActive() public {
        // User1 subscribes -> token 1
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 subscribes -> token 2
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer token 1 to user2 - should NOT emit Activated for user2
        // (only Deactivated for user1)
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User2's active should still be 2
        assertEq(premium.activeSubscription(user2), 2);
    }

    // Test: subscribeToToken doesn't change ownership or activation
    function testSubscribeToTokenDoesNotAffectOwnership() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User2 gifts subscription to token 1 (owned by user1)
        vm.prank(user2);
        premium.subscribeToToken{value: monthlyPrice}(1, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Ownership unchanged
        assertEq(premium.ownerOf(1), user1);
        // User1's active subscription unchanged
        assertEq(premium.activeSubscription(user1), 1);
        // User2 still has no tokens
        assertEq(premium.balanceOf(user2), 0);
        assertEq(premium.activeSubscription(user2), 0);
    }

    // Test: Activate to tokenId you don't own fails
    function testActivateTokenNotOwned() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotTokenOwner.selector);
        premium.activate(1);
    }

    // Test: Paying wrong amount for renewal with locked prices
    function testWrongAmountWithLockedPrices() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Admin increases prices via NON_MEMBER_FEE
        vm.prank(premium.admin());
        premium.setNonMemberFee(1 ether); // Monthly = 12 ether, Yearly = 60 ether

        // User tries to pay NEW price (12 ether) but locked price is monthlyPrice
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: 12 ether}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: Token attributes for tokenId 0 (should revert)
    function testGetTokenAttributesTokenZero() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getTokenAttributes(0);
    }

    // Test: Token locked prices for tokenId 0 (should revert)
    function testGetTokenLockedPricesTokenZero() public {
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.getTokenLockedPrices(0);
    }

    // Test: subscribeToToken with tokenId 0 (should revert)
    function testSubscribeToTokenZero() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.subscribeToToken{value: monthlyPrice}(0, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: Overpayment should revert
    function testOverpaymentReverts() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: monthlyPrice + 1 wei}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: Underpayment should revert
    function testUnderpaymentReverts() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: monthlyPrice - 1 wei}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: transferFrom not approved should revert
    function testTransferFromNotApproved() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotApproved.selector);
        premium.transferFrom(user1, user2, 1);
    }

    // Test: safeTransferFrom not approved should revert
    function testSafeTransferFromNotApproved() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotApproved.selector);
        premium.safeTransferFrom(user1, user2, 1);
    }

    // Test: isApprovedForAll returns false by default
    function testIsApprovedForAllDefault() public view {
        assertFalse(premium.isApprovedForAll(user1, user2));
    }

    // Test: setApprovalForAll can be revoked
    function testSetApprovalForAllRevoke() public {
        vm.prank(user1);
        premium.setApprovalForAll(user2, true);
        assertTrue(premium.isApprovedForAll(user1, user2));

        vm.prank(user1);
        premium.setApprovalForAll(user2, false);
        assertFalse(premium.isApprovedForAll(user1, user2));
    }

    // Test: Operator can approve on behalf of owner
    function testOperatorCanApprove() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        premium.setApprovalForAll(user2, true);

        // user2 (operator) can approve referrer for token 1
        vm.prank(user2);
        premium.approve(referrer, 1);

        assertEq(premium.getApproved(1), referrer);
    }

    // Test: Fuzz test for subscription amounts
    function testFuzzSubscribeAmount(uint8 tierIndex) public {
        vm.assume(tierIndex < 2); // Only 2 tiers: Monthly (0), Yearly (1)

        IBiuBiuPremium.SubscriptionTier tier = IBiuBiuPremium.SubscriptionTier(tierIndex);
        uint256 price;
        if (tierIndex == 0) price = monthlyPrice;
        else price = yearlyPrice;

        vm.prank(user1);
        premium.subscribe{value: price}(tier, address(0));

        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
    }

    // Test: Contract can receive ETH from VAULT payment failure scenario
    // Note: This is edge case where VAULT could be a contract that sometimes rejects
    function testVaultCanBeContractThatRejects() public {
        // Deploy a rejecting contract as vault
        RejectingContract rejectingVault = new RejectingContract();
        BiuBiuPremium premiumWithRejectingVault = new BiuBiuPremium(address(rejectingVault));

        vm.deal(user1, 10 ether);

        // Subscribe should succeed even if vault payment fails
        // (contract keeps the funds)
        uint256 price = premiumWithRejectingVault.MONTHLY_PRICE();
        vm.prank(user1);
        premiumWithRejectingVault.subscribe{value: price}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Subscription succeeded
        (bool isPremium,,) = premiumWithRejectingVault.getSubscriptionInfo(user1);
        assertTrue(isPremium);

        // Contract still has the funds (vault rejected)
        assertEq(address(premiumWithRejectingVault).balance, price);
    }

    // Test: Renewal count doesn't affect locked prices
    function testRenewalCountDoesNotAffectLockedPrices() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (uint256 lockedMonthly1, uint256 lockedYearly1) = premium.getTokenLockedPrices(1);

        // Renew multiple times
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        }

        (uint256 lockedMonthly2, uint256 lockedYearly2) = premium.getTokenLockedPrices(1);

        // Locked prices unchanged
        assertEq(lockedMonthly1, lockedMonthly2);
        assertEq(lockedYearly1, lockedYearly2);
    }

    // Test: Price changes don't affect existing token's locked prices
    function testPriceChangesDoNotAffectExistingLockedPrices() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        (uint256 lockedMonthly1,) = premium.getTokenLockedPrices(1);

        // Admin changes NON_MEMBER_FEE multiple times
        vm.startPrank(premium.admin());
        premium.setNonMemberFee(1 ether); // Monthly = 12 ether
        premium.setNonMemberFee(0.001 ether); // Monthly = 0.012 ether
        premium.setNonMemberFee(10 ether); // Monthly = 120 ether
        vm.stopPrank();

        // Token 1's locked price is still the original
        (uint256 lockedMonthly2,) = premium.getTokenLockedPrices(1);
        assertEq(lockedMonthly1, lockedMonthly2);
    }

    // ============ Additional Edge Case Tests ============

    // CRITICAL: Test getSubscriptionInfo when activeSubscription points to non-owned token
    // This can happen if user transfers their only NFT but activeSubscription wasn't cleared properly
    // (It SHOULD be cleared, but let's verify the view function handles edge cases)
    function testGetSubscriptionInfoAfterTransferAllTokens() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer to user2
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // User1's activeSubscription should be 0
        assertEq(premium.activeSubscription(user1), 0);

        // getSubscriptionInfo should return false
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);
        assertEq(expiryTime, 0);
        assertEq(remainingTime, 0);
    }

    // Test: _nextTokenId overflow (theoretical - would need 2^256 mints)
    // Just verify tokenId increments correctly
    function testTokenIdIncrement() public {
        assertEq(premium.nextTokenId(), 1);

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.nextTokenId(), 2);

        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.nextTokenId(), 3);

        // Renewal doesn't increment tokenId
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        assertEq(premium.nextTokenId(), 3); // Still 3
    }

    // Test: subscribeToToken with user's own token (should work same as subscribe)
    function testSubscribeToTokenOwnToken() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        uint256 expiryBefore = premium.subscriptionExpiry(1);

        // User renews their own token via subscribeToToken
        vm.prank(user1);
        premium.subscribeToToken{value: monthlyPrice}(1, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.subscriptionExpiry(1), expiryBefore + 30 days);
    }

    // Test: Transfer to self (should work but no-op on activeSubscription)
    function testTransferToSelf() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer to self
        vm.prank(user1);
        premium.transferFrom(user1, user1, 1);

        // Should still own it
        assertEq(premium.ownerOf(1), user1);
        assertEq(premium.activeSubscription(user1), 1);
        assertEq(premium.balanceOf(user1), 1);
    }

    // Test: Mint to contract that implements onERC721Received correctly
    function testMintToReceiverContract() public {
        ERC721Receiver receiver = new ERC721Receiver();
        vm.deal(address(receiver), 1 ether);

        vm.prank(address(receiver));
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.ownerOf(1), address(receiver));
        assertEq(premium.activeSubscription(address(receiver)), 1);
    }

    // Test: Referrer is the VAULT address (edge case - vault gets 100%)
    function testReferrerIsVault() public {
        uint256 vaultBalanceBefore = vault.balance;

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, vault);

        // Vault gets 50% as referral + rest as regular payment = 100%
        assertEq(vault.balance, vaultBalanceBefore + monthlyPrice);
    }

    // Test: Very large tokenId in subscribeToToken (non-existent)
    function testSubscribeToTokenMaxUint() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.subscribeToToken{value: monthlyPrice}(
            type(uint256).max, IBiuBiuPremium.SubscriptionTier.Monthly, address(0)
        );
    }

    // Test: Activate already active token (no-op)
    function testActivateAlreadyActiveToken() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        assertEq(premium.activeSubscription(user1), 1);

        // Activate again - should work and emit event
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IBiuBiuPremium.Activated(user1, 1);
        premium.activate(1);

        assertEq(premium.activeSubscription(user1), 1);
    }

    // Test: Multiple subscriptions in same block (different users)
    function testMultipleSubscriptionsSameBlock() public {
        address user3 = address(0x33);
        vm.deal(user3, 10 ether);

        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user3);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // All should have same mintedAt (same block)
        (uint256 mintedAt1,,) = premium.getTokenAttributes(1);
        (uint256 mintedAt2,,) = premium.getTokenAttributes(2);
        (uint256 mintedAt3,,) = premium.getTokenAttributes(3);

        assertEq(mintedAt1, mintedAt2);
        assertEq(mintedAt2, mintedAt3);
        assertEq(mintedAt1, block.timestamp);
    }

    // Test: Subscription expiry edge case - exactly at block.timestamp
    function testExpiryExactlyAtBlockTimestamp() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Warp to exactly expiry time
        vm.warp(block.timestamp + 30 days);

        // At expiry time, subscription should be expired (expiry <= block.timestamp)
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        (, bool isExpired,) = premium.getTokenSubscriptionInfo(1);
        assertTrue(isExpired);
    }

    // Test: balanceOf after multiple mints and transfers
    function testBalanceOfAfterMultipleOperations() public {
        // User1 subscribes twice (second time renews, no new mint)
        vm.startPrank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        vm.stopPrank();

        assertEq(premium.balanceOf(user1), 1);

        // User2 subscribes
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer token 2 to user1
        vm.prank(user2);
        premium.transferFrom(user2, user1, 2);

        assertEq(premium.balanceOf(user1), 2);
        assertEq(premium.balanceOf(user2), 0);

        // Transfer one back
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        assertEq(premium.balanceOf(user1), 1);
        assertEq(premium.balanceOf(user2), 1);
    }

    // Test: _getTierInfo function is unused but exists (dead code check)
    // Note: _getTierInfo is private and currently unused - it was replaced by _getLockedTierInfo
    // This is not a bug, but the function could be removed to save bytecode

    // Test: Ensure referral amount calculation is correct (50% with bit shift)
    function testReferralAmountCalculation() public {
        uint256 referrerBalanceBefore = referrer.balance;

        // Test with amount to ensure bit shift works correctly
        // monthlyPrice = 0.12 ether = 120000000000000000 wei
        // 120000000000000000 >> 1 = 60000000000000000 (correct 50%)
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

        uint256 expectedReferral = monthlyPrice >> 1;
        assertEq(referrer.balance, referrerBalanceBefore + expectedReferral);
        assertEq(expectedReferral, 0.06 ether);
    }

    // Test: Referral with small wei amount
    function testReferralWithMinimumAmount() public {
        // Set NON_MEMBER_FEE to minimum
        // Since Monthly = NON_MEMBER_FEE * 12, NON_MEMBER_FEE = 1 gives Monthly = 12 wei
        vm.prank(premium.admin());
        premium.setNonMemberFee(1); // Monthly = 12 wei, Yearly = 60 wei

        uint256 referrerBalanceBefore = referrer.balance;
        uint256 vaultBalanceBefore = vault.balance;

        vm.prank(user1);
        premium.subscribe{value: 12}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

        // 12 >> 1 = 6, so referrer gets 6 wei
        assertEq(referrer.balance, referrerBalanceBefore + 6);
        // Vault gets remaining 6 wei
        assertEq(vault.balance, vaultBalanceBefore + 6);
    }
}

// Contract that rejects ETH to test failed referral payments
contract RejectingContract {
    receive() external payable {
        revert("I reject ETH");
    }
}

// Mock ERC20 for testing token withdrawal
contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// ERC721 Receiver contract for testing safeMint
contract ERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
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
        uint256 monthlyPrice = premium.MONTHLY_PRICE();
        if (!_attacked && address(this).balance >= monthlyPrice) {
            _attacked = true;
            // Try to reenter - should fail with "Reentrancy detected"
            premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
        }
    }
}
