// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKnockCard {
    struct Card {
        string nickname;
        string bio;
        string avatar;
        string twitter;
        string github;
        string website;
        uint256 createdAt;
        uint256 knocksSent;
        uint256 knocksAccepted;
        uint256 knocksRejected;
        bool isBanned;
    }

    event CardCreated(address indexed owner, uint256 indexed tokenId);
    event CardUpdated(address indexed owner);
    event CardBanned(address indexed owner);

    error CardAlreadyExists();
    error CardNotFound();
    error CardIsBanned();
    error InsufficientPayment();
    error TransferNotAllowed();
    error OnlyProtocol();

    function createCard(
        string calldata nickname,
        string calldata bio,
        string calldata avatar,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable;

    function updateCard(
        string calldata nickname,
        string calldata bio,
        string calldata avatar,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable;

    function getCard(address owner) external view returns (Card memory);
    function hasCard(address owner) external view returns (bool);
    function incrementKnocksSent(address owner) external;
    function incrementKnocksAccepted(address owner) external;
    function incrementKnocksRejected(address owner) external;
    function banCard(address owner) external;
}
