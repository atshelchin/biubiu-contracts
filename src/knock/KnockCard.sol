// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IKnockCard} from "./interfaces/IKnockCard.sol";

/// @title KnockCard - Soulbound Token (SBT) for Knock Protocol
/// @notice Each address can only have one card, and it cannot be transferred
contract KnockCard is IKnockCard {
    uint256 public constant CARD_FEE = 0.1 ether;

    string public name = "Knock Card";
    string public symbol = "KNOCK";

    address public protocol;
    address public owner;

    mapping(address => Card) private _cards;
    mapping(address => bool) private _hasCard;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert OnlyProtocol();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Set the protocol address (can only be set once)
    function setProtocol(address _protocol) external onlyOwner {
        require(protocol == address(0), "Protocol already set");
        protocol = _protocol;
    }

    /// @notice Create a new card (SBT)
    function createCard(
        string calldata nickname,
        string calldata bio,
        string calldata avatar,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable {
        if (_hasCard[msg.sender]) revert CardAlreadyExists();
        if (msg.value < CARD_FEE) revert InsufficientPayment();

        _cards[msg.sender] = Card({
            nickname: nickname,
            bio: bio,
            avatar: avatar,
            twitter: twitter,
            github: github,
            website: website,
            createdAt: block.timestamp,
            knocksSent: 0,
            knocksAccepted: 0,
            knocksRejected: 0,
            isBanned: false
        });

        _hasCard[msg.sender] = true;

        emit CardCreated(msg.sender, uint256(uint160(msg.sender)));
    }

    /// @notice Update card information
    function updateCard(
        string calldata nickname,
        string calldata bio,
        string calldata avatar,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable {
        if (!_hasCard[msg.sender]) revert CardNotFound();
        if (_cards[msg.sender].isBanned) revert CardIsBanned();
        if (msg.value < CARD_FEE) revert InsufficientPayment();

        Card storage card = _cards[msg.sender];
        card.nickname = nickname;
        card.bio = bio;
        card.avatar = avatar;
        card.twitter = twitter;
        card.github = github;
        card.website = website;

        emit CardUpdated(msg.sender);
    }

    /// @notice Get card information
    function getCard(address cardOwner) external view returns (Card memory) {
        if (!_hasCard[cardOwner]) revert CardNotFound();
        return _cards[cardOwner];
    }

    /// @notice Check if address has a card
    function hasCard(address cardOwner) external view returns (bool) {
        return _hasCard[cardOwner] && !_cards[cardOwner].isBanned;
    }

    /// @notice Increment knocks sent counter (only protocol)
    function incrementKnocksSent(address cardOwner) external onlyProtocol {
        _cards[cardOwner].knocksSent++;
    }

    /// @notice Increment knocks accepted counter (only protocol)
    function incrementKnocksAccepted(address cardOwner) external onlyProtocol {
        _cards[cardOwner].knocksAccepted++;
    }

    /// @notice Increment knocks rejected counter (only protocol)
    function incrementKnocksRejected(address cardOwner) external onlyProtocol {
        _cards[cardOwner].knocksRejected++;
    }

    /// @notice Ban a card (only protocol)
    function banCard(address cardOwner) external onlyProtocol {
        if (!_hasCard[cardOwner]) revert CardNotFound();
        _cards[cardOwner].isBanned = true;
        _hasCard[cardOwner] = false;
        emit CardBanned(cardOwner);
    }

    /// @notice Withdraw collected fees
    function withdraw() external onlyOwner {
        (bool success,) = owner.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ============ ERC721 Compatibility (Read Only) ============

    function balanceOf(address cardOwner) external view returns (uint256) {
        return (_hasCard[cardOwner] && !_cards[cardOwner].isBanned) ? 1 : 0;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address cardOwner = address(uint160(tokenId));
        if (!_hasCard[cardOwner] || _cards[cardOwner].isBanned) {
            revert CardNotFound();
        }
        return cardOwner;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address cardOwner = address(uint160(tokenId));
        if (!_hasCard[cardOwner]) revert CardNotFound();
        // TODO: Generate on-chain SVG or return IPFS URI
        return "";
    }

    // ============ Disabled Transfer Functions ============

    function transferFrom(address, address, uint256) external pure {
        revert TransferNotAllowed();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert TransferNotAllowed();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert TransferNotAllowed();
    }

    function approve(address, uint256) external pure {
        revert TransferNotAllowed();
    }

    function setApprovalForAll(address, bool) external pure {
        revert TransferNotAllowed();
    }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x01ffc9a7; // ERC165
    }
}
