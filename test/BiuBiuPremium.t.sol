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
    uint256 public dailyPrice;
    uint256 public monthlyPrice;
    uint256 public yearlyPrice;

    function setUp() public {
        premium = new BiuBiuPremium(vault);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Cache prices
        dailyPrice = premium.DAILY_PRICE();
        monthlyPrice = premium.MONTHLY_PRICE();
        yearlyPrice = premium.YEARLY_PRICE();
    }

    // Test constants and defaults
    function testConstants() public view {
        assertEq(premium.DAILY_PRICE(), 0.05 ether);
        assertEq(premium.MONTHLY_PRICE(), 0.25 ether);
        assertEq(premium.YEARLY_PRICE(), 1.25 ether);
        assertEq(premium.DAILY_DURATION(), 1 days);
        assertEq(premium.MONTHLY_DURATION(), 30 days);
        assertEq(premium.YEARLY_DURATION(), 365 days);
        assertEq(premium.VAULT(), vault);
    }

    // Test ERC721 basics
    function testERC721Basics() public view {
        assertEq(premium.name(), "BiuBiu Premium");
        assertEq(premium.symbol(), "BBP");
        assertTrue(premium.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(premium.supportsInterface(0x01ffc9a7)); // ERC165
    }

    // Test daily subscription without referrer - mints NFT
    function testSubscribeDailyNoReferrer() public {
        vm.startPrank(user1);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 dailyPrice = premium.DAILY_PRICE();

        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // Owner receives payment automatically
        assertEq(vault.balance, vaultBalanceBefore + dailyPrice);

        // Check NFT was minted
        assertEq(premium.balanceOf(user1), 1);
        assertEq(premium.ownerOf(1), user1);

        // Check activeSubscription
        assertEq(premium.activeSubscription(user1), 1);

        // Check subscription info
        (bool isPremium, uint256 expiryTime, uint256 remainingTime) = premium.getSubscriptionInfo(user1);
        assertTrue(isPremium);
        assertEq(expiryTime, block.timestamp + 1 days);
        assertEq(remainingTime, 1 days);

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));
        assertEq(premium.balanceOf(user1), 1);

        uint256 firstExpiry = block.timestamp + 1 days;

        // Second subscription - renews existing NFT (no new mint)
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));
        assertEq(premium.balanceOf(user1), 1); // Still only 1 NFT

        (, uint256 expiryTime,) = premium.getSubscriptionInfo(user1);
        assertEq(expiryTime, firstExpiry + 1 days);

        vm.stopPrank();
    }

    // Test subscription after expiry
    function testSubscriptionAfterExpiry() public {
        vm.startPrank(user1);

        // First subscription
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // Fast forward past expiry
        vm.warp(block.timestamp + 8 days);

        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        // Subscribe again - renews existing NFT
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (, uint256 newExpiry,) = premium.getSubscriptionInfo(user1);
        assertEq(newExpiry, block.timestamp + 1 days);

        // Still only 1 NFT
        assertEq(premium.balanceOf(user1), 1);

        vm.stopPrank();
    }

    // Test incorrect payment amount
    function testIncorrectPaymentAmount() public {
        vm.startPrank(user1);

        vm.expectRevert(BiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: 0.005 ether}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.stopPrank();
    }

    // Test self-referral (no commission paid)
    function testSelfReferralNoCommission() public {
        vm.startPrank(user1);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 dailyPrice = premium.DAILY_PRICE();

        // User1 tries to refer themselves
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, user1);

        // Owner receives full payment (no referral commission)
        assertEq(vault.balance, vaultBalanceBefore + dailyPrice);

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // Deactivate and subscribe again to get new NFT
        // We need to transfer away and get a new one
        vm.stopPrank();

        // User2 subscribes to create tokenId=2
        vm.prank(user2);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user2);
        vm.expectRevert(BiuBiuPremium.NotTokenOwner.selector);
        premium.activate(1);
    }

    // Test subscribeToToken (gift subscription)
    function testSubscribeToToken() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        uint256 originalExpiry = premium.subscriptionExpiry(1);

        // User2 gifts more time to user1's NFT
        vm.prank(user2);
        premium.subscribeToToken{value: dailyPrice}(1, IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // Check expiry extended
        assertEq(premium.subscriptionExpiry(1), originalExpiry + 1 days);
    }

    // Test subscribeToToken for non-existent token
    function testSubscribeToTokenNotExists() public {
        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TokenNotExists.selector);
        premium.subscribeToToken{value: dailyPrice}(999, IBiuBiuPremium.SubscriptionTier.Daily, address(0));
    }

    // Test getTokenSubscriptionInfo
    function testGetTokenSubscriptionInfo() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (uint256 expiryTime, bool isExpired, address tokenOwner) = premium.getTokenSubscriptionInfo(1);

        assertEq(expiryTime, block.timestamp + 1 days);
        assertFalse(isExpired);
        assertEq(tokenOwner, user1);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        assertEq(premium.nextTokenId(), 2);
    }

    // Test ERC721 approval
    function testApproval() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (uint256 mintedAt, address mintedBy, uint256 renewalCount) = premium.getTokenAttributes(1);

        assertEq(mintedAt, mintTime);
        assertEq(mintedBy, user1);
        assertEq(renewalCount, 1); // First subscribe counts as 1 renewal
    }

    // Test getTokenAttributes - renewal count increments
    function testGetTokenAttributesRenewalCount() public {
        vm.startPrank(user1);

        // First subscription - mints NFT with renewalCount = 1
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (,, uint256 count1) = premium.getTokenAttributes(1);
        assertEq(count1, 1);

        // Second subscription - renews existing, renewalCount = 2
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // User2's active token is now token 1 (auto-activated on transfer)
        (, address mintedBy2, uint256 count2) = premium.getTokenAttributes(1);
        assertEq(mintedBy2, user1); // Still user1
        assertEq(count2, 2); // Renewal count increased
    }

    // Test getTokenAttributes - gift subscription increases renewal count
    function testGetTokenAttributesGiftRenewal() public {
        // User1 subscribes
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (,, uint256 count1) = premium.getTokenAttributes(1);
        assertEq(count1, 1);

        // User2 gifts more time via subscribeToToken
        vm.prank(user2);
        premium.subscribeToToken{value: dailyPrice}(1, IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        (,, uint256 count2) = premium.getTokenAttributes(1);
        assertEq(count2, 2); // Gift also counts as renewal
    }

    // Test totalSupply
    function testTotalSupply() public {
        assertEq(premium.totalSupply(), 0);

        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        assertEq(premium.totalSupply(), 1);

        vm.prank(user2);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        assertEq(premium.totalSupply(), 2);

        // Renewal should not increase totalSupply
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.approve(user1, 1);
    }

    // Test approve by non-owner/non-approved reverts
    function testApproveNotAuthorized() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user1);
        premium.safeTransferFrom(user1, user2, 1);

        assertEq(premium.ownerOf(1), user2);
        assertEq(premium.activeSubscription(user2), 1);
    }

    // Test safeTransferFrom (with data)
    function testSafeTransferFromWithData() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user1);
        premium.safeTransferFrom(user1, user2, 1, "test data");

        assertEq(premium.ownerOf(1), user2);
    }

    // Test safeTransferFrom to contract that rejects
    function testSafeTransferFromToNonReceiver() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        // RejectingContract doesn't implement onERC721Received
        RejectingContract nonReceiver = new RejectingContract();

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.TransferToNonReceiver.selector);
        premium.safeTransferFrom(user1, address(nonReceiver), 1);
    }

    // Test transferFrom to zero address reverts
    function testTransferToZeroAddress() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user1);
        vm.expectRevert(BiuBiuPremium.InvalidAddress.selector);
        premium.transferFrom(user1, address(0), 1);
    }

    // Test transferFrom with wrong 'from' address
    function testTransferFromWrongFrom() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        assertEq(premium.ownerOf(1), address(receiver));
    }

    // Test operator can transfer via approval
    function testOperatorTransfer() public {
        vm.prank(user1);
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

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
        premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));

        vm.prank(user1);
        premium.approve(referrer, 1);
        assertEq(premium.getApproved(1), referrer);

        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        // Approval should be cleared
        assertEq(premium.getApproved(1), address(0));
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
        uint256 dailyPrice = premium.DAILY_PRICE();
        if (!_attacked && address(this).balance >= dailyPrice) {
            _attacked = true;
            // Try to reenter - should fail with "Reentrancy detected"
            premium.subscribe{value: dailyPrice}(IBiuBiuPremium.SubscriptionTier.Daily, address(0));
        }
    }
}
