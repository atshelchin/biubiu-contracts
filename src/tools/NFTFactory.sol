// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INFTFactory} from "../interfaces/INFTFactory.sol";

/**
 * @title NFTFactory
 * @notice Factory to deploy ERC721 NFT collections with CREATE2
 * @dev Part of BiuBiu Tools - https://biubiu.tools
 */
contract NFTFactory is INFTFactory {
    // Hardcoded constants (no external dependencies)
    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;
    uint256 public constant NON_MEMBER_FEE = 0.01 ether;

    // Immutables (set via constructor for cross-chain deterministic deployment)
    address public immutable METADATA_CONTRACT;

    constructor(address _metadataContract) {
        METADATA_CONTRACT = _metadataContract;
    }

    // Usage types
    uint8 public constant USAGE_FREE = 0;
    uint8 public constant USAGE_PAID = 1;

    // Reentrancy guard (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;

    // Statistics
    uint256 public totalFreeUsage;
    uint256 public totalPaidUsage;

    // Errors
    error InsufficientPayment();
    error NameEmpty();
    error SymbolEmpty();
    error ReentrancyDetected();

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
        _;
        _locked = 1;
    }

    address[] public allNFTs;
    mapping(address => address[]) public userNFTs;

    /**
     * @notice Create ERC721 NFT Collection (paid version)
     * @param name Collection name
     * @param symbol Collection symbol
     * @param description Collection description
     * @param externalURL Project website URL
     * @param referrer Referrer address for fee sharing
     */
    function createERC721(
        string memory name,
        string memory symbol,
        string memory description,
        string memory externalURL,
        address referrer
    ) external payable nonReentrant returns (address) {
        // Collect fee (non-members pay directly)
        _collectFee(referrer);

        return _createERC721(name, symbol, description, externalURL, USAGE_PAID);
    }

    /**
     * @notice Create ERC721 NFT Collection (free version)
     * @param name Collection name
     * @param symbol Collection symbol
     * @param description Collection description
     * @param externalURL Project website URL
     */
    function createERC721Free(
        string memory name,
        string memory symbol,
        string memory description,
        string memory externalURL
    ) external nonReentrant returns (address) {
        totalFreeUsage++;
        return _createERC721(name, symbol, description, externalURL, USAGE_FREE);
    }

    /**
     * @dev Internal function to create ERC721 NFT
     */
    function _createERC721(
        string memory name,
        string memory symbol,
        string memory description,
        string memory externalURL,
        uint8 usageType
    ) internal returns (address) {
        if (bytes(name).length == 0) revert NameEmpty();
        if (bytes(symbol).length == 0) revert SymbolEmpty();

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, name, symbol, description, externalURL));

        SocialNFT nft = new SocialNFT{salt: salt}(name, symbol, description, externalURL, msg.sender, METADATA_CONTRACT);

        address nftAddress = address(nft);
        allNFTs.push(nftAddress);
        userNFTs[msg.sender].push(nftAddress);

        emit NFTCreated(nftAddress, msg.sender, name, symbol, description, usageType);

        return nftAddress;
    }

    /**
     * @dev Collect fee from non-member payment
     */
    function _collectFee(address referrer) internal {
        // Must pay the fee
        if (msg.value < NON_MEMBER_FEE) revert InsufficientPayment();

        totalPaidUsage++;

        // Split fee with referrer (50%)
        if (referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = msg.value >> 1; // 50%
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, msg.sender, referralAmount);
            }
        }

        // Transfer remaining to vault
        uint256 vaultAmount = address(this).balance;
        if (vaultAmount > 0) {
            // forge-lint: disable-next-line(unchecked-call)
            payable(VAULT).call{value: vaultAmount}("");
        }
    }

    // ============ Query Functions ============

    /**
     * @notice Get total number of NFTs created
     */
    function allNFTsLength() external view returns (uint256) {
        return allNFTs.length;
    }

    /**
     * @notice Get number of NFTs created by a specific user
     */
    function userNFTsLength(address user) external view returns (uint256) {
        return userNFTs[user].length;
    }

    /**
     * @notice Get all NFTs created by a specific user
     */
    function getUserNFTs(address user) external view returns (address[] memory) {
        return userNFTs[user];
    }

    /**
     * @notice Get all NFTs created through this factory
     */
    function getAllNFTs() external view returns (address[] memory) {
        return allNFTs;
    }

    /**
     * @notice Get user NFTs with pagination
     */
    function getUserNFTsPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total)
    {
        return _paginate(userNFTs[user], offset, limit);
    }

    /**
     * @notice Get all NFTs with pagination
     */
    function getAllNFTsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total)
    {
        return _paginate(allNFTs, offset, limit);
    }

    function _paginate(address[] storage arr, uint256 offset, uint256 limit)
        internal
        view
        returns (address[] memory nfts, uint256 total)
    {
        total = arr.length;
        if (offset >= total) return (new address[](0), total);

        uint256 end = offset + limit;
        if (end > total) end = total;

        uint256 size = end - offset;
        nfts = new address[](size);
        for (uint256 i; i < size;) {
            nfts[i] = arr[offset + i];
            unchecked {
                ++i;
            }
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface INFTMetadata {
    function generateMetadata(
        string memory collectionName,
        string memory tokenName,
        string memory description,
        string memory externalURL,
        uint8 rarity,
        uint8 background,
        uint8 pattern,
        uint8 glow,
        uint256 luckyNumber,
        uint256 driftCount
    ) external view returns (string memory);
}

/**
 * @title SocialNFT
 * @notice ERC721 NFT with random traits and social features
 * @dev Each transfer creates a "drift" record, recipients can leave messages
 * @dev Part of BiuBiu Tools - https://biubiu.tools
 */
contract SocialNFT {
    // NFTMetadata contract address (deployed separately, passed via constructor)
    address public immutable METADATA_CONTRACT;

    // Collection info
    string public name;
    string public symbol;
    string public collectionDescription;
    string public externalURL; // Project website URL

    uint256 public totalSupply;
    uint256 public nextTokenId;
    address public owner;

    // Rarity constants
    uint8 public constant RARITY_COMMON = 0; // 70%
    uint8 public constant RARITY_RARE = 1; // 20%
    uint8 public constant RARITY_LEGENDARY = 2; // 8%
    uint8 public constant RARITY_EPIC = 3; // 2%

    // Token metadata
    struct TokenData {
        string name;
        string description;
        uint256 createdAt;
    }

    // Token traits (randomly generated)
    struct TokenTraits {
        uint8 rarity;
        uint8 background; // 0-9
        uint8 pattern; // 0-9
        uint8 glow; // 0-9
        uint256 luckyNumber; // 0-9999
    }

    // Drift message (transfer history)
    struct DriftMessage {
        address from;
        string message;
        uint256 timestamp;
    }

    // ERC721 storage
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // Metadata storage
    mapping(uint256 => TokenData) public tokenData;
    mapping(uint256 => TokenTraits) public tokenTraits;
    mapping(uint256 => DriftMessage[]) internal _driftHistory;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Minted(uint256 indexed tokenId, address indexed to, uint8 rarity, uint256 luckyNumber);
    event Drifted(uint256 indexed tokenId, address indexed from, address indexed to);
    event MessageLeft(uint256 indexed tokenId, address indexed by, string message);

    // Errors
    error NotOwner();
    error NotTokenOwner();
    error InvalidRecipient();
    error TokenNotExist();
    error NotAuthorized();
    error AlreadyLeftMessage();
    error TransferToNonReceiver();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _collectionDescription,
        string memory _externalURL,
        address _owner,
        address _metadataContract
    ) {
        name = _name;
        symbol = _symbol;
        collectionDescription = _collectionDescription;
        externalURL = _externalURL;
        owner = _owner;
        METADATA_CONTRACT = _metadataContract;
    }

    // ============ Mint Functions ============

    /**
     * @notice Mint NFT with on-chain generated SVG (only owner)
     * @param to Recipient address
     * @param _name Token name
     * @param _description Token description
     */
    function mint(address to, string calldata _name, string calldata _description) public onlyOwner returns (uint256) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 tokenId = nextTokenId++;
        ownerOf[tokenId] = to;
        unchecked {
            balanceOf[to]++;
            totalSupply++;
        }

        tokenData[tokenId] = TokenData({name: _name, description: _description, createdAt: block.timestamp});
        tokenTraits[tokenId] = _generateTraits(tokenId);

        emit Transfer(address(0), to, tokenId);
        emit Minted(tokenId, to, tokenTraits[tokenId].rarity, tokenTraits[tokenId].luckyNumber);

        return tokenId;
    }

    // ============ Drift (Transfer Message) System ============

    /**
     * @notice Leave a message after receiving an NFT
     * @param tokenId Token ID
     * @param message Your message
     */
    function leaveMessage(uint256 tokenId, string calldata message) public {
        if (ownerOf[tokenId] != msg.sender) revert NotTokenOwner();

        uint256 len = _driftHistory[tokenId].length;

        // 检查是否已经留过言（最后一条记录的 from 是自己）
        if (len > 0 && _driftHistory[tokenId][len - 1].from == msg.sender) {
            revert AlreadyLeftMessage();
        }

        // 直接 push 新记录（只有真正留言时才写入）
        _driftHistory[tokenId].push(DriftMessage({from: msg.sender, message: message, timestamp: block.timestamp}));

        emit MessageLeft(tokenId, msg.sender, message);
    }

    /**
     * @notice Get drift history for a token
     * @param tokenId Token ID
     * @return Array of drift messages
     */
    function getDriftHistory(uint256 tokenId) public view returns (DriftMessage[] memory) {
        return _driftHistory[tokenId];
    }

    /**
     * @notice Get drift count for a token
     * @param tokenId Token ID
     * @return Number of times the token has been transferred
     */
    function getDriftCount(uint256 tokenId) public view returns (uint256) {
        return _driftHistory[tokenId].length;
    }

    /**
     * @notice Get drift history with pagination
     * @param tokenId Token ID
     * @param offset Starting index
     * @param limit Maximum number of records to return
     * @return messages Array of drift messages
     * @return total Total number of drift records for this token
     */
    function getDriftHistoryPaginated(uint256 tokenId, uint256 offset, uint256 limit)
        public
        view
        returns (DriftMessage[] memory messages, uint256 total)
    {
        total = _driftHistory[tokenId].length;

        if (offset >= total) {
            return (new DriftMessage[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        messages = new DriftMessage[](size);

        for (uint256 i = 0; i < size; i++) {
            messages[i] = _driftHistory[tokenId][offset + i];
        }

        return (messages, total);
    }

    // ============ ERC721 Functions ============

    function approve(address spender, uint256 tokenId) public {
        address tokenOwner = ownerOf[tokenId];
        if (msg.sender != tokenOwner && !isApprovedForAll[tokenOwner][msg.sender]) {
            revert NotAuthorized();
        }
        getApproved[tokenId] = spender;
        emit Approval(tokenOwner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (from != ownerOf[tokenId]) revert NotTokenOwner();
        if (to == address(0)) revert InvalidRecipient();
        if (msg.sender != from && msg.sender != getApproved[tokenId] && !isApprovedForAll[from][msg.sender]) {
            revert NotAuthorized();
        }

        _transfer(from, to, tokenId);
    }

    /**
     * @notice Drift NFT to next owner with a message (atomic operation)
     * @param to Next owner address
     * @param tokenId Token ID
     * @param message Your message to leave on this drift bottle
     */
    function driftWithMessage(address to, uint256 tokenId, string calldata message) public {
        address from = ownerOf[tokenId];
        if (from != msg.sender) revert NotTokenOwner();
        if (to == address(0)) revert InvalidRecipient();

        // 检查是否已经留过言
        uint256 len = _driftHistory[tokenId].length;
        if (len > 0 && _driftHistory[tokenId][len - 1].from == msg.sender) {
            revert AlreadyLeftMessage();
        }

        // 记录留言
        _driftHistory[tokenId].push(DriftMessage({from: msg.sender, message: message, timestamp: block.timestamp}));

        emit MessageLeft(tokenId, msg.sender, message);

        _transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        balanceOf[from]--;
        balanceOf[to]++;
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];

        emit Transfer(from, to, tokenId);
        emit Drifted(tokenId, from, to);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    revert TransferToNonReceiver();
                }
            } catch {
                revert TransferToNonReceiver();
            }
        }
    }

    // ============ Metadata Functions ============

    /**
     * @notice Get token URI with on-chain metadata
     * @param tokenId Token ID
     * @return Token URI string (data URI with JSON metadata)
     */
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (ownerOf[tokenId] == address(0)) revert TokenNotExist();
        TokenData storage data = tokenData[tokenId];
        return _generateOnChainMetadata(tokenId, data);
    }

    function _generateOnChainMetadata(uint256 tokenId, TokenData storage data) internal view returns (string memory) {
        TokenTraits storage traits = tokenTraits[tokenId];
        uint256 driftCount = _driftHistory[tokenId].length;
        return INFTMetadata(METADATA_CONTRACT)
            .generateMetadata(
                name,
                data.name,
                data.description,
                externalURL,
                traits.rarity,
                traits.background,
                traits.pattern,
                traits.glow,
                traits.luckyNumber,
                driftCount
            );
    }

    /**
     * @notice Get token traits
     * @param tokenId Token ID
     */
    function getTokenTraits(uint256 tokenId)
        public
        view
        returns (uint8 rarity, uint8 background, uint8 pattern, uint8 glow, uint256 luckyNumber)
    {
        TokenTraits memory traits = tokenTraits[tokenId];
        return (traits.rarity, traits.background, traits.pattern, traits.glow, traits.luckyNumber);
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x80ac58cd // ERC721
                || interfaceId == 0x5b5e139f // ERC721Metadata
                || interfaceId == 0x01ffc9a7; // ERC165
    }

    // ============ Internal Functions ============

    function _generateTraits(uint256 tokenId) internal view returns (TokenTraits memory) {
        // Enhanced entropy: add historical block hashes for better randomness
        // Use safe block hash retrieval to avoid underflow on early blocks
        bytes32 hash1 = block.number > 0 ? blockhash(block.number - 1) : bytes32(0);
        bytes32 hash2 = block.number > 1 ? blockhash(block.number - 2) : bytes32(0);

        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp, block.prevrandao, hash1, hash2, msg.sender, tokenId, totalSupply, address(this)
                )
            )
        );

        // Rarity distribution: Common 70%, Rare 20%, Legendary 8%, Epic 2%
        uint8 rarity;
        uint256 roll = seed % 100;
        if (roll < 2) {
            rarity = RARITY_EPIC; // 2%
        } else if (roll < 10) {
            rarity = RARITY_LEGENDARY; // 8%
        } else if (roll < 30) {
            rarity = RARITY_RARE; // 20%
        } else {
            rarity = RARITY_COMMON; // 70%
        }

        return TokenTraits({
            rarity: rarity,
            background: uint8((seed >> 8) % 10),
            pattern: uint8((seed >> 16) % 10),
            glow: uint8((seed >> 24) % 10),
            luckyNumber: (seed >> 32) % 10000
        });
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
