// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKnockProtocol {
    enum KnockStatus {
        Pending,    // Waiting for daily settlement
        Settled,    // Selected, waiting for receiver to process
        Accepted,   // Receiver accepted
        Rejected,   // Receiver rejected
        Refunded,   // Not selected, refunded
        Expired     // Not processed within 7 days
    }

    struct Knock {
        uint256 id;
        address sender;
        address receiver;
        uint256 bid;
        bytes32 contentId;      // PDF file ID from official platform
        uint256 createdAt;
        uint256 settleDay;      // UTC day number for settlement
        KnockStatus status;
    }

    struct ReceiverSettings {
        uint256 dailySlots;     // Max knocks to receive per day (default 10)
        bool isConfigured;      // Whether receiver has configured settings
    }

    struct ReceiverStats {
        uint256 totalReceived;
        uint256 totalEthReceived;
        uint256 accepted;
        uint256 rejected;
    }

    // Events
    event KnockSent(
        uint256 indexed knockId,
        address indexed sender,
        address indexed receiver,
        uint256 bid,
        bytes32 contentId
    );
    event KnockSettled(uint256 indexed knockId, bool selected);
    event KnockAccepted(uint256 indexed knockId, address indexed receiver);
    event KnockRejected(uint256 indexed knockId, address indexed receiver);
    event KnockExpired(uint256 indexed knockId);
    event KnockRefunded(uint256 indexed knockId, address indexed sender, uint256 amount);
    event SettingsUpdated(address indexed receiver, uint256 dailySlots);

    // Errors
    error NoCard();
    error CardBanned();
    error TooManyPendingKnocks();
    error BidTooLow();
    error CannotKnockSelf();
    error KnockNotFound();
    error NotReceiver();
    error InvalidStatus();
    error NotExpired();
    error AlreadySettled();

    // Core functions
    function knock(address receiver, bytes32 contentId) external payable returns (uint256 knockId);
    function settle(address receiver) external;
    function accept(uint256 knockId) external;
    function reject(uint256 knockId) external;
    function claimExpired(uint256 knockId) external;

    // Settings
    function setDailySlots(uint256 slots) external;

    // View functions
    function getKnock(uint256 knockId) external view returns (Knock memory);
    function getPendingKnocks(address sender) external view returns (uint256[] memory);
    function getSettledKnocks(address receiver) external view returns (uint256[] memory);
    function getReceiverSettings(address receiver) external view returns (ReceiverSettings memory);
    function getReceiverStats(address receiver) external view returns (ReceiverStats memory);
    function getCurrentDay() external view returns (uint256);
}
