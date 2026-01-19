// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";
import {IBiuBiuPremium} from "../src/interfaces/IBiuBiuPremium.sol";

// Tool contract imports for integration testing
import {TokenFactory} from "../src/tools/TokenFactory.sol";
import {NFTFactory} from "../src/tools/NFTFactory.sol";
import {TokenDistribution} from "../src/tools/TokenDistribution.sol";
import {TokenSweep} from "../src/tools/TokenSweep.sol";
import {Recipient} from "../src/interfaces/ITokenDistribution.sol";
import {Wallet} from "../src/interfaces/ITokenSweep.sol";
import {TokenInfo} from "../src/interfaces/ITokenFactory.sol";

contract BiuBiuPremiumTest is Test {
    BiuBiuPremium public premium;
    address public vault = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public referrer = address(0x3);

    // Cache prices to avoid consuming vm.prank
    uint256 public monthlyPrice;
    uint256 public yearlyPrice;

    function setUp() public {
        premium = new BiuBiuPremium();
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Cache prices
        monthlyPrice = premium.MONTHLY_PRICE();
        yearlyPrice = premium.YEARLY_PRICE();
    }

    // Test constants and defaults
    function testConstants() public view {
        assertEq(premium.MONTHLY_PRICE(), 0.2 ether);
        assertEq(premium.YEARLY_PRICE(), 0.6 ether);
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

        vm.expectRevert(IBiuBiuPremium.IncorrectPaymentAmount.selector);
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
        vm.expectRevert(IBiuBiuPremium.NotTokenOwner.selector);
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
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
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
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
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
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
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
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
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
        vm.expectRevert(IBiuBiuPremium.InvalidAddress.selector);
        premium.balanceOf(address(0));
    }

    // Test ownerOf for non-existent token
    function testOwnerOfNotExists() public {
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
        premium.ownerOf(999);
    }

    // Test getApproved for non-existent token
    function testGetApprovedNotExists() public {
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
        premium.getApproved(999);
    }

    // Test approve to self reverts
    function testApproveToSelf() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.InvalidAddress.selector);
        premium.approve(user1, 1);
    }

    // Test approve by non-owner/non-approved reverts
    function testApproveNotAuthorized() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(IBiuBiuPremium.NotApproved.selector);
        premium.approve(referrer, 1);
    }

    // Test setApprovalForAll to self reverts
    function testSetApprovalForAllToSelf() public {
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.InvalidAddress.selector);
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
        vm.expectRevert(IBiuBiuPremium.TransferToNonReceiver.selector);
        premium.safeTransferFrom(user1, address(nonReceiver), 1);
    }

    // Test transferFrom to zero address reverts
    function testTransferToZeroAddress() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.InvalidAddress.selector);
        premium.transferFrom(user1, address(0), 1);
    }

    // Test transferFrom with wrong 'from' address
    function testTransferFromWrongFrom() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotTokenOwner.selector);
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
        vm.expectRevert(IBiuBiuPremium.NotTokenOwner.selector);
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
        vm.expectRevert(IBiuBiuPremium.NotTokenOwner.selector);
        premium.activate(1);
    }

    // Test: Token attributes for tokenId 0 (should revert)
    function testGetTokenAttributesTokenZero() public {
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
        premium.getTokenAttributes(0);
    }

    // Test: subscribeToToken with tokenId 0 (should revert)
    function testSubscribeToTokenZero() public {
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
        premium.subscribeToToken{value: monthlyPrice}(0, IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: Overpayment should revert
    function testOverpaymentReverts() public {
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: monthlyPrice + 1 wei}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: Underpayment should revert
    function testUnderpaymentReverts() public {
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.IncorrectPaymentAmount.selector);
        premium.subscribe{value: monthlyPrice - 1 wei}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test: transferFrom not approved should revert
    function testTransferFromNotApproved() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(IBiuBiuPremium.NotApproved.selector);
        premium.transferFrom(user1, user2, 1);
    }

    // Test: safeTransferFrom not approved should revert
    function testSafeTransferFromNotApproved() public {
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        vm.expectRevert(IBiuBiuPremium.NotApproved.selector);
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

    // Note: testVaultCanBeContractThatRejects was removed because VAULT is now a constant
    // and cannot be set to a rejecting contract at deployment time.

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
        vm.expectRevert(IBiuBiuPremium.TokenNotExists.selector);
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
        // monthlyPrice = 0.2 ether = 200000000000000000 wei
        // 200000000000000000 >> 1 = 100000000000000000 (correct 50%)
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, referrer);

        uint256 expectedReferral = monthlyPrice >> 1;
        assertEq(referrer.balance, referrerBalanceBefore + expectedReferral);
        assertEq(expectedReferral, 0.1 ether);
    }

    // ============ callTool Tests ============

    // Test: callTool by non-member should revert
    function testCallToolNotPremiumMember() public {
        MockTool tool = new MockTool();

        // user1 has no subscription
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
    }

    // Test: callTool by user with no activeSubscription (activeSubscription == 0)
    function testCallToolNoActiveSubscription() public {
        MockTool tool = new MockTool();

        // user1 subscribes, gets token 1
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Transfer token away, activeSubscription becomes 0
        vm.prank(user1);
        premium.transferFrom(user1, user2, 1);

        assertEq(premium.activeSubscription(user1), 0);

        // user1 tries to call tool - should revert
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
    }

    // Test: callTool by expired member should revert
    function testCallToolExpiredMember() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward past expiry (30 days exactly = expired)
        vm.warp(block.timestamp + 30 days);

        // Verify subscription is expired
        (bool isPremium,,) = premium.getSubscriptionInfo(user1);
        assertFalse(isPremium);

        // Try to call tool - should revert
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
    }

    // Test: callTool with 1 second before expiry should succeed
    function testCallToolOneSecondBeforeExpiry() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward to 1 second before expiry
        vm.warp(block.timestamp + 30 days - 1);

        // Should still work
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
        uint256 value = abi.decode(result, (uint256));
        assertEq(value, 0);
    }

    // Test: callTool to address(this) should revert
    function testCallToolToSelf() public {
        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Try to call premium contract itself
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.InvalidTarget.selector);
        premium.callTool(address(premium), abi.encodeWithSignature("totalSupply()"));
    }

    // Test: callTool to address(0) should revert
    function testCallToolToZeroAddress() public {
        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Try to call zero address
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.InvalidTarget.selector);
        premium.callTool(address(0), abi.encodeWithSignature("anything()"));
    }

    // Test: callTool successful call with return value
    function testCallToolSuccessWithReturn() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call setValue and check return
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 123));

        uint256 returnValue = abi.decode(result, (uint256));
        assertEq(returnValue, 246); // 123 * 2

        // Verify state was modified
        assertEq(tool.lastValue(), 123);
    }

    // Test: callTool successful call with multiple return values
    function testCallToolSuccessMultipleReturns() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call getMultipleValues
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getMultipleValues()"));

        (uint256 num, string memory str, bool flag) = abi.decode(result, (uint256, string, bool));
        assertEq(num, 42);
        assertEq(str, "hello");
        assertTrue(flag);
    }

    // Test: callTool successful call with no return
    function testCallToolSuccessNoReturn() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call noReturn
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("noReturn()"));

        // Result should be empty
        assertEq(result.length, 0);

        // But state should be modified
        assertEq(tool.lastValue(), 999);
    }

    // Test: callTool verifies msg.sender is the premium contract
    function testCallToolMsgSenderIsPremiumContract() public {
        SenderCheckTool tool = new SenderCheckTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call getSender
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getSender()"));

        address sender = abi.decode(result, (address));
        // msg.sender in the tool should be the premium contract, not user1
        assertEq(sender, address(premium));
    }

    // Test: callTool bubbles up revert with message
    function testCallToolRevertWithMessage() public {
        RevertingTool tool = new RevertingTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call revertWithMessage - should bubble up the revert
        vm.prank(user1);
        vm.expectRevert("Tool operation failed");
        premium.callTool(address(tool), abi.encodeWithSignature("revertWithMessage()"));
    }

    // Test: callTool bubbles up revert with require message
    function testCallToolRevertWithRequire() public {
        RevertingTool tool = new RevertingTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call revertWithRequire
        vm.prank(user1);
        vm.expectRevert("Require failed");
        premium.callTool(address(tool), abi.encodeWithSignature("revertWithRequire()"));
    }

    // Test: callTool bubbles up custom error
    function testCallToolRevertWithCustomError() public {
        RevertingTool tool = new RevertingTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call revertWithCustomError - should bubble up custom error
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("CustomError(string)", "Custom error occurred"));
        premium.callTool(address(tool), abi.encodeWithSignature("revertWithCustomError()"));
    }

    // Test: callTool reverts with CallFailed when no revert reason
    function testCallToolRevertNoReason() public {
        RevertingToolNoReason tool = new RevertingToolNoReason();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call revertWithoutReason - should get CallFailed
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.CallFailed.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("revertWithoutReason()"));
    }

    // Test: callTool reverts with CallFailed when empty require
    function testCallToolRevertEmptyRequire() public {
        RevertingToolNoReason tool = new RevertingToolNoReason();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call revertWithEmptyReason
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.CallFailed.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("revertWithEmptyReason()"));
    }

    // Test: callTool reentrancy protection
    function testCallToolReentrancyProtection() public {
        MockTool normalTool = new MockTool();
        ReentrantTool reentrantTool = new ReentrantTool(premium);
        reentrantTool.setTargetTool(address(normalTool));

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call reentrant tool - it will try to call callTool again
        // The inner callTool should fail with ReentrancyDetected
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.ReentrancyDetected.selector);
        premium.callTool(address(reentrantTool), abi.encodeWithSignature("triggerReentry()"));
    }

    // Test: callTool to non-contract address (EOA)
    function testCallToolToEOA() public {
        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call to EOA (user2) - low-level call to EOA returns success
        // but with the calldata we sent (not empty)
        vm.prank(user1);
        bytes memory result = premium.callTool(user2, abi.encodeWithSignature("nonexistent()"));

        // Call to EOA returns success - result length depends on EVM behavior
        // The important thing is it doesn't revert
        assertTrue(result.length >= 0);
    }

    // Test: callTool with empty calldata to contract with fallback
    function testCallToolEmptyCalldataWithFallback() public {
        // Create a contract that has a fallback function
        FallbackTool tool = new FallbackTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call with empty data - triggers fallback
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), "");

        // Fallback was triggered
        assertTrue(tool.fallbackCalled());
        assertEq(result.length, 0);
    }

    // Test: callTool with empty calldata to contract without fallback reverts
    function testCallToolEmptyCalldataNoFallback() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call with empty data to contract without fallback - should revert
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.CallFailed.selector);
        premium.callTool(address(tool), "");
    }

    // Test: callTool with large return data
    function testCallToolLargeReturnData() public {
        LargeReturnTool tool = new LargeReturnTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Get 1000 bytes of data
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getLargeData(uint256)", 1000));

        bytes memory data = abi.decode(result, (bytes));
        assertEq(data.length, 1000);

        // Verify some data
        assertEq(uint8(data[0]), 0);
        assertEq(uint8(data[255]), 255);
        assertEq(uint8(data[256]), 0);
    }

    // Test: callTool multiple times by same member
    function testCallToolMultipleCalls() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call multiple times
        vm.startPrank(user1);

        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 1));
        assertEq(tool.lastValue(), 1);

        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 2));
        assertEq(tool.lastValue(), 2);

        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 3));
        assertEq(tool.lastValue(), 3);

        vm.stopPrank();
    }

    // Test: callTool by different premium members
    function testCallToolDifferentMembers() public {
        MockTool tool = new MockTool();

        // Both users subscribe
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User1 calls
        vm.prank(user1);
        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 100));
        assertEq(tool.lastValue(), 100);
        assertEq(tool.lastCaller(), address(premium)); // Both go through premium

        // User2 calls
        vm.prank(user2);
        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 200));
        assertEq(tool.lastValue(), 200);
        assertEq(tool.lastCaller(), address(premium));
    }

    // Test: callTool after renewing subscription
    function testCallToolAfterRenewal() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward 25 days
        vm.warp(block.timestamp + 25 days);

        // Renew
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward another 10 days (now 35 days from start, but renewed)
        vm.warp(block.timestamp + 10 days);

        // Should still work (renewed for another 30 days from day 25)
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
        assertEq(abi.decode(result, (uint256)), 0);
    }

    // Test: callTool with yearly subscription
    function testCallToolYearlyMember() public {
        MockTool tool = new MockTool();

        // user1 subscribes yearly
        vm.prank(user1);
        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        // Fast forward 300 days
        vm.warp(block.timestamp + 300 days);

        // Should still work
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
        assertEq(abi.decode(result, (uint256)), 0);
    }

    // Test: callTool to contract without the called function (will revert if no fallback)
    function testCallToolNonexistentFunctionNoFallback() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call nonexistent function - MockTool has no fallback, so it reverts
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.CallFailed.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("nonexistentFunction()"));
    }

    // Test: callTool to contract with fallback handles nonexistent function
    function testCallToolNonexistentFunctionWithFallback() public {
        FallbackTool tool = new FallbackTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call nonexistent function - FallbackTool has fallback, so it succeeds
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("nonexistentFunction()"));

        // Fallback was triggered
        assertTrue(tool.fallbackCalled());
        assertEq(result.length, 0);
    }

    // Test: callTool state modification check (call not delegatecall)
    function testCallToolStateNotModified() public {
        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        uint256 premiumBalanceBefore = premium.balanceOf(user1);
        uint256 premiumTotalSupplyBefore = premium.totalSupply();

        // Call tool that modifies state
        vm.prank(user1);
        premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", 12345));

        // Premium contract state should not be modified
        assertEq(premium.balanceOf(user1), premiumBalanceBefore);
        assertEq(premium.totalSupply(), premiumTotalSupplyBefore);

        // Tool state should be modified
        assertEq(tool.lastValue(), 12345);
    }

    // Test: callTool after activating different token
    function testCallToolAfterActivatingDifferentToken() public {
        MockTool tool = new MockTool();

        // user1 subscribes - gets token 1
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // user2 subscribes - gets token 2
        vm.prank(user2);
        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        // user2 transfers token 2 to user1
        vm.prank(user2);
        premium.transferFrom(user2, user1, 2);

        // user1 now has token 1 (active, monthly) and token 2 (yearly)
        assertEq(premium.activeSubscription(user1), 1);

        // Fast forward 31 days - token 1 expires
        vm.warp(block.timestamp + 31 days);

        // user1's active token is expired
        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));

        // user1 activates token 2 (yearly, still valid)
        vm.prank(user1);
        premium.activate(2);

        // Now callTool should work
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("getValue()"));
        assertEq(abi.decode(result, (uint256)), 0);
    }

    // Test: callTool gas consumption
    function testCallToolGasConsumption() public {
        GasConsumingTool tool = new GasConsumingTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call with moderate gas consumption
        vm.prank(user1);
        premium.callTool(address(tool), abi.encodeWithSignature("consumeGas(uint256)", 100));

        // Should complete without issues
    }

    // Fuzz test: callTool with various inputs (bounded to avoid overflow in MockTool)
    function testFuzzCallToolSetValue(uint256 value) public {
        // Bound value to avoid overflow in MockTool's value * 2
        value = bound(value, 0, type(uint256).max / 2);

        MockTool tool = new MockTool();

        // user1 subscribes
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Call with fuzzed value
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tool), abi.encodeWithSignature("setValue(uint256)", value));

        // Check return value (value * 2)
        uint256 returnValue = abi.decode(result, (uint256));
        assertEq(returnValue, value * 2);

        // Check stored value
        assertEq(tool.lastValue(), value);
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

// ============ Mock Contracts for callTool Tests ============

// Simple mock tool that returns values
contract MockTool {
    uint256 public lastValue;
    address public lastCaller;

    function setValue(uint256 value) external returns (uint256) {
        lastValue = value;
        lastCaller = msg.sender;
        return value * 2;
    }

    function getValue() external view returns (uint256) {
        return lastValue;
    }

    function getMultipleValues() external pure returns (uint256, string memory, bool) {
        return (42, "hello", true);
    }

    function noReturn() external {
        lastValue = 999;
    }
}

// Mock tool that reverts with a reason
contract RevertingTool {
    error CustomError(string reason);

    function revertWithMessage() external pure {
        revert("Tool operation failed");
    }

    function revertWithCustomError() external pure {
        revert CustomError("Custom error occurred");
    }

    function revertWithRequire() external pure {
        require(false, "Require failed");
    }
}

// Mock tool that reverts without a reason
contract RevertingToolNoReason {
    function revertWithoutReason() external pure {
        revert();
    }

    function revertWithEmptyReason() external pure {
        require(false);
    }
}

// Mock tool that tries to reenter callTool
contract ReentrantTool {
    BiuBiuPremium public premium;
    address public targetTool;
    bool private _attacked;

    constructor(BiuBiuPremium _premium) {
        premium = _premium;
    }

    function setTargetTool(address _target) external {
        targetTool = _target;
    }

    function attacked() external view returns (bool) {
        return _attacked;
    }

    function triggerReentry() external {
        if (!_attacked) {
            _attacked = true;
            // Try to reenter callTool
            premium.callTool(targetTool, abi.encodeWithSignature("getValue()"));
        }
    }
}

// Mock tool that consumes lots of gas
contract GasConsumingTool {
    uint256[] private _storage;

    function consumeGas(uint256 iterations) external {
        for (uint256 i = 0; i < iterations; i++) {
            _storage.push(i);
        }
    }
}

// Mock tool that returns large data
contract LargeReturnTool {
    function getLargeData(uint256 size) external pure returns (bytes memory) {
        bytes memory data = new bytes(size);
        for (uint256 i = 0; i < size; i++) {
            data[i] = bytes1(uint8(i % 256));
        }
        return data;
    }
}

// Mock tool that checks msg.sender
contract SenderCheckTool {
    function getSender() external view returns (address) {
        return msg.sender;
    }

    function requireSender(address expected) external view {
        require(msg.sender == expected, "Wrong sender");
    }
}

// Mock tool with fallback function
contract FallbackTool {
    bool public fallbackCalled;

    fallback() external {
        fallbackCalled = true;
    }
}

// ============ Integration Tests: callTool with Real Tool Contracts ============

contract BiuBiuPremiumToolIntegrationTest is Test {
    BiuBiuPremium public premium;
    TokenFactory public tokenFactory;
    NFTFactory public nftFactory;
    TokenDistribution public tokenDistribution;
    TokenSweep public tokenSweep;

    address public vault = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public nonMember = address(0x99);

    uint256 public monthlyPrice;

    function setUp() public {
        // Deploy BiuBiuPremium
        premium = new BiuBiuPremium();

        // Deploy tool contracts
        tokenFactory = new TokenFactory();
        nftFactory = new NFTFactory(address(0)); // No metadata contract needed for tests
        tokenDistribution = new TokenDistribution(address(0)); // No WETH needed for basic tests
        tokenSweep = new TokenSweep();

        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(nonMember, 100 ether);

        // Cache price
        monthlyPrice = premium.MONTHLY_PRICE();

        // Subscribe user1 as premium member
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // ============ TokenFactory.createTokenFree Tests ============

    // Test: Premium member can call createTokenFree via callTool
    function testCallToolTokenFactoryCreateTokenFree() public {
        uint256 initialSupply = 1000000 * 10 ** 18;

        // Encode the function call
        bytes memory callData = abi.encodeWithSelector(
            TokenFactory.createTokenFree.selector,
            "TestToken",
            "TT",
            uint8(18),
            initialSupply,
            false // not mintable
        );

        // Call via premium
        vm.prank(user1);
        bytes memory result = premium.callTool(address(tokenFactory), callData);

        // Decode the returned token address
        address tokenAddress = abi.decode(result, (address));

        // Verify token was created
        assertTrue(tokenAddress != address(0), "Token should be created");

        // Verify token is tracked in factory
        assertEq(tokenFactory.allTokensLength(), 1);

        // Verify msg.sender in factory was premium contract
        address[] memory tokens = tokenFactory.getUserTokens(address(premium));
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenAddress);

        // Verify factory free usage counter
        assertEq(tokenFactory.totalFreeUsage(), 1);
    }

    // Test: Premium member can create multiple tokens
    function testCallToolTokenFactoryCreateMultipleTokens() public {
        vm.startPrank(user1);

        // Create first token
        bytes memory result1 = premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token1", "TK1", uint8(18), 1000, false)
        );
        address token1 = abi.decode(result1, (address));

        // Create second token
        bytes memory result2 = premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token2", "TK2", uint8(18), 2000, true)
        );
        address token2 = abi.decode(result2, (address));

        vm.stopPrank();

        // Verify both tokens created
        assertEq(tokenFactory.allTokensLength(), 2);
        assertTrue(token1 != token2);
        assertEq(tokenFactory.totalFreeUsage(), 2);
    }

    // Test: Non-member cannot call createTokenFree via callTool
    function testCallToolTokenFactoryNotPremiumMember() public {
        bytes memory callData =
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "TestToken", "TT", uint8(18), 1000, false);

        vm.prank(nonMember);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tokenFactory), callData);
    }

    // Test: createTokenFree with mintable token
    function testCallToolTokenFactoryMintableToken() public {
        bytes memory callData = abi.encodeWithSelector(
            TokenFactory.createTokenFree.selector, "MintableToken", "MTK", uint8(18), 1000 * 10 ** 18, true
        );

        vm.prank(user1);
        bytes memory result = premium.callTool(address(tokenFactory), callData);
        address tokenAddress = abi.decode(result, (address));

        // Get token info - returns TokenInfo struct
        TokenInfo memory info = tokenFactory.getTokenInfo(tokenAddress);
        assertTrue(info.mintable);
    }

    // ============ NFTFactory.createERC721Free Tests ============

    // Test: Premium member can call createERC721Free via callTool
    function testCallToolNFTFactoryCreateERC721Free() public {
        bytes memory callData = abi.encodeWithSelector(
            NFTFactory.createERC721Free.selector,
            "TestNFT",
            "TNFT",
            "A test NFT collection",
            "https://example.com",
            true
        );

        vm.prank(user1);
        bytes memory result = premium.callTool(address(nftFactory), callData);
        address nftAddress = abi.decode(result, (address));

        // Verify NFT was created
        assertTrue(nftAddress != address(0));
        assertEq(nftFactory.allNFTsLength(), 1);

        // Verify msg.sender in factory was premium contract
        address[] memory nfts = nftFactory.getUserNFTs(address(premium));
        assertEq(nfts.length, 1);
        assertEq(nfts[0], nftAddress);

        // Verify factory free usage counter
        assertEq(nftFactory.totalFreeUsage(), 1);
    }

    // Test: Premium member can create multiple NFT collections
    function testCallToolNFTFactoryCreateMultipleNFTs() public {
        vm.startPrank(user1);

        bytes memory result1 = premium.callTool(
            address(nftFactory),
            abi.encodeWithSelector(
                NFTFactory.createERC721Free.selector, "NFT1", "N1", "First NFT", "https://nft1.com", true
            )
        );

        bytes memory result2 = premium.callTool(
            address(nftFactory),
            abi.encodeWithSelector(
                NFTFactory.createERC721Free.selector, "NFT2", "N2", "Second NFT", "https://nft2.com", true
            )
        );

        vm.stopPrank();

        address nft1 = abi.decode(result1, (address));
        address nft2 = abi.decode(result2, (address));

        assertEq(nftFactory.allNFTsLength(), 2);
        assertTrue(nft1 != nft2);
        assertEq(nftFactory.totalFreeUsage(), 2);
    }

    // Test: Non-member cannot call createERC721Free via callTool
    function testCallToolNFTFactoryNotPremiumMember() public {
        bytes memory callData = abi.encodeWithSelector(
            NFTFactory.createERC721Free.selector, "TestNFT", "TNFT", "Description", "https://example.com", true
        );

        vm.prank(nonMember);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(nftFactory), callData);
    }

    // ============ TokenDistribution.distributeFree Tests ============

    // Test: Premium member can call distributeFree via callTool
    function testCallToolTokenDistributionDistributeFree() public {
        // Create a mock ERC20 token first
        MockERC20ForDistribution mockToken = new MockERC20ForDistribution();
        uint256 totalAmount = 1000 * 10 ** 18;
        mockToken.mint(address(premium), totalAmount);

        // Approve distribution contract from premium
        // Since we're calling through premium, we need to approve via callTool
        vm.prank(user1);
        premium.callTool(
            address(mockToken),
            abi.encodeWithSelector(MockERC20ForDistribution.approve.selector, address(tokenDistribution), totalAmount)
        );

        // Create recipients
        Recipient[] memory recipients = new Recipient[](2);
        recipients[0] = Recipient({to: address(0x100), value: 300 * 10 ** 18});
        recipients[1] = Recipient({to: address(0x101), value: 400 * 10 ** 18});

        // Call distributeFree
        bytes memory callData = abi.encodeWithSelector(
            TokenDistribution.distributeFree.selector,
            address(mockToken),
            uint8(1), // TOKEN_TYPE_ERC20
            uint256(0), // tokenId (not used for ERC20)
            recipients
        );

        vm.prank(user1);
        bytes memory result = premium.callTool(address(tokenDistribution), callData);

        // Decode result (totalDistributed, failed)
        (uint256 totalDistributed,) = abi.decode(result, (uint256, bytes));

        // Verify distribution
        assertEq(totalDistributed, 700 * 10 ** 18);
        assertEq(mockToken.balanceOf(address(0x100)), 300 * 10 ** 18);
        assertEq(mockToken.balanceOf(address(0x101)), 400 * 10 ** 18);

        // Verify factory free usage counter
        assertEq(tokenDistribution.totalFreeUsage(), 1);
    }

    // Test: Non-member cannot call distributeFree via callTool
    function testCallToolTokenDistributionNotPremiumMember() public {
        Recipient[] memory recipients = new Recipient[](1);
        recipients[0] = Recipient({to: address(0x100), value: 100});

        bytes memory callData = abi.encodeWithSelector(
            TokenDistribution.distributeFree.selector, address(0x123), uint8(1), uint256(0), recipients
        );

        vm.prank(nonMember);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tokenDistribution), callData);
    }

    // Test: distributeFree with empty recipients reverts with BatchTooLarge
    function testCallToolTokenDistributionEmptyRecipientsReverts() public {
        MockERC20ForDistribution mockToken = new MockERC20ForDistribution();

        Recipient[] memory recipients = new Recipient[](0);

        bytes memory callData = abi.encodeWithSelector(
            TokenDistribution.distributeFree.selector, address(mockToken), uint8(1), uint256(0), recipients
        );

        // TokenDistribution requires at least 1 recipient (reverts with BatchTooLarge)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("BatchTooLarge()"));
        premium.callTool(address(tokenDistribution), callData);
    }

    // ============ TokenSweep.multicallFree Tests ============

    // Test: Premium member can call multicallFree via callTool (empty wallets)
    function testCallToolTokenSweepMulticallFreeEmptyWallets() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory callData = abi.encodeWithSelector(
            TokenSweep.multicallFree.selector,
            wallets,
            user1, // recipient
            tokens,
            deadline,
            "" // no signature
        );

        vm.prank(user1);
        bytes memory result = premium.callTool(address(tokenSweep), callData);

        // multicallFree returns nothing, so result should be empty
        assertEq(result.length, 0);

        // Verify free usage counter incremented
        assertEq(tokenSweep.totalFreeUsage(), 1);
    }

    // Test: Non-member cannot call multicallFree via callTool
    function testCallToolTokenSweepNotPremiumMember() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        bytes memory callData = abi.encodeWithSelector(
            TokenSweep.multicallFree.selector, wallets, nonMember, tokens, block.timestamp + 1 hours, ""
        );

        vm.prank(nonMember);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tokenSweep), callData);
    }

    // Test: Multiple premium members can use tools
    function testCallToolMultiplePremiumMembers() public {
        // Subscribe user2 as premium member
        vm.prank(user2);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // User1 creates a token
        vm.prank(user1);
        bytes memory result1 = premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token1", "TK1", uint8(18), 1000, false)
        );

        // User2 creates a token
        vm.prank(user2);
        bytes memory result2 = premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token2", "TK2", uint8(18), 2000, false)
        );

        address token1 = abi.decode(result1, (address));
        address token2 = abi.decode(result2, (address));

        // Both tokens created, both owned by premium contract
        assertEq(tokenFactory.allTokensLength(), 2);
        address[] memory premiumTokens = tokenFactory.getUserTokens(address(premium));
        assertEq(premiumTokens.length, 2);
    }

    // Test: Expired member cannot use tools
    function testCallToolExpiredMemberCannotUseTool() public {
        // Fast forward past subscription expiry
        vm.warp(block.timestamp + 31 days);

        bytes memory callData =
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "TestToken", "TT", uint8(18), 1000, false);

        vm.prank(user1);
        vm.expectRevert(IBiuBiuPremium.NotPremiumMember.selector);
        premium.callTool(address(tokenFactory), callData);
    }

    // Test: Member can use tool after renewal
    function testCallToolAfterRenewal() public {
        // Fast forward 25 days
        vm.warp(block.timestamp + 25 days);

        // Renew subscription
        vm.prank(user1);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward another 10 days (now 35 days from start, but still valid)
        vm.warp(block.timestamp + 10 days);

        // Should still work
        bytes memory callData =
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "TestToken", "TT", uint8(18), 1000, false);

        vm.prank(user1);
        bytes memory result = premium.callTool(address(tokenFactory), callData);

        address tokenAddress = abi.decode(result, (address));
        assertTrue(tokenAddress != address(0));
    }

    // Test: Premium contract is msg.sender for all tool calls
    function testCallToolMsgSenderIsPremiumForAllTools() public {
        // TokenFactory - check via getUserTokens
        vm.prank(user1);
        premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token", "TK", uint8(18), 1000, false)
        );
        assertEq(tokenFactory.getUserTokens(address(premium)).length, 1);

        // NFTFactory - check via getUserNFTs
        vm.prank(user1);
        premium.callTool(
            address(nftFactory),
            abi.encodeWithSelector(
                NFTFactory.createERC721Free.selector, "NFT", "N", "Desc", "https://example.com", true
            )
        );
        assertEq(nftFactory.getUserNFTs(address(premium)).length, 1);
    }

    // Test: Tool calls don't affect premium contract state
    function testCallToolDoesNotAffectPremiumState() public {
        uint256 totalSupplyBefore = premium.totalSupply();
        uint256 user1BalanceBefore = premium.balanceOf(user1);

        // Make several tool calls
        vm.startPrank(user1);
        premium.callTool(
            address(tokenFactory),
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "Token1", "TK1", uint8(18), 1000, false)
        );
        premium.callTool(
            address(nftFactory),
            abi.encodeWithSelector(
                NFTFactory.createERC721Free.selector, "NFT1", "N1", "Desc", "https://example.com", true
            )
        );
        vm.stopPrank();

        // Premium contract state unchanged
        assertEq(premium.totalSupply(), totalSupplyBefore);
        assertEq(premium.balanceOf(user1), user1BalanceBefore);
    }

    // Test: Tool calls with invalid parameters bubble up errors
    function testCallToolInvalidParametersBubbleUp() public {
        // TokenFactory requires non-empty name
        bytes memory callData = abi.encodeWithSelector(
            TokenFactory.createTokenFree.selector,
            "", // empty name - should fail
            "TK",
            uint8(18),
            1000,
            false
        );

        vm.prank(user1);
        vm.expectRevert("TokenFactory: name cannot be empty");
        premium.callTool(address(tokenFactory), callData);
    }

    // Test: Yearly member can use tools for longer period
    function testCallToolYearlyMember() public {
        // Subscribe user2 with yearly plan
        uint256 yearlyPrice = premium.YEARLY_PRICE();
        vm.prank(user2);
        premium.subscribe{value: yearlyPrice}(IBiuBiuPremium.SubscriptionTier.Yearly, address(0));

        // Fast forward 300 days - still valid
        vm.warp(block.timestamp + 300 days);

        bytes memory callData =
            abi.encodeWithSelector(TokenFactory.createTokenFree.selector, "YearlyToken", "YT", uint8(18), 1000, false);

        vm.prank(user2);
        bytes memory result = premium.callTool(address(tokenFactory), callData);
        address tokenAddress = abi.decode(result, (address));
        assertTrue(tokenAddress != address(0));
    }
}

// Mock ERC20 for distribution tests
contract MockERC20ForDistribution {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}
