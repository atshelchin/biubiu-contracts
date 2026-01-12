// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/knock/KnockCard.sol";
import "../src/knock/KnockProtocol.sol";

contract KnockProtocolTest is Test {
    KnockCard public card;
    KnockProtocol public protocol;

    address public owner = address(this);
    address public protocolFeeReceiver = address(0x999);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public carol = address(0x3);

    uint256 public constant CARD_FEE = 0.1 ether;
    uint256 public constant MIN_BID = 0.01 ether;

    function setUp() public {
        card = new KnockCard();
        protocol = new KnockProtocol(address(card), protocolFeeReceiver);
        card.setProtocol(address(protocol));

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
    }

    // ============ Card Tests ============

    function test_CreateCard() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "@alice", "", "");

        assertTrue(card.hasCard(alice));
        IKnockCard.Card memory c = card.getCard(alice);
        assertEq(c.nickname, "Alice");
        assertEq(c.bio, "Hello");
    }

    function test_CreateCard_RevertIfAlreadyExists() public {
        vm.startPrank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        vm.expectRevert(IKnockCard.CardAlreadyExists.selector);
        card.createCard{value: CARD_FEE}("Alice2", "Hello2", "", "", "", "");
        vm.stopPrank();
    }

    function test_CreateCard_RevertIfInsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert(IKnockCard.InsufficientPayment.selector);
        card.createCard{value: 0.05 ether}("Alice", "Hello", "", "", "", "");
    }

    function test_UpdateCard() public {
        vm.startPrank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");
        card.updateCard{value: CARD_FEE}("Alice Updated", "New bio", "", "@newalice", "", "");
        vm.stopPrank();

        IKnockCard.Card memory c = card.getCard(alice);
        assertEq(c.nickname, "Alice Updated");
        assertEq(c.bio, "New bio");
        assertEq(c.twitter, "@newalice");
    }

    function test_CardTransferNotAllowed() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        vm.expectRevert(IKnockCard.TransferNotAllowed.selector);
        card.transferFrom(alice, bob, uint256(uint160(alice)));
    }

    // ============ Knock Tests ============

    function test_SendKnock() public {
        // Create cards
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        // Send knock
        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 0.1 ether}(bob, keccak256("content1"));

        assertEq(knockId, 1);
        IKnockProtocol.Knock memory k = protocol.getKnock(knockId);
        assertEq(k.sender, alice);
        assertEq(k.receiver, bob);
        assertEq(k.bid, 0.1 ether);
        assertEq(uint256(k.status), uint256(IKnockProtocol.KnockStatus.Pending));
    }

    function test_SendKnock_RevertIfNoCard() public {
        vm.prank(alice);
        vm.expectRevert(IKnockProtocol.NoCard.selector);
        protocol.knock{value: 0.1 ether}(bob, keccak256("content1"));
    }

    function test_SendKnock_RevertIfBidTooLow() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        vm.prank(alice);
        vm.expectRevert(IKnockProtocol.BidTooLow.selector);
        protocol.knock{value: 0.005 ether}(bob, keccak256("content1"));
    }

    function test_SendKnock_RevertIfTooManyPending() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        vm.startPrank(alice);
        protocol.knock{value: 0.1 ether}(bob, keccak256("content1"));
        protocol.knock{value: 0.1 ether}(bob, keccak256("content2"));
        protocol.knock{value: 0.1 ether}(bob, keccak256("content3"));

        vm.expectRevert(IKnockProtocol.TooManyPendingKnocks.selector);
        protocol.knock{value: 0.1 ether}(bob, keccak256("content4"));
        vm.stopPrank();
    }

    function test_SendKnock_RevertIfKnockSelf() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "Hello", "", "", "", "");

        vm.prank(alice);
        vm.expectRevert(IKnockProtocol.CannotKnockSelf.selector);
        protocol.knock{value: 0.1 ether}(alice, keccak256("content1"));
    }

    // ============ Settlement Tests ============

    function test_Settlement_SelectsTopBids() public {
        // Create cards for senders
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");
        vm.prank(carol);
        card.createCard{value: CARD_FEE}("Carol", "", "", "", "", "");

        // Bob sets 1 slot
        vm.prank(bob);
        protocol.setDailySlots(1);

        // Alice and Carol send knocks
        vm.prank(alice);
        uint256 knockId1 = protocol.knock{value: 0.1 ether}(bob, keccak256("alice"));
        vm.prank(carol);
        uint256 knockId2 = protocol.knock{value: 0.2 ether}(bob, keccak256("carol"));

        // Move to next day and settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        // Carol's knock (higher bid) should be settled
        IKnockProtocol.Knock memory k1 = protocol.getKnock(knockId1);
        IKnockProtocol.Knock memory k2 = protocol.getKnock(knockId2);

        assertEq(uint256(k1.status), uint256(IKnockProtocol.KnockStatus.Refunded));
        assertEq(uint256(k2.status), uint256(IKnockProtocol.KnockStatus.Settled));
    }

    function test_Settlement_RefundsNotSelected() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");

        vm.prank(bob);
        protocol.setDailySlots(1);

        // Send knock
        vm.prank(alice);
        protocol.knock{value: 0.1 ether}(bob, keccak256("alice"));

        // Carol sends higher bid
        vm.prank(carol);
        card.createCard{value: CARD_FEE}("Carol", "", "", "", "", "");
        vm.prank(carol);
        protocol.knock{value: 0.2 ether}(bob, keccak256("carol"));

        uint256 aliceBalanceBefore = alice.balance;

        // Settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        // Alice should get 100% refund
        assertEq(alice.balance, aliceBalanceBefore + 0.1 ether);
    }

    // ============ Accept/Reject Tests ============

    function test_Accept() public {
        // Setup
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");
        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 1 ether}(bob, keccak256("content"));

        // Settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        // Record balances
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;
        uint256 protocolBalanceBefore = protocolFeeReceiver.balance;

        // Accept
        vm.prank(bob);
        protocol.accept(knockId);

        // Check distribution: Sender 40%, Receiver 40%, Protocol 20%
        assertEq(alice.balance, aliceBalanceBefore + 0.4 ether);
        assertEq(bob.balance, bobBalanceBefore + 0.4 ether);
        assertEq(protocolFeeReceiver.balance, protocolBalanceBefore + 0.2 ether);

        // Check status
        IKnockProtocol.Knock memory k = protocol.getKnock(knockId);
        assertEq(uint256(k.status), uint256(IKnockProtocol.KnockStatus.Accepted));
    }

    function test_Reject() public {
        // Setup
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");
        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 1 ether}(bob, keccak256("content"));

        // Settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        // Record balances
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;
        uint256 protocolBalanceBefore = protocolFeeReceiver.balance;

        // Reject
        vm.prank(bob);
        protocol.reject(knockId);

        // Check distribution: Receiver 80%, Protocol 20%
        assertEq(alice.balance, aliceBalanceBefore); // Sender gets nothing
        assertEq(bob.balance, bobBalanceBefore + 0.8 ether);
        assertEq(protocolFeeReceiver.balance, protocolBalanceBefore + 0.2 ether);

        // Check status
        IKnockProtocol.Knock memory k = protocol.getKnock(knockId);
        assertEq(uint256(k.status), uint256(IKnockProtocol.KnockStatus.Rejected));
    }

    // ============ Expiry Tests ============

    function test_ClaimExpired() public {
        // Setup
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");
        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 1 ether}(bob, keccak256("content"));

        // Settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        uint256 aliceBalanceBefore = alice.balance;

        // Wait 7 days and claim
        vm.warp(block.timestamp + 7 days);
        protocol.claimExpired(knockId);

        // Alice gets 100% refund
        assertEq(alice.balance, aliceBalanceBefore + 1 ether);

        // Check status
        IKnockProtocol.Knock memory k = protocol.getKnock(knockId);
        assertEq(uint256(k.status), uint256(IKnockProtocol.KnockStatus.Expired));
    }

    function test_ClaimExpired_RevertIfNotExpired() public {
        // Setup
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");
        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 1 ether}(bob, keccak256("content"));

        // Settle
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);

        // Try to claim before expiry
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(IKnockProtocol.NotExpired.selector);
        protocol.claimExpired(knockId);
    }

    // ============ Stats Tests ============

    function test_ReceiverStats() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");

        vm.prank(alice);
        protocol.knock{value: 0.5 ether}(bob, keccak256("content"));

        IKnockProtocol.ReceiverStats memory stats = protocol.getReceiverStats(bob);
        assertEq(stats.totalReceived, 1);
        assertEq(stats.totalEthReceived, 0.5 ether);
    }

    function test_SenderStats() public {
        vm.prank(alice);
        card.createCard{value: CARD_FEE}("Alice", "", "", "", "", "");

        vm.prank(alice);
        uint256 knockId = protocol.knock{value: 0.5 ether}(bob, keccak256("content"));

        // Settle and accept
        vm.warp(block.timestamp + 1 days);
        protocol.settle(bob);
        vm.prank(bob);
        protocol.accept(knockId);

        IKnockCard.Card memory c = card.getCard(alice);
        assertEq(c.knocksSent, 1);
        assertEq(c.knocksAccepted, 1);
    }
}
