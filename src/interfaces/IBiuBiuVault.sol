// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BiuBiuShare} from "../core/BiuBiuShare.sol";

/**
 * @title IBiuBiuVault
 * @notice Interface for BiuBiuVault epoch-based revenue distribution
 * @dev Stable API for frontend and other contracts to interact with BiuBiuVault
 */
interface IBiuBiuVault {
    // ============ Events ============

    event EpochStarted(uint256 indexed epochId, uint256 ethAmount, uint256 startTime);
    event Deposited(uint256 indexed epochId, address indexed user, uint256 amount);
    event Withdrawn(uint256 indexed epochId, address indexed user, uint256 tokenAmount, uint256 ethReward);
    event ETHReceived(address indexed from, uint256 amount);

    // ============ Constants ============

    function EPOCH_DURATION() external view returns (uint256);
    function DEPOSIT_PERIOD() external view returns (uint256);

    // ============ State Variables ============

    function shareToken() external view returns (BiuBiuShare);
    function currentEpoch() external view returns (uint256);
    function epochStartTime() external view returns (uint256);
    function totalReserved() external view returns (uint256);

    // ============ Epoch Management ============

    function startEpoch() external;
    function isDepositPeriod() external view returns (bool);
    function depositPeriodRemaining() external view returns (uint256);
    function timeUntilNextEpoch() external view returns (uint256);

    // ============ User Actions ============

    function deposit(uint256 amount) external;
    function withdraw(uint256 epochId) external;

    // ============ View Functions ============

    function epochs(uint256 epochId)
        external
        view
        returns (uint256 ethAmount, uint256 ethRemaining, uint256 totalDeposited);

    function deposits(uint256 epochId, address user) external view returns (uint256);
    function withdrawn(uint256 epochId, address user) external view returns (bool);
    function getUserDeposit(uint256 epochId, address user) external view returns (uint256);
    function getPendingReward(uint256 epochId, address user) external view returns (uint256);

    function getEpochInfo(uint256 epochId)
        external
        view
        returns (uint256 ethAmount, uint256 totalDeposited, bool depositActive, bool withdrawable);
}
