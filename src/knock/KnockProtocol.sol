// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IKnockProtocol} from "./interfaces/IKnockProtocol.sol";
import {IKnockCard} from "./interfaces/IKnockCard.sol";

/// @title KnockProtocol - On-chain Attention Market
/// @notice Allows users to send paid messages (knocks) to any address
/// @dev Daily settlement selects top N knocks by bid for each receiver
contract KnockProtocol is IKnockProtocol {
    // ============ Constants ============

    uint256 public constant MIN_BID = 0.01 ether;
    uint256 public constant MAX_PENDING_KNOCKS = 3;
    uint256 public constant EXPIRE_DAYS = 7;
    uint256 public constant DEFAULT_DAILY_SLOTS = 10;

    // Fee distribution (basis points, 100 = 1%)
    uint256 public constant ACCEPTED_SENDER_SHARE = 4000;      // 40%
    uint256 public constant ACCEPTED_RECEIVER_SHARE = 4000;    // 40%
    uint256 public constant ACCEPTED_PROTOCOL_SHARE = 2000;    // 20%

    uint256 public constant REJECTED_RECEIVER_SHARE = 8000;    // 80%
    uint256 public constant REJECTED_PROTOCOL_SHARE = 2000;    // 20%

    // ============ State ============

    IKnockCard public immutable knockCard;
    address public owner;
    address public protocolFeeReceiver;

    uint256 public nextKnockId = 1;

    // knockId => Knock
    mapping(uint256 => Knock) public knocks;

    // sender => pending knockIds
    mapping(address => uint256[]) private _senderPendingKnocks;

    // receiver => day => pending knockIds (for settlement)
    mapping(address => mapping(uint256 => uint256[])) private _receiverDayKnocks;

    // receiver => settled knockIds (waiting for processing)
    mapping(address => uint256[]) private _receiverSettledKnocks;

    // receiver => settings
    mapping(address => ReceiverSettings) private _receiverSettings;

    // receiver => stats
    mapping(address => ReceiverStats) private _receiverStats;

    // receiver => day => settled flag
    mapping(address => mapping(uint256 => bool)) private _daySettled;

    // ============ Constructor ============

    constructor(address _knockCard, address _protocolFeeReceiver) {
        knockCard = IKnockCard(_knockCard);
        owner = msg.sender;
        protocolFeeReceiver = _protocolFeeReceiver;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ============ Core Functions ============

    /// @notice Send a knock to a receiver
    /// @param receiver The address to knock
    /// @param contentId The PDF content ID from official platform
    /// @return knockId The ID of the created knock
    function knock(address receiver, bytes32 contentId) external payable returns (uint256 knockId) {
        // Checks
        if (!knockCard.hasCard(msg.sender)) revert NoCard();
        if (receiver == msg.sender) revert CannotKnockSelf();
        if (msg.value < MIN_BID) revert BidTooLow();
        if (_countActivePending(msg.sender) >= MAX_PENDING_KNOCKS) revert TooManyPendingKnocks();

        // Create knock
        knockId = nextKnockId++;
        uint256 today = getCurrentDay();

        knocks[knockId] = Knock({
            id: knockId,
            sender: msg.sender,
            receiver: receiver,
            bid: msg.value,
            contentId: contentId,
            createdAt: block.timestamp,
            settleDay: today,
            status: KnockStatus.Pending
        });

        // Track pending knocks
        _senderPendingKnocks[msg.sender].push(knockId);
        _receiverDayKnocks[receiver][today].push(knockId);

        // Update stats
        knockCard.incrementKnocksSent(msg.sender);
        _receiverStats[receiver].totalReceived++;
        _receiverStats[receiver].totalEthReceived += msg.value;

        emit KnockSent(knockId, msg.sender, receiver, msg.value, contentId);
    }

    /// @notice Settle knocks for a receiver for a specific day
    /// @param receiver The receiver address to settle
    function settle(address receiver) external {
        uint256 yesterday = getCurrentDay() - 1;
        if (_daySettled[receiver][yesterday]) revert AlreadySettled();

        uint256[] storage dayKnocks = _receiverDayKnocks[receiver][yesterday];
        if (dayKnocks.length == 0) {
            _daySettled[receiver][yesterday] = true;
            return;
        }

        uint256 slots = _getSlots(receiver);

        // Sort by bid (descending) - simple bubble sort for small arrays
        _sortByBidDesc(dayKnocks);

        // Select top N
        uint256 selectCount = dayKnocks.length < slots ? dayKnocks.length : slots;

        for (uint256 i = 0; i < dayKnocks.length; i++) {
            uint256 knockId = dayKnocks[i];
            Knock storage k = knocks[knockId];

            if (k.status != KnockStatus.Pending) continue;

            if (i < selectCount) {
                // Selected - move to settled
                k.status = KnockStatus.Settled;
                _receiverSettledKnocks[receiver].push(knockId);
                emit KnockSettled(knockId, true);
            } else {
                // Not selected - refund 100%
                k.status = KnockStatus.Refunded;
                _refund(k.sender, k.bid);
                emit KnockSettled(knockId, false);
                emit KnockRefunded(knockId, k.sender, k.bid);
            }

            // Remove from sender pending
            _removePending(k.sender, knockId);
        }

        _daySettled[receiver][yesterday] = true;
    }

    /// @notice Accept a knock
    /// @param knockId The knock ID to accept
    function accept(uint256 knockId) external {
        Knock storage k = knocks[knockId];
        if (k.id == 0) revert KnockNotFound();
        if (k.receiver != msg.sender) revert NotReceiver();
        if (k.status != KnockStatus.Settled) revert InvalidStatus();

        k.status = KnockStatus.Accepted;

        // Distribution: Sender 40%, Receiver 40%, Protocol 20%
        uint256 senderShare = (k.bid * ACCEPTED_SENDER_SHARE) / 10000;
        uint256 receiverShare = (k.bid * ACCEPTED_RECEIVER_SHARE) / 10000;
        uint256 protocolShare = k.bid - senderShare - receiverShare;

        _refund(k.sender, senderShare);
        _refund(k.receiver, receiverShare);
        _refund(protocolFeeReceiver, protocolShare);

        // Update stats
        knockCard.incrementKnocksAccepted(k.sender);
        _receiverStats[k.receiver].accepted++;

        // Remove from settled list
        _removeSettled(k.receiver, knockId);

        emit KnockAccepted(knockId, msg.sender);
    }

    /// @notice Reject a knock
    /// @param knockId The knock ID to reject
    function reject(uint256 knockId) external {
        Knock storage k = knocks[knockId];
        if (k.id == 0) revert KnockNotFound();
        if (k.receiver != msg.sender) revert NotReceiver();
        if (k.status != KnockStatus.Settled) revert InvalidStatus();

        k.status = KnockStatus.Rejected;

        // Distribution: Receiver 80%, Protocol 20%
        uint256 receiverShare = (k.bid * REJECTED_RECEIVER_SHARE) / 10000;
        uint256 protocolShare = k.bid - receiverShare;

        _refund(k.receiver, receiverShare);
        _refund(protocolFeeReceiver, protocolShare);

        // Update stats
        knockCard.incrementKnocksRejected(k.sender);
        _receiverStats[k.receiver].rejected++;

        // Remove from settled list
        _removeSettled(k.receiver, knockId);

        emit KnockRejected(knockId, msg.sender);
    }

    /// @notice Claim expired knock (sender gets 100% refund)
    /// @param knockId The knock ID to claim
    function claimExpired(uint256 knockId) external {
        Knock storage k = knocks[knockId];
        if (k.id == 0) revert KnockNotFound();
        if (k.status != KnockStatus.Settled) revert InvalidStatus();

        uint256 expireTime = k.createdAt + (EXPIRE_DAYS * 1 days);
        if (block.timestamp < expireTime) revert NotExpired();

        k.status = KnockStatus.Expired;

        // Sender gets 100% refund
        _refund(k.sender, k.bid);

        // Remove from settled list
        _removeSettled(k.receiver, knockId);

        emit KnockExpired(knockId);
        emit KnockRefunded(knockId, k.sender, k.bid);
    }

    // ============ Settings ============

    /// @notice Set daily slots for receiving knocks
    /// @param slots Number of slots (1-100)
    function setDailySlots(uint256 slots) external {
        require(slots >= 1 && slots <= 100, "Invalid slots");
        _receiverSettings[msg.sender].dailySlots = slots;
        _receiverSettings[msg.sender].isConfigured = true;
        emit SettingsUpdated(msg.sender, slots);
    }

    // ============ View Functions ============

    function getKnock(uint256 knockId) external view returns (Knock memory) {
        return knocks[knockId];
    }

    function getPendingKnocks(address sender) external view returns (uint256[] memory) {
        return _senderPendingKnocks[sender];
    }

    function getSettledKnocks(address receiver) external view returns (uint256[] memory) {
        return _receiverSettledKnocks[receiver];
    }

    function getReceiverSettings(address receiver) external view returns (ReceiverSettings memory) {
        ReceiverSettings memory settings = _receiverSettings[receiver];
        if (!settings.isConfigured) {
            settings.dailySlots = DEFAULT_DAILY_SLOTS;
        }
        return settings;
    }

    function getReceiverStats(address receiver) external view returns (ReceiverStats memory) {
        return _receiverStats[receiver];
    }

    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function getDayKnocks(address receiver, uint256 day) external view returns (uint256[] memory) {
        return _receiverDayKnocks[receiver][day];
    }

    function isDaySettled(address receiver, uint256 day) external view returns (bool) {
        return _daySettled[receiver][day];
    }

    // ============ Admin Functions ============

    function setProtocolFeeReceiver(address _receiver) external onlyOwner {
        protocolFeeReceiver = _receiver;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ============ Internal Functions ============

    function _getSlots(address receiver) internal view returns (uint256) {
        ReceiverSettings storage settings = _receiverSettings[receiver];
        return settings.isConfigured ? settings.dailySlots : DEFAULT_DAILY_SLOTS;
    }

    function _countActivePending(address sender) internal view returns (uint256 count) {
        uint256[] storage pending = _senderPendingKnocks[sender];
        for (uint256 i = 0; i < pending.length; i++) {
            if (knocks[pending[i]].status == KnockStatus.Pending) {
                count++;
            }
        }
    }

    function _removePending(address sender, uint256 knockId) internal {
        uint256[] storage pending = _senderPendingKnocks[sender];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == knockId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }

    function _removeSettled(address receiver, uint256 knockId) internal {
        uint256[] storage settled = _receiverSettledKnocks[receiver];
        for (uint256 i = 0; i < settled.length; i++) {
            if (settled[i] == knockId) {
                settled[i] = settled[settled.length - 1];
                settled.pop();
                break;
            }
        }
    }

    function _sortByBidDesc(uint256[] storage knockIds) internal {
        uint256 len = knockIds.length;
        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (knocks[knockIds[j]].bid > knocks[knockIds[i]].bid) {
                    uint256 temp = knockIds[i];
                    knockIds[i] = knockIds[j];
                    knockIds[j] = temp;
                }
            }
        }
    }

    function _refund(address to, uint256 amount) internal {
        if (amount > 0) {
            (bool success,) = to.call{value: amount}("");
            require(success, "Refund failed");
        }
    }
}
