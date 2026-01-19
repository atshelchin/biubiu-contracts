// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "../../src/libraries/ReentrancyGuard.sol";

/**
 * @title MockReentrancyGuard
 * @notice Concrete implementation of ReentrancyGuard for testing
 */
contract MockReentrancyGuard is ReentrancyGuard {
    uint256 public counter;

    function increment() external nonReentrant {
        counter += 1;
    }

    function incrementWithCallback(address target) external nonReentrant {
        counter += 1;
        (bool success,) = target.call("");
        require(success, "Callback failed");
    }

    function incrementTwice() external nonReentrant {
        counter += 1;
        this.increment();
    }

    function nonProtectedIncrement() external {
        counter += 1;
    }
}

/**
 * @title ReentrantAttacker
 * @notice Contract that attempts reentrancy attack
 */
contract ReentrantAttacker {
    MockReentrancyGuard public target;
    bool public attackSucceeded;

    constructor(MockReentrancyGuard _target) {
        target = _target;
    }

    receive() external payable {
        try target.increment() {
            attackSucceeded = true;
        } catch {
            attackSucceeded = false;
        }
    }

    fallback() external payable {
        try target.increment() {
            attackSucceeded = true;
        } catch {
            attackSucceeded = false;
        }
    }

    function attack() external {
        target.incrementWithCallback(address(this));
    }
}

/**
 * @title ReentrancyGuardTest
 * @notice Tests for ReentrancyGuard abstract contract
 */
contract ReentrancyGuardTest is Test {
    MockReentrancyGuard public guard;
    ReentrantAttacker public attacker;

    function setUp() public {
        guard = new MockReentrancyGuard();
        attacker = new ReentrantAttacker(guard);
    }

    // ============ Basic Functionality Tests ============

    function test_nonReentrant_allowsSingleCall() public {
        guard.increment();
        assertEq(guard.counter(), 1);
    }

    function test_nonReentrant_allowsMultipleSequentialCalls() public {
        guard.increment();
        guard.increment();
        guard.increment();
        assertEq(guard.counter(), 3);
    }

    function test_nonReentrant_stateResetAfterCall() public {
        guard.increment();
        assertEq(guard.counter(), 1);

        // Should work again after first call completes
        guard.increment();
        assertEq(guard.counter(), 2);
    }

    // ============ Reentrancy Prevention Tests ============

    function test_nonReentrant_preventsDirectReentrancy() public {
        vm.expectRevert(ReentrancyGuard.ReentrancyDetected.selector);
        guard.incrementTwice();
    }

    function test_nonReentrant_preventsCallbackReentrancy() public {
        // Attacker's callback tries to reenter but fails
        // The outer call succeeds, callback reentrancy is blocked
        attacker.attack();

        // Attack did not succeed - reentrancy was blocked
        assertFalse(attacker.attackSucceeded());
        // Counter is 1 because first increment succeeded, reentrant call was blocked
        assertEq(guard.counter(), 1);
    }

    function test_nonReentrant_attackerCannotReenter() public {
        attacker.attack();

        // The attack was blocked
        assertFalse(attacker.attackSucceeded());
        // Only the legitimate first increment went through
        assertEq(guard.counter(), 1);
    }

    // ============ Non-Protected Function Tests ============

    function test_nonProtectedFunction_canBeCalledAnytime() public {
        guard.nonProtectedIncrement();
        guard.nonProtectedIncrement();
        assertEq(guard.counter(), 2);
    }

    // ============ Cross-Function Tests ============

    function test_nonReentrant_blocksCrossFunctionReentrancy() public {
        // incrementWithCallback tries to call increment during execution via callback
        attacker.attack();

        // Reentrancy was blocked
        assertFalse(attacker.attackSucceeded());
        assertEq(guard.counter(), 1);
    }

    // ============ Edge Case Tests ============

    function test_nonReentrant_worksWithDifferentCallers() public {
        address user1 = address(0x1);
        address user2 = address(0x2);

        vm.prank(user1);
        guard.increment();

        vm.prank(user2);
        guard.increment();

        assertEq(guard.counter(), 2);
    }

    function test_nonReentrant_worksAfterRevertedCall() public {
        // First call should revert due to reentrancy
        vm.expectRevert(ReentrancyGuard.ReentrancyDetected.selector);
        guard.incrementTwice();

        // Lock should be reset, so this should work
        guard.increment();
        assertEq(guard.counter(), 1);
    }
}
