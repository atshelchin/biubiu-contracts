// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BiuBiuShare} from "../src/core/BiuBiuShare.sol";

contract BiuBiuShareTest is Test {
    BiuBiuShare public token;

    address public constant FOUNDER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;
    address public alice = address(0x1001);
    address public bob = address(0x1002);

    function setUp() public {
        token = new BiuBiuShare();
    }

    // ========== Deployment Tests ==========

    function test_Name() public view {
        assertEq(token.name(), "BiuBiu Share");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "BBS");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 0);
    }

    function test_TotalSupply() public view {
        assertEq(token.totalSupply(), 1_000_000);
    }

    function test_FounderAddress() public view {
        assertEq(token.FOUNDER(), FOUNDER);
    }

    function test_InitialBalance() public view {
        assertEq(token.balanceOf(FOUNDER), 1_000_000);
    }

    // ========== Transfer Tests ==========

    function test_Transfer() public {
        vm.prank(FOUNDER);
        bool success = token.transfer(alice, 100_000);

        assertTrue(success);
        assertEq(token.balanceOf(FOUNDER), 900_000);
        assertEq(token.balanceOf(alice), 100_000);
    }

    function test_TransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit BiuBiuShare.Transfer(FOUNDER, alice, 100_000);

        vm.prank(FOUNDER);
        token.transfer(alice, 100_000);
    }

    function test_TransferRevertsZeroAddress() public {
        vm.prank(FOUNDER);
        vm.expectRevert(BiuBiuShare.ZeroAddress.selector);
        token.transfer(address(0), 100_000);
    }

    function test_TransferRevertsInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(BiuBiuShare.InsufficientBalance.selector);
        token.transfer(bob, 1);
    }

    function test_TransferFullBalance() public {
        vm.prank(FOUNDER);
        token.transfer(alice, 1_000_000);

        assertEq(token.balanceOf(FOUNDER), 0);
        assertEq(token.balanceOf(alice), 1_000_000);
    }

    // ========== Approve Tests ==========

    function test_Approve() public {
        vm.prank(FOUNDER);
        bool success = token.approve(alice, 100_000);

        assertTrue(success);
        assertEq(token.allowance(FOUNDER, alice), 100_000);
    }

    function test_ApproveEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit BiuBiuShare.Approval(FOUNDER, alice, 100_000);

        vm.prank(FOUNDER);
        token.approve(alice, 100_000);
    }

    function test_ApproveMaxUint() public {
        vm.prank(FOUNDER);
        token.approve(alice, type(uint256).max);

        assertEq(token.allowance(FOUNDER, alice), type(uint256).max);
    }

    function test_ApproveOverwrite() public {
        vm.startPrank(FOUNDER);
        token.approve(alice, 100_000);
        token.approve(alice, 50_000);
        vm.stopPrank();

        assertEq(token.allowance(FOUNDER, alice), 50_000);
    }

    // ========== TransferFrom Tests ==========

    function test_TransferFrom() public {
        vm.prank(FOUNDER);
        token.approve(alice, 100_000);

        vm.prank(alice);
        bool success = token.transferFrom(FOUNDER, bob, 50_000);

        assertTrue(success);
        assertEq(token.balanceOf(FOUNDER), 950_000);
        assertEq(token.balanceOf(bob), 50_000);
        assertEq(token.allowance(FOUNDER, alice), 50_000);
    }

    function test_TransferFromEmitsEvent() public {
        vm.prank(FOUNDER);
        token.approve(alice, 100_000);

        vm.expectEmit(true, true, false, true);
        emit BiuBiuShare.Transfer(FOUNDER, bob, 50_000);

        vm.prank(alice);
        token.transferFrom(FOUNDER, bob, 50_000);
    }

    function test_TransferFromMaxAllowance() public {
        vm.prank(FOUNDER);
        token.approve(alice, type(uint256).max);

        vm.prank(alice);
        token.transferFrom(FOUNDER, bob, 100_000);

        // Max allowance should not decrease
        assertEq(token.allowance(FOUNDER, alice), type(uint256).max);
    }

    function test_TransferFromRevertsZeroAddress() public {
        vm.prank(FOUNDER);
        token.approve(alice, 100_000);

        vm.prank(alice);
        vm.expectRevert(BiuBiuShare.ZeroAddress.selector);
        token.transferFrom(FOUNDER, address(0), 50_000);
    }

    function test_TransferFromRevertsInsufficientBalance() public {
        // Give alice some tokens
        vm.prank(FOUNDER);
        token.transfer(alice, 100);

        // Alice approves bob
        vm.prank(alice);
        token.approve(bob, 200);

        // Bob tries to transfer more than alice has
        vm.prank(bob);
        vm.expectRevert(BiuBiuShare.InsufficientBalance.selector);
        token.transferFrom(alice, bob, 200);
    }

    function test_TransferFromRevertsInsufficientAllowance() public {
        vm.prank(FOUNDER);
        token.approve(alice, 50_000);

        vm.prank(alice);
        vm.expectRevert(BiuBiuShare.InsufficientAllowance.selector);
        token.transferFrom(FOUNDER, bob, 100_000);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_Transfer(uint256 amount) public {
        vm.assume(amount <= 1_000_000);

        vm.prank(FOUNDER);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(FOUNDER), 1_000_000 - amount);
    }

    function testFuzz_Approve(uint256 amount) public {
        vm.prank(FOUNDER);
        token.approve(alice, amount);

        assertEq(token.allowance(FOUNDER, alice), amount);
    }

    function testFuzz_TransferFrom(uint256 approveAmount, uint256 transferAmount) public {
        vm.assume(approveAmount <= 1_000_000);
        vm.assume(transferAmount <= approveAmount);

        vm.prank(FOUNDER);
        token.approve(alice, approveAmount);

        vm.prank(alice);
        token.transferFrom(FOUNDER, bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        if (approveAmount != type(uint256).max) {
            assertEq(token.allowance(FOUNDER, alice), approveAmount - transferAmount);
        }
    }
}
