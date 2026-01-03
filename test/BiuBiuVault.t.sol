// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BiuBiuVault} from "../src/core/BiuBiuVault.sol";
import {BiuBiuShare} from "../src/core/BiuBiuShare.sol";

contract BiuBiuVaultTest is Test {
    BiuBiuVault public vault;
    BiuBiuShare public shareToken;

    address public constant FOUNDER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;
    address public alice = address(0x1001);
    address public bob = address(0x1002);
    address public charlie = address(0x1003);

    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public constant DEPOSIT_PERIOD = 7 days;

    event EpochStarted(uint256 indexed epochId, uint256 ethAmount, uint256 startTime);
    event Deposited(uint256 indexed epochId, address indexed user, uint256 amount);
    event Withdrawn(uint256 indexed epochId, address indexed user, uint256 tokenAmount, uint256 ethReward);

    function setUp() public {
        vault = new BiuBiuVault();
        shareToken = vault.shareToken();

        // Distribute tokens from founder to users
        vm.startPrank(FOUNDER);
        shareToken.transfer(alice, 400_000); // 40%
        shareToken.transfer(bob, 300_000); // 30%
        shareToken.transfer(charlie, 200_000); // 20%
        // FOUNDER keeps 100_000 (10%)
        vm.stopPrank();

        // Approve vault
        vm.prank(alice);
        shareToken.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        shareToken.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        shareToken.approve(address(vault), type(uint256).max);
        vm.prank(FOUNDER);
        shareToken.approve(address(vault), type(uint256).max);
    }

    // ========== Token Tests ==========

    function test_TokenDeployed() public view {
        assertEq(shareToken.name(), "BiuBiu Share");
        assertEq(shareToken.symbol(), "BBS");
        assertEq(shareToken.decimals(), 0);
        assertEq(shareToken.totalSupply(), 1_000_000);
    }

    function test_TokenDistribution() public view {
        assertEq(shareToken.balanceOf(alice), 400_000);
        assertEq(shareToken.balanceOf(bob), 300_000);
        assertEq(shareToken.balanceOf(charlie), 200_000);
        assertEq(shareToken.balanceOf(FOUNDER), 100_000);
    }

    // ========== Epoch Management Tests ==========

    function test_StartEpoch() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        assertEq(vault.currentEpoch(), 1);
        assertTrue(vault.isDepositPeriod());

        (uint256 ethAmount, uint256 totalDeposited, bool depositActive, bool withdrawable) = vault.getEpochInfo(1);
        assertEq(ethAmount, 10 ether);
        assertEq(totalDeposited, 0);
        assertTrue(depositActive);
        assertFalse(withdrawable);
    }

    function test_StartEpochRevertsIfNotReady() public {
        vault.startEpoch();

        // Try to start another epoch immediately
        vm.expectRevert(BiuBiuVault.EpochNotReady.selector);
        vault.startEpoch();

        // Still fails after 29 days
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(BiuBiuVault.EpochNotReady.selector);
        vault.startEpoch();

        // Works after 30 days
        vm.warp(block.timestamp + 1 days);
        vault.startEpoch();
        assertEq(vault.currentEpoch(), 2);
    }

    function test_DepositPeriodRemaining() public {
        vault.startEpoch();

        assertEq(vault.depositPeriodRemaining(), DEPOSIT_PERIOD);

        vm.warp(block.timestamp + 3 days);
        assertEq(vault.depositPeriodRemaining(), 4 days);

        vm.warp(block.timestamp + 5 days);
        assertEq(vault.depositPeriodRemaining(), 0);
    }

    function test_TimeUntilNextEpoch() public {
        vault.startEpoch();

        assertEq(vault.timeUntilNextEpoch(), EPOCH_DURATION);

        vm.warp(block.timestamp + 15 days);
        assertEq(vault.timeUntilNextEpoch(), 15 days);

        vm.warp(block.timestamp + 20 days);
        assertEq(vault.timeUntilNextEpoch(), 0);
    }

    // ========== Deposit Tests ==========

    function test_Deposit() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(100_000);

        assertEq(vault.getUserDeposit(1, alice), 100_000);
        assertEq(shareToken.balanceOf(address(vault)), 100_000);

        (, uint256 totalDeposited,,) = vault.getEpochInfo(1);
        assertEq(totalDeposited, 100_000);
    }

    function test_DepositMultipleUsers() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        vm.prank(bob);
        vault.deposit(300_000);

        vm.prank(charlie);
        vault.deposit(200_000);

        (, uint256 totalDeposited,,) = vault.getEpochInfo(1);
        assertEq(totalDeposited, 900_000);
    }

    function test_DepositRevertsNoEpoch() public {
        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.DepositPeriodEnded.selector);
        vault.deposit(100_000);
    }

    function test_DepositRevertsAfterDepositPeriod() public {
        vault.startEpoch();

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.DepositPeriodEnded.selector);
        vault.deposit(100_000);
    }

    function test_DepositRevertsZeroAmount() public {
        vault.startEpoch();

        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    // ========== Withdraw Tests ==========

    function test_Withdraw() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        vm.prank(bob);
        vault.deposit(300_000);

        vm.prank(charlie);
        vault.deposit(200_000);

        // End deposit period
        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Alice withdraws - 400k / 1M total supply = 40%
        vm.prank(alice);
        vault.withdraw(1);

        uint256 expectedReward = (10 ether * uint256(400_000)) / uint256(1_000_000);
        assertEq(alice.balance, expectedReward); // 4 ETH
        assertEq(shareToken.balanceOf(alice), 400_000);
        // Deposit record preserved, but marked as withdrawn
        assertEq(vault.getUserDeposit(1, alice), 400_000);
        assertTrue(vault.withdrawn(1, alice));
        // getPendingReward returns 0 after withdrawal
        assertEq(vault.getPendingReward(1, alice), 0);
    }

    function test_WithdrawAllUsers() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // Each deposits proportionally: 40%, 30%, 20% (based on their balances)
        vm.prank(alice);
        vault.deposit(400_000);

        vm.prank(bob);
        vault.deposit(300_000);

        vm.prank(charlie);
        vault.deposit(200_000);

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Reward based on share of total supply (1M):
        // alice: 400k / 1M = 40% of 10 ETH = 4 ETH
        // bob: 300k / 1M = 30% of 10 ETH = 3 ETH
        // charlie: 200k / 1M = 20% of 10 ETH = 2 ETH
        // Total: 9 ETH distributed, 1 ETH remains (FOUNDER's 10% not deposited)
        vm.prank(alice);
        vault.withdraw(1);
        assertEq(alice.balance, 4 ether);

        vm.prank(bob);
        vault.withdraw(1);
        assertEq(bob.balance, 3 ether);

        vm.prank(charlie);
        vault.withdraw(1);
        assertEq(charlie.balance, 2 ether);

        // 1 ETH remains (10% of supply not deposited)
        assertEq(address(vault).balance, 1 ether);
    }

    function test_WithdrawRevertsDepositPeriodNotEnded() public {
        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(100_000);

        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.DepositPeriodNotEnded.selector);
        vault.withdraw(1);
    }

    function test_WithdrawRevertsNothingToWithdraw() public {
        vault.startEpoch();

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.NothingToWithdraw.selector);
        vault.withdraw(1);
    }

    function test_WithdrawRevertsInvalidEpoch() public {
        vault.startEpoch();

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Epoch 0 is invalid
        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.InvalidEpoch.selector);
        vault.withdraw(0);

        // Epoch 2 doesn't exist yet
        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.InvalidEpoch.selector);
        vault.withdraw(2);
    }

    function test_WithdrawNeverExpires() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        // Wait a very long time (multiple epochs)
        vm.warp(block.timestamp + 365 days);

        // Can still withdraw from epoch 1
        // Alice gets 400k / 1M = 40% of 10 ETH = 4 ETH
        vm.prank(alice);
        vault.withdraw(1);

        assertEq(alice.balance, 4 ether);
        assertEq(shareToken.balanceOf(alice), 400_000);
    }

    // ========== Multiple Epochs Tests ==========

    function test_MultipleEpochs() public {
        vm.deal(address(this), 30 ether);

        // Epoch 1: 10 ETH, Alice deposits 400k (40%)
        // Reserved: 10 * 40% = 4 ETH, Remaining: 6 ETH
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // Epoch 2: 10 ETH new + 6 ETH leftover = 16 ETH, Bob deposits 300k (30%)
        // Reserved: 16 * 30% = 4.8 ETH, Remaining: 11.2 ETH
        (success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(bob);
        vault.deposit(300_000);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // Epoch 3: 10 ETH new + 11.2 ETH leftover = 21.2 ETH, Charlie deposits 200k (20%)
        // Reserved: 21.2 * 20% = 4.24 ETH
        (success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(charlie);
        vault.deposit(200_000);

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Withdraw from all epochs
        // Alice: 400k / 1M = 40% of epoch 1's 10 ETH = 4 ETH
        vm.prank(alice);
        vault.withdraw(1);
        assertEq(alice.balance, 4 ether);

        // Bob: 300k / 1M = 30% of epoch 2's 16 ETH = 4.8 ETH
        vm.prank(bob);
        vault.withdraw(2);
        assertEq(bob.balance, 4.8 ether);

        // Charlie: 200k / 1M = 20% of epoch 3's 21.2 ETH = 4.24 ETH
        vm.prank(charlie);
        vault.withdraw(3);
        assertEq(charlie.balance, 4.24 ether);
    }

    // ========== View Functions Tests ==========

    function test_GetPendingReward() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        vm.prank(bob);
        vault.deposit(100_000);

        // Reward based on share of total supply (1M):
        // alice: 400k / 1M = 40% of 10 ETH = 4 ETH
        // bob: 100k / 1M = 10% of 10 ETH = 1 ETH
        assertEq(vault.getPendingReward(1, alice), 4 ether);
        assertEq(vault.getPendingReward(1, bob), 1 ether);
        assertEq(vault.getPendingReward(1, charlie), 0);
    }

    // ========== Edge Cases ==========

    function test_NoDepositsRollover() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // No one deposits, epoch ends
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Start new epoch - epoch 1 had no deposits so its ETH is recycled to epoch 2
        vault.startEpoch();

        // Epoch 2 gets all 10 ETH (recycled from epoch 1)
        (uint256 ethAmount,,,) = vault.getEpochInfo(2);
        assertEq(ethAmount, 10 ether);

        // Epoch 1's ethAmount remains as historical record, but no ETH was reserved
        (uint256 epoch1Eth,,,) = vault.getEpochInfo(1);
        assertEq(epoch1Eth, 10 ether); // Historical record preserved
        assertEq(vault.totalReserved(), 0); // But nothing was reserved
    }

    function test_PartialDeposit() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // Only Alice deposits 100k (10% of supply)
        vm.prank(alice);
        vault.deposit(100_000);

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Alice gets 100k / 1M = 10% of 10 ETH = 1 ETH
        vm.prank(alice);
        vault.withdraw(1);
        assertEq(alice.balance, 1 ether);
    }

    function test_ReceiveETH() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);
        assertEq(address(vault).balance, 10 ether);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_DepositAndWithdraw(uint96 depositAmount) public {
        vm.assume(depositAmount >= 1);
        vm.assume(depositAmount <= 400_000);

        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(depositAmount);

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        vm.prank(alice);
        vault.withdraw(1);

        // Alice gets reward based on deposited share of total supply
        uint256 expectedReward = (10 ether * uint256(depositAmount)) / uint256(1_000_000);
        assertEq(alice.balance, expectedReward);
        assertEq(shareToken.balanceOf(alice), 400_000);
    }

    // ========== Additional Coverage Tests ==========

    function test_WithdrawRevertsDoubleWithdraw() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(100_000);

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // First withdraw succeeds
        vm.prank(alice);
        vault.withdraw(1);

        // Second withdraw fails
        vm.prank(alice);
        vm.expectRevert(BiuBiuVault.NothingToWithdraw.selector);
        vault.withdraw(1);
    }

    function test_WithdrawETHTransferFails() public {
        // Deploy a contract that rejects ETH
        RejectETH rejecter = new RejectETH();

        // Give rejecter some tokens
        vm.prank(FOUNDER);
        shareToken.transfer(address(rejecter), 100_000);

        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // Rejecter deposits
        vm.startPrank(address(rejecter));
        shareToken.approve(address(vault), type(uint256).max);
        vault.deposit(100_000);
        vm.stopPrank();

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Withdraw fails because rejecter can't receive ETH
        vm.prank(address(rejecter));
        vm.expectRevert(BiuBiuVault.TransferFailed.selector);
        vault.withdraw(1);
    }

    function test_ReentrancyProtection() public {
        // Deploy reentrancy attacker
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);

        // Give attacker some tokens
        vm.prank(FOUNDER);
        shareToken.transfer(address(attacker), 100_000);

        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // Attacker deposits
        vm.startPrank(address(attacker));
        shareToken.approve(address(vault), type(uint256).max);
        vault.deposit(100_000);
        vm.stopPrank();

        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        // Attacker tries to reenter - reentrancy guard catches it
        // The attacker's receive() tries to call withdraw again, which triggers ReentrancyGuard
        // But since this happens inside the first withdraw call, the whole tx reverts with TransferFailed
        // (because the inner revert causes the ETH transfer to fail)
        vm.prank(address(attacker));
        vm.expectRevert(BiuBiuVault.TransferFailed.selector);
        vault.withdraw(1);

        // Verify attacker didn't steal any ETH
        assertEq(address(attacker).balance, 0);
        // Verify vault still has all ETH
        assertEq(address(vault).balance, 10 ether);
    }

    function test_DepositMultipleTimes() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);

        vault.startEpoch();

        // Alice deposits twice
        vm.startPrank(alice);
        vault.deposit(100_000);
        vault.deposit(200_000);
        vm.stopPrank();

        assertEq(vault.getUserDeposit(1, alice), 300_000);
        (, uint256 totalDeposited,,) = vault.getEpochInfo(1);
        assertEq(totalDeposited, 300_000);
    }

    function test_WithdrawFromPastEpoch() public {
        vm.deal(address(this), 20 ether);

        // Epoch 1
        (bool success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);
        vault.startEpoch();

        vm.prank(alice);
        vault.deposit(400_000);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // Epoch 2
        (success,) = address(vault).call{value: 10 ether}("");
        assertTrue(success);
        vault.startEpoch();

        // Withdraw from epoch 1 while in epoch 2
        vm.prank(alice);
        vault.withdraw(1);

        assertEq(alice.balance, 4 ether); // 400k / 1M * 10 ETH
    }

    function test_GetEpochInfoBeforeAnyEpoch() public view {
        // Epoch 0 doesn't exist, so ethAmount and totalDeposited are 0
        // withdrawable is true because epochId (0) <= currentEpoch (0) && !isCurrentDepositPeriod
        // This is expected behavior - epoch 0 is technically "withdrawable" but has no deposits
        (uint256 ethAmount, uint256 totalDeposited, bool depositActive, bool withdrawable) = vault.getEpochInfo(0);
        assertEq(ethAmount, 0);
        assertEq(totalDeposited, 0);
        assertFalse(depositActive);
        // Note: withdrawable is true for epoch 0 because the condition is epochId <= currentEpoch
        // This is fine because trying to withdraw from epoch 0 will revert with InvalidEpoch
        assertTrue(withdrawable);
    }

    function test_IsDepositPeriodBeforeAnyEpoch() public view {
        assertFalse(vault.isDepositPeriod());
    }

    function test_TimeUntilNextEpochBeforeAnyEpoch() public view {
        assertEq(vault.timeUntilNextEpoch(), 0);
    }

    function test_DepositPeriodRemainingAfterPeriodEnds() public {
        vault.startEpoch();
        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);
        assertEq(vault.depositPeriodRemaining(), 0);
    }
}

// Helper contract that rejects ETH
contract RejectETH {
    receive() external payable {
        revert("No ETH");
    }
}

// Helper contract for reentrancy attack
contract ReentrancyAttacker {
    BiuBiuVault public vault;
    bool public attacking;

    constructor(BiuBiuVault _vault) {
        vault = _vault;
    }

    receive() external payable {
        if (!attacking) {
            attacking = true;
            vault.withdraw(1); // Try to reenter
        }
    }
}
