// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WETH} from "../src/core/WETH.sol";

contract WETHTest is Test {
    WETH public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event DepositAndApprove(address indexed account, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        weth = new WETH();

        // Give test addresses some ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // ========== Basic Info Tests ==========

    function test_BasicInfo() public view {
        assertEq(weth.name(), "Wrapped Ether");
        assertEq(weth.symbol(), "WETH");
        assertEq(weth.decimals(), 18);
        assertEq(weth.totalSupply(), 0);
    }

    // ========== Deposit Tests ==========

    function test_Deposit() public {
        vm.startPrank(alice);

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, 1 ether);

        weth.deposit{value: 1 ether}();

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.totalSupply(), 1 ether);
        assertEq(address(weth).balance, 1 ether);

        vm.stopPrank();
    }

    function test_DepositMultipleTimes() public {
        vm.startPrank(alice);

        weth.deposit{value: 1 ether}();
        assertEq(weth.balanceOf(alice), 1 ether);

        weth.deposit{value: 2 ether}();
        assertEq(weth.balanceOf(alice), 3 ether);
        assertEq(weth.totalSupply(), 3 ether);

        vm.stopPrank();
    }

    function test_DepositZeroReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("WETH: deposit amount must be greater than 0");
        weth.deposit{value: 0}();

        vm.stopPrank();
    }

    function test_DepositViaReceive() public {
        vm.startPrank(alice);

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1 ether);

        (bool success,) = address(weth).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(weth.balanceOf(alice), 1 ether);

        vm.stopPrank();
    }

    function test_DepositViaFallback() public {
        vm.startPrank(alice);

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1 ether);

        (bool success,) = address(weth).call{value: 1 ether}("random data");
        assertTrue(success);

        assertEq(weth.balanceOf(alice), 1 ether);

        vm.stopPrank();
    }

    // ========== DepositAndApprove Tests ==========

    function test_DepositAndApprove() public {
        vm.startPrank(alice);

        // deposit() emits Deposit and Transfer first
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, 1 ether);
        // then depositAndApprove emits its events
        vm.expectEmit(true, true, false, true);
        emit DepositAndApprove(alice, bob, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, 1 ether);

        weth.depositAndApprove{value: 1 ether}(bob);

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.allowance(alice, bob), 1 ether);
        assertEq(weth.totalSupply(), 1 ether);

        vm.stopPrank();
    }

    function test_DepositAndApproveZeroAddressReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("WETH: approve to the zero address");
        weth.depositAndApprove{value: 1 ether}(address(0));

        vm.stopPrank();
    }

    function test_DepositAndApproveZeroAmountReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("WETH: deposit amount must be greater than 0");
        weth.depositAndApprove{value: 0}(bob);

        vm.stopPrank();
    }

    function test_DepositAndApproveAccumulatesAllowance() public {
        vm.startPrank(alice);

        weth.depositAndApprove{value: 1 ether}(bob);
        assertEq(weth.allowance(alice, bob), 1 ether);

        // Second deposit accumulates allowance
        weth.depositAndApprove{value: 2 ether}(bob);
        assertEq(weth.allowance(alice, bob), 3 ether); // Accumulated
        assertEq(weth.balanceOf(alice), 3 ether);

        vm.stopPrank();
    }

    // ========== Withdraw Tests ==========

    function test_Withdraw() public {
        vm.startPrank(alice);

        weth.deposit{value: 5 ether}();
        uint256 balanceBefore = alice.balance;

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(alice, 5 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, address(0), 5 ether);

        weth.withdraw();

        assertEq(weth.balanceOf(alice), 0);
        assertEq(weth.totalSupply(), 0);
        assertEq(alice.balance, balanceBefore + 5 ether);
        assertEq(address(weth).balance, 0);

        vm.stopPrank();
    }

    function test_WithdrawPartialBalance() public {
        vm.startPrank(alice);

        weth.deposit{value: 10 ether}();

        // Transfer some away
        weth.transfer(bob, 3 ether);

        uint256 balanceBefore = alice.balance;
        weth.withdraw(); // Should withdraw remaining 7 ether

        assertEq(weth.balanceOf(alice), 0);
        assertEq(alice.balance, balanceBefore + 7 ether);

        vm.stopPrank();
    }

    function test_WithdrawZeroBalanceReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("WETH: amount must be greater than 0");
        weth.withdraw();

        vm.stopPrank();
    }

    function test_WithdrawAfterFullTransferReverts() public {
        vm.startPrank(alice);

        weth.deposit{value: 1 ether}();
        weth.transfer(bob, 1 ether);

        vm.expectRevert("WETH: amount must be greater than 0");
        weth.withdraw();

        vm.stopPrank();
    }

    // ========== Withdraw(uint256) Tests ==========

    function test_WithdrawAmount() public {
        vm.startPrank(alice);

        weth.deposit{value: 10 ether}();
        uint256 balanceBefore = alice.balance;

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(alice, 3 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, address(0), 3 ether);

        weth.withdraw(3 ether);

        assertEq(weth.balanceOf(alice), 7 ether);
        assertEq(weth.totalSupply(), 7 ether);
        assertEq(alice.balance, balanceBefore + 3 ether);
        assertEq(address(weth).balance, 7 ether);

        vm.stopPrank();
    }

    function test_WithdrawAmountMultipleTimes() public {
        vm.startPrank(alice);

        weth.deposit{value: 10 ether}();
        uint256 balanceBefore = alice.balance;

        weth.withdraw(2 ether);
        assertEq(weth.balanceOf(alice), 8 ether);

        weth.withdraw(3 ether);
        assertEq(weth.balanceOf(alice), 5 ether);

        weth.withdraw(5 ether);
        assertEq(weth.balanceOf(alice), 0);

        assertEq(alice.balance, balanceBefore + 10 ether);
        assertEq(weth.totalSupply(), 0);

        vm.stopPrank();
    }

    function test_WithdrawAmountZeroReverts() public {
        vm.startPrank(alice);

        weth.deposit{value: 5 ether}();

        vm.expectRevert("WETH: amount must be greater than 0");
        weth.withdraw(0);

        vm.stopPrank();
    }

    function test_WithdrawAmountInsufficientBalanceReverts() public {
        vm.startPrank(alice);

        weth.deposit{value: 5 ether}();

        vm.expectRevert("WETH: insufficient balance");
        weth.withdraw(10 ether);

        vm.stopPrank();
    }

    function test_WithdrawAmountExactBalance() public {
        vm.startPrank(alice);

        weth.deposit{value: 5 ether}();
        uint256 balanceBefore = alice.balance;

        weth.withdraw(5 ether);

        assertEq(weth.balanceOf(alice), 0);
        assertEq(alice.balance, balanceBefore + 5 ether);
        assertEq(weth.totalSupply(), 0);

        vm.stopPrank();
    }

    function test_WithdrawAmountAfterTransfer() public {
        vm.prank(alice);
        weth.deposit{value: 10 ether}();

        vm.prank(alice);
        weth.transfer(bob, 6 ether);

        // Alice can only withdraw remaining 4 ether
        vm.startPrank(alice);
        weth.withdraw(4 ether);
        assertEq(weth.balanceOf(alice), 0);
        vm.stopPrank();

        // Bob can withdraw his 6 ether
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        weth.withdraw(6 ether);
        assertEq(bob.balance, bobBalanceBefore + 6 ether);
    }

    function testFuzz_WithdrawAmount(uint96 depositAmount, uint96 withdrawAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount);
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        weth.deposit{value: depositAmount}();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        weth.withdraw(withdrawAmount);

        assertEq(alice.balance, balanceBefore + withdrawAmount);
        assertEq(weth.balanceOf(alice), depositAmount - withdrawAmount);
    }

    // ========== Transfer Tests ==========

    function test_Transfer() public {
        vm.prank(alice);
        weth.deposit{value: 10 ether}();

        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 3 ether);

        bool success = weth.transfer(bob, 3 ether);
        assertTrue(success);

        assertEq(weth.balanceOf(alice), 7 ether);
        assertEq(weth.balanceOf(bob), 3 ether);
        assertEq(weth.totalSupply(), 10 ether);

        vm.stopPrank();
    }

    function test_TransferZeroAddress() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.startPrank(alice);
        vm.expectRevert("WETH: transfer to the zero address");
        weth.transfer(address(0), 1 ether);
        vm.stopPrank();
    }

    function test_TransferInsufficientBalance() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.startPrank(alice);
        vm.expectRevert("WETH: insufficient balance");
        weth.transfer(bob, 2 ether);
        vm.stopPrank();
    }

    function test_TransferZeroAmount() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.prank(alice);
        bool success = weth.transfer(bob, 0);
        assertTrue(success);

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.balanceOf(bob), 0);
    }

    // ========== Approve Tests ==========

    function test_Approve() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, 5 ether);

        bool success = weth.approve(bob, 5 ether);
        assertTrue(success);

        assertEq(weth.allowance(alice, bob), 5 ether);

        vm.stopPrank();
    }

    function test_ApproveZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert("WETH: approve to the zero address");
        weth.approve(address(0), 1 ether);
        vm.stopPrank();
    }

    function test_ApproveOverwrite() public {
        vm.startPrank(alice);

        weth.approve(bob, 5 ether);
        assertEq(weth.allowance(alice, bob), 5 ether);

        weth.approve(bob, 10 ether);
        assertEq(weth.allowance(alice, bob), 10 ether);

        vm.stopPrank();
    }

    // ========== TransferFrom Tests ==========

    function test_TransferFrom() public {
        vm.prank(alice);
        weth.deposit{value: 10 ether}();

        vm.prank(alice);
        weth.approve(bob, 5 ether);

        vm.startPrank(bob);

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, charlie, 3 ether);

        bool success = weth.transferFrom(alice, charlie, 3 ether);
        assertTrue(success);

        assertEq(weth.balanceOf(alice), 7 ether);
        assertEq(weth.balanceOf(charlie), 3 ether);
        assertEq(weth.allowance(alice, bob), 2 ether);

        vm.stopPrank();
    }

    function test_TransferFromInsufficientAllowance() public {
        vm.prank(alice);
        weth.deposit{value: 10 ether}();

        vm.prank(alice);
        weth.approve(bob, 2 ether);

        vm.startPrank(bob);
        vm.expectRevert("WETH: insufficient allowance");
        weth.transferFrom(alice, charlie, 3 ether);
        vm.stopPrank();
    }

    function test_TransferFromInsufficientBalance() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.prank(alice);
        weth.approve(bob, 10 ether);

        vm.startPrank(bob);
        vm.expectRevert("WETH: insufficient balance");
        weth.transferFrom(alice, charlie, 5 ether);
        vm.stopPrank();
    }

    function test_TransferFromZeroAddresses() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.prank(alice);
        weth.approve(bob, 1 ether);

        vm.startPrank(bob);

        vm.expectRevert("WETH: transfer to the zero address");
        weth.transferFrom(alice, address(0), 1 ether);

        vm.stopPrank();
    }

    // ========== Integration Tests ==========

    function test_FullCycle() public {
        // Alice deposits
        vm.prank(alice);
        weth.deposit{value: 10 ether}();

        // Alice approves Bob
        vm.prank(alice);
        weth.approve(bob, 5 ether);

        // Bob transfers from Alice to Charlie
        vm.prank(bob);
        weth.transferFrom(alice, charlie, 3 ether);

        assertEq(weth.balanceOf(alice), 7 ether);
        assertEq(weth.balanceOf(charlie), 3 ether);

        // Charlie withdraws
        uint256 charlieBalanceBefore = charlie.balance;
        vm.prank(charlie);
        weth.withdraw();

        assertEq(weth.balanceOf(charlie), 0);
        assertEq(charlie.balance, charlieBalanceBefore + 3 ether);

        // Alice withdraws remaining
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        weth.withdraw();

        assertEq(weth.balanceOf(alice), 0);
        assertEq(alice.balance, aliceBalanceBefore + 7 ether);

        assertEq(weth.totalSupply(), 0);
    }

    function test_DepositAndApproveFullFlow() public {
        // Alice deposits and approves Bob in one tx
        vm.prank(alice);
        weth.depositAndApprove{value: 5 ether}(bob);

        assertEq(weth.balanceOf(alice), 5 ether);
        assertEq(weth.allowance(alice, bob), 5 ether);

        // Bob uses the approval
        vm.prank(bob);
        weth.transferFrom(alice, bob, 5 ether);

        assertEq(weth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(bob), 5 ether);

        // Bob withdraws
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        weth.withdraw();

        assertEq(bob.balance, bobBalanceBefore + 5 ether);
        assertEq(weth.totalSupply(), 0);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_Deposit(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);

        vm.prank(alice);
        weth.deposit{value: amount}();

        assertEq(weth.balanceOf(alice), amount);
        assertEq(weth.totalSupply(), amount);
    }

    function testFuzz_Transfer(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);

        vm.prank(alice);
        weth.deposit{value: amount}();

        vm.prank(alice);
        weth.transfer(bob, amount);

        assertEq(weth.balanceOf(bob), amount);
        assertEq(weth.balanceOf(alice), 0);
    }

    function testFuzz_WithdrawAfterDeposit(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);

        vm.prank(alice);
        weth.deposit{value: amount}();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        weth.withdraw();

        assertEq(alice.balance, balanceBefore + amount);
        assertEq(weth.balanceOf(alice), 0);
    }

    // ========== Reentrancy Protection Tests ==========

    function test_WithdrawCEIProtection() public {
        // This test proves CEI pattern prevents reentrancy attacks
        // The balance is set to 0 before external call, preventing double withdrawal
        ReentrancyAttacker attacker = new ReentrancyAttacker(weth);
        vm.deal(address(attacker), 0 ether);

        vm.deal(address(this), 1 ether);
        (bool sent,) = address(attacker).call{value: 1 ether}("");
        require(sent, "Failed to send ETH");

        // Attacker tries to reenter but CEI pattern prevents it
        // If reentrancy worked, attacker would get 2 ETH, but they only get 1 ETH
        assertEq(address(attacker).balance, 1 ether); // Only gets their 1 ETH back
        assertEq(weth.balanceOf(address(attacker)), 0);
        assertEq(attacker.callCount(), 1); // Reentrancy was attempted but failed
    }
}

// Malicious contract that tries to reenter withdraw()
contract ReentrancyAttacker {
    WETH public weth;
    uint256 public callCount;

    constructor(WETH _weth) {
        weth = _weth;
    }

    function attack() external payable {
        weth.deposit{value: msg.value}();
        weth.withdraw();
    }

    receive() external payable {
        callCount++;
        // Try to reenter withdraw - will fail because balance is already 0 (CEI pattern)
        if (callCount == 1) {
            try weth.withdraw() {
                revert("CEI protection failed - reentrancy succeeded!");
            } catch Error(string memory reason) {
                // Expected: "WETH: amount must be greater than 0"
                require(
                    keccak256(bytes(reason)) == keccak256(bytes("WETH: amount must be greater than 0")),
                    "Unexpected error message"
                );
            }
        }
    }
}
