// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IKnockCard} from "./interfaces/IKnockCard.sol";

/// @title KnockCard - Soulbound Token (SBT) for Knock Protocol
/// @notice Each address can only have one card, and it cannot be transferred
/// @dev Nickname is unique globally and immutable once set
contract KnockCard is IKnockCard {
    uint256 public constant CARD_FEE = 0.1 ether;
    uint256 public constant MAX_NICKNAME_LENGTH = 20;
    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;

    string public name = "Knock Card";
    string public symbol = "KNOCK";

    address public immutable protocol;
    address public metadataContract;

    mapping(address => Card) private _cards;
    mapping(address => bool) private _hasCard;
    mapping(bytes32 => address) private _nicknameToOwner; // lowercase nickname hash => owner

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert OnlyProtocol();
        _;
    }

    constructor(address _protocol) {
        protocol = _protocol;
    }

    /// @notice Set metadata contract address (can only be set once)
    function setMetadataContract(address _metadata) external {
        require(metadataContract == address(0), "Already set");
        require(msg.sender == protocol, "Only protocol");
        metadataContract = _metadata;
    }

    /// @notice Create a new card (SBT) with unique nickname
    function createCard(
        string calldata nickname,
        string calldata bio,
        string calldata twitter,
        string calldata github,
        string calldata website
    ) external payable {
        if (_hasCard[msg.sender]) revert CardAlreadyExists();
        if (msg.value < CARD_FEE) revert InsufficientPayment();
        if (bytes(nickname).length == 0) revert NicknameRequired();
        if (bytes(nickname).length > MAX_NICKNAME_LENGTH) revert NicknameTooLong();

        // Check nickname uniqueness (case-insensitive)
        bytes32 nicknameHash = _normalizeNickname(nickname);
        if (_nicknameToOwner[nicknameHash] != address(0)) revert NicknameAlreadyTaken();

        // Register nickname
        _nicknameToOwner[nicknameHash] = msg.sender;

        // Preserve accumulated stats (ETH received before card creation)
        Card storage card = _cards[msg.sender];
        uint256 prevEthReceived = card.ethReceived;
        uint256 prevKnocksReceived = card.knocksReceived;

        _cards[msg.sender] = Card({
            nickname: nickname,
            bio: bio,
            twitter: twitter,
            github: github,
            website: website,
            createdAt: block.timestamp,
            ethReceived: prevEthReceived,
            knocksReceived: prevKnocksReceived,
            knocksSent: 0,
            knocksAccepted: 0,
            knocksRejected: 0,
            isBanned: false
        });

        _hasCard[msg.sender] = true;

        // Send fee to VAULT
        (bool success,) = VAULT.call{value: msg.value}("");
        require(success, "Fee transfer failed");

        emit CardCreated(msg.sender, uint256(uint160(msg.sender)), nickname);
    }

    /// @notice Update card information (nickname cannot be changed)
    function updateCard(string calldata bio, string calldata twitter, string calldata github, string calldata website)
        external
        payable
    {
        if (!_hasCard[msg.sender]) revert CardNotFound();
        if (_cards[msg.sender].isBanned) revert CardIsBanned();
        if (msg.value < CARD_FEE) revert InsufficientPayment();

        Card storage card = _cards[msg.sender];
        // nickname is NOT updated - it's immutable
        card.bio = bio;
        card.twitter = twitter;
        card.github = github;
        card.website = website;

        // Send fee to VAULT
        (bool success,) = VAULT.call{value: msg.value}("");
        require(success, "Fee transfer failed");

        emit CardUpdated(msg.sender);
    }

    /// @notice Get card information
    function getCard(address cardOwner) external view returns (Card memory) {
        if (!_hasCard[cardOwner]) revert CardNotFound();
        return _cards[cardOwner];
    }

    /// @notice Check if address has a valid card
    function hasCard(address cardOwner) external view returns (bool) {
        return _hasCard[cardOwner] && !_cards[cardOwner].isBanned;
    }

    /// @notice Check if nickname is already taken
    function isNicknameTaken(string calldata nickname) external view returns (bool) {
        bytes32 nicknameHash = _normalizeNickname(nickname);
        return _nicknameToOwner[nicknameHash] != address(0);
    }

    /// @notice Get card owner by nickname
    function getOwnerByNickname(string calldata nickname) external view returns (address) {
        bytes32 nicknameHash = _normalizeNickname(nickname);
        return _nicknameToOwner[nicknameHash];
    }

    /// @notice Get nickname by address
    function getNickname(address cardOwner) external view returns (string memory) {
        if (!_hasCard[cardOwner]) revert CardNotFound();
        return _cards[cardOwner].nickname;
    }

    /// @notice Get card by tokenId (tokenId = uint256(uint160(address)))
    function getCardByTokenId(uint256 tokenId) external view returns (Card memory) {
        address cardOwner = address(uint160(tokenId));
        if (!_hasCard[cardOwner]) revert CardNotFound();
        return _cards[cardOwner];
    }

    /// @notice Get card by nickname
    function getCardByNickname(string calldata nickname) external view returns (Card memory) {
        bytes32 nicknameHash = _normalizeNickname(nickname);
        address cardOwner = _nicknameToOwner[nicknameHash];
        if (cardOwner == address(0)) revert CardNotFound();
        return _cards[cardOwner];
    }

    /// @notice Get tokenId by address (tokenId = uint256(uint160(address)))
    function getTokenId(address cardOwner) external pure returns (uint256) {
        return uint256(uint160(cardOwner));
    }

    /// @notice Add ETH received (only protocol)
    function addEthReceived(address cardOwner, uint256 amount) external onlyProtocol {
        _cards[cardOwner].ethReceived += amount;
    }

    /// @notice Increment knocks received counter (only protocol)
    function incrementKnocksReceived(address cardOwner) external onlyProtocol {
        _cards[cardOwner].knocksReceived++;
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
        // Note: nickname remains occupied even after ban
        emit CardBanned(cardOwner);
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

        if (metadataContract != address(0)) {
            // Call metadata contract to generate SVG
            (bool success, bytes memory data) =
                metadataContract.staticcall(abi.encodeWithSignature("generateMetadata(address)", cardOwner));
            if (success && data.length > 0) {
                return abi.decode(data, (string));
            }
        }
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
        return interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x01ffc9a7; // ERC165
    }

    // ============ Internal Functions ============

    /// @dev Normalize nickname to lowercase hash for case-insensitive uniqueness
    function _normalizeNickname(string calldata nickname) internal pure returns (bytes32) {
        bytes memory b = bytes(nickname);
        bytes memory lower = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                // A-Z -> a-z
                lower[i] = bytes1(uint8(b[i]) + 32);
            } else {
                lower[i] = b[i];
            }
        }
        return keccak256(lower);
    }
}
