// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BiuBiuShare} from "./BiuBiuShare.sol";

/**
 * @title BiuBiuVault
 * @notice Epoch-based revenue distribution vault
 * @dev Deploys BiuBiuShare token. Users deposit tokens during deposit period,
 *      withdraw tokens + rewards after deposit period ends.
 *
 * Timeline per epoch:
 * - Day 0: startEpoch() can be called (every 30 days)
 * - Day 0-7: Deposit period - users deposit DAO tokens
 * - Day 7+: Withdraw period - users withdraw tokens + ETH rewards (never expires)
 *
 * No admin, fully permissionless
 */
contract BiuBiuVault {
    // ============ Constants ============

    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public constant DEPOSIT_PERIOD = 7 days;

    // ============ Immutables ============

    BiuBiuShare public immutable shareToken;
    uint256 private immutable _totalSupply;

    // ============ Reentrancy Guard ============

    uint256 private _locked = 1;

    // ============ Epoch State ============

    uint256 public currentEpoch;
    uint256 public epochStartTime;
    uint256 public totalReserved; // Total ETH reserved for epochs with deposits (sum of all epoch.ethRemaining)

    struct Epoch {
        uint256 ethAmount; // ETH allocated to this epoch for reward calculation
        uint256 ethRemaining; // ETH remaining to be claimed (decreases as users withdraw)
        uint256 totalDeposited; // Total tokens deposited
    }

    mapping(uint256 => Epoch) public epochs;

    // ============ User State ============

    // epochId => user => deposited amount
    mapping(uint256 => mapping(address => uint256)) public deposits;
    // epochId => user => whether user has withdrawn
    mapping(uint256 => mapping(address => bool)) public withdrawn;

    // ============ Events ============

    event EpochStarted(uint256 indexed epochId, uint256 ethAmount, uint256 startTime);
    event Deposited(uint256 indexed epochId, address indexed user, uint256 amount);
    event Withdrawn(uint256 indexed epochId, address indexed user, uint256 tokenAmount, uint256 ethReward);
    event ETHReceived(address indexed from, uint256 amount);

    // ============ Errors ============

    error EpochNotReady();
    error DepositPeriodEnded();
    error DepositPeriodNotEnded();
    error NothingToWithdraw();
    error TransferFailed();
    error ZeroAmount();
    error InvalidEpoch();
    error ReentrancyGuard();

    // ============ Modifiers ============

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyGuard();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ============ Constructor ============

    constructor() {
        shareToken = new BiuBiuShare();
        _totalSupply = shareToken.totalSupply();
    }

    // ============ Receive ETH ============

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    // ============ Epoch Management ============

    /**
     * @notice Start a new epoch
     * @dev Anyone can call after 30 days since last epoch. Takes available vault balance as rewards.
     */
    function startEpoch() external {
        // Must wait 30 days since last epoch started
        if (epochStartTime > 0 && block.timestamp < epochStartTime + EPOCH_DURATION) {
            revert EpochNotReady();
        }

        // Finalize previous epoch if needed (reserve ETH if deposits exist, or recycle if none)
        if (currentEpoch > 0) {
            _finalizeEpochIfNeeded(currentEpoch);
        }

        unchecked {
            currentEpoch++;
        }
        epochStartTime = block.timestamp;

        // Only unreserved ETH goes to this epoch
        uint256 ethAmount = address(this).balance - totalReserved;
        epochs[currentEpoch].ethAmount = ethAmount;
        // ethRemaining starts at 0, will be set when deposit period ends (first withdraw or next epoch)

        emit EpochStarted(currentEpoch, ethAmount, block.timestamp);
    }

    /**
     * @notice Finalize an epoch after deposit period ends
     * @dev Called internally. If no deposits, ETH stays available for next epoch.
     *      If deposits exist, reserve only the ETH that will be claimed based on deposited share.
     */
    function _finalizeEpochIfNeeded(uint256 epochId) internal {
        Epoch storage e = epochs[epochId];

        // Already finalized or no ETH to finalize or no deposits
        if (e.ethRemaining > 0 || e.ethAmount == 0 || e.totalDeposited == 0) return;

        // Reserve only the portion that will be claimed (proportional to deposited share of total supply)
        uint256 reserved = (e.ethAmount * e.totalDeposited) / _totalSupply;
        e.ethRemaining = reserved;
        totalReserved += reserved;
    }

    /**
     * @notice Check if currently in deposit period
     */
    function isDepositPeriod() public view returns (bool) {
        if (epochStartTime == 0) return false;
        return block.timestamp < epochStartTime + DEPOSIT_PERIOD;
    }

    /**
     * @notice Get time remaining in current deposit period
     */
    function depositPeriodRemaining() external view returns (uint256) {
        if (!isDepositPeriod()) return 0;
        return (epochStartTime + DEPOSIT_PERIOD) - block.timestamp;
    }

    /**
     * @notice Get time until next epoch can start
     */
    function timeUntilNextEpoch() external view returns (uint256) {
        if (epochStartTime == 0) return 0;
        uint256 nextEpochTime = epochStartTime + EPOCH_DURATION;
        if (block.timestamp >= nextEpochTime) return 0;
        return nextEpochTime - block.timestamp;
    }

    // ============ User Actions ============

    /**
     * @notice Deposit tokens to participate in current epoch
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (!isDepositPeriod()) revert DepositPeriodEnded();

        shareToken.transferFrom(msg.sender, address(this), amount);

        unchecked {
            deposits[currentEpoch][msg.sender] += amount;
            epochs[currentEpoch].totalDeposited += amount;
        }

        emit Deposited(currentEpoch, msg.sender, amount);
    }

    /**
     * @notice Withdraw tokens and claim rewards from a completed epoch
     * @param epochId The epoch to withdraw from
     */
    function withdraw(uint256 epochId) external nonReentrant {
        // Validate epoch
        if (epochId == 0 || epochId > currentEpoch) revert InvalidEpoch();

        // Deposit period must have ended
        if (epochId == currentEpoch && isDepositPeriod()) {
            revert DepositPeriodNotEnded();
        }

        // Check if already withdrawn
        if (withdrawn[epochId][msg.sender]) revert NothingToWithdraw();

        uint256 deposited = deposits[epochId][msg.sender];
        if (deposited == 0) revert NothingToWithdraw();

        // Finalize epoch if needed (first withdraw triggers this)
        _finalizeEpochIfNeeded(epochId);

        // Mark as withdrawn (preserves deposit record)
        withdrawn[epochId][msg.sender] = true;

        // Cache storage reads
        Epoch storage e = epochs[epochId];
        uint256 epochEth = e.ethAmount;

        // Calculate reward based on deposited share of total supply
        uint256 reward = (epochEth * deposited) / _totalSupply;

        // Return tokens
        shareToken.transfer(msg.sender, deposited);

        // Send ETH reward
        if (reward > 0) {
            e.ethRemaining -= reward;
            totalReserved -= reward;
            (bool success,) = msg.sender.call{value: reward}("");
            if (!success) revert TransferFailed();
        }

        emit Withdrawn(epochId, msg.sender, deposited, reward);
    }

    // ============ View Functions ============

    /**
     * @notice Get user's deposit for an epoch
     */
    function getUserDeposit(uint256 epochId, address user) external view returns (uint256) {
        return deposits[epochId][user];
    }

    /**
     * @notice Get user's pending reward for an epoch (0 if already withdrawn)
     */
    function getPendingReward(uint256 epochId, address user) external view returns (uint256) {
        if (withdrawn[epochId][user]) return 0;

        uint256 deposited = deposits[epochId][user];
        if (deposited == 0) return 0;

        Epoch storage e = epochs[epochId];
        return (e.ethAmount * deposited) / _totalSupply;
    }

    /**
     * @notice Get epoch info
     */
    function getEpochInfo(uint256 epochId)
        external
        view
        returns (uint256 ethAmount, uint256 totalDeposited, bool depositActive, bool withdrawable)
    {
        Epoch storage e = epochs[epochId];
        bool isCurrentDepositPeriod = epochId == currentEpoch && isDepositPeriod();
        return
            (e.ethAmount, e.totalDeposited, isCurrentDepositPeriod, epochId <= currentEpoch && !isCurrentDepositPeriod);
    }
}
