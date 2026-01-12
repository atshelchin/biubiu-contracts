// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKnockCard {
    struct Card {
        string nickname; // Unique, immutable once set
        string bio;
        string twitter;
        string github;
        string website;
        uint256 createdAt;
        uint256 ethReceived; // Total ETH received from knocks (in wei) - most authoritative metric
        uint256 knocksReceived; // Incoming knock requests (like followers)
        uint256 knocksSent; // Outgoing knock requests (like following)
        uint256 knocksAccepted; // Sender's knocks that were accepted
        uint256 knocksRejected; // Sender's knocks that were rejected
        bool isBanned;
    }

    event CardCreated(address indexed owner, uint256 indexed tokenId, string nickname);
    event CardUpdated(address indexed owner);
    event CardBanned(address indexed owner);

    error CardAlreadyExists();
    error CardNotFound();
    error CardIsBanned();
    error InsufficientPayment();
    error TransferNotAllowed();
    error OnlyProtocol();
    error NicknameAlreadyTaken();
    error NicknameRequired();
    error NicknameTooLong();

    function createCard(
        string calldata nickname,
        string calldata bio,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable;

    function updateCard(string calldata bio, string calldata twitter, string calldata github, string calldata website)
        external
        payable;

    function getCard(address owner) external view returns (Card memory);
    function hasCard(address owner) external view returns (bool);
    function isNicknameTaken(string calldata nickname) external view returns (bool);
    function getOwnerByNickname(string calldata nickname) external view returns (address);

    // Convenience lookup methods
    function getNickname(address owner) external view returns (string memory);
    function getCardByTokenId(uint256 tokenId) external view returns (Card memory);
    function getCardByNickname(string calldata nickname) external view returns (Card memory);
    function getTokenId(address owner) external pure returns (uint256);

    function addEthReceived(address owner, uint256 amount) external;
    function incrementKnocksReceived(address owner) external;
    function incrementKnocksSent(address owner) external;
    function incrementKnocksAccepted(address owner) external;
    function incrementKnocksRejected(address owner) external;
    function banCard(address owner) external;
}
