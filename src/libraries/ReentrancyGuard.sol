// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyGuard
 * @notice Abstract contract that provides reentrancy protection
 * @dev Inherit this contract and use the `nonReentrant` modifier on functions
 *      that should not be called recursively.
 */
abstract contract ReentrancyGuard {
    error ReentrancyDetected();

    uint256 private _locked = 1;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
        _;
        _locked = 1;
    }
}
