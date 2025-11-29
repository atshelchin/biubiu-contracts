// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20
 * @notice Minimal ERC20 interface for staking
 */
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title SimpleERC721
 * @notice ERC721 NFT with stake-to-mint mechanism
 */
contract SimpleERC721 {
    string public name;
    string public symbol;
    string public baseURI;

    uint256 public totalSupply;
    uint256 public nextTokenId;

    address public owner;
    bool public publicMintEnabled;

    // Stake-to-mint settings
    bool public stakeToMintEnabled;
    address public stakeToken; // ERC20 token required for minting
    uint256 public stakeAmount; // Amount of tokens to stake per NFT

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // Stake tracking: tokenId => staked amount
    mapping(uint256 => uint256) public stakedAmount;

    // Reentrancy guard
    uint256 private locked = 1;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Staked(uint256 indexed tokenId, uint256 amount);
    event Redeemed(uint256 indexed tokenId, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(locked == 1, "Reentrancy detected");
        locked = 2;
        _;
        locked = 1;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        address _owner,
        bool _publicMintEnabled,
        bool _stakeToMintEnabled,
        address _stakeToken,
        uint256 _stakeAmount
    ) {
        name = _name;
        symbol = _symbol;
        baseURI = _baseURI;
        owner = _owner;
        publicMintEnabled = _publicMintEnabled;
        stakeToMintEnabled = _stakeToMintEnabled;
        stakeToken = _stakeToken;
        stakeAmount = _stakeAmount;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(ownerOf[tokenId] != address(0), "Token does not exist");
        return string(abi.encodePacked(baseURI, _toString(tokenId)));
    }

    function approve(address spender, uint256 tokenId) public {
        address tokenOwner = ownerOf[tokenId];
        require(msg.sender == tokenOwner || isApprovedForAll[tokenOwner][msg.sender], "Not authorized");
        getApproved[tokenId] = spender;
        emit Approval(tokenOwner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(from == ownerOf[tokenId], "Wrong from");
        require(to != address(0), "Invalid recipient");
        require(
            msg.sender == from || msg.sender == getApproved[tokenId] || isApprovedForAll[from][msg.sender],
            "Not authorized"
        );

        balanceOf[from]--;
        balanceOf[to]++;
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory) public {
        transferFrom(from, to, tokenId);
    }

    /**
     * @notice Mint NFT by owner (traditional way)
     */
    function mint(address to) public onlyOwner returns (uint256) {
        require(!stakeToMintEnabled, "Stake-to-mint is enabled");
        return _mint(to, 0);
    }

    /**
     * @notice Mint NFT by staking ERC20 tokens
     */
    function stakeToMint() public nonReentrant returns (uint256) {
        require(stakeToMintEnabled, "Stake-to-mint not enabled");
        require(publicMintEnabled || msg.sender == owner, "Public mint disabled");
        require(stakeToken != address(0), "Stake token not set");
        require(stakeAmount > 0, "Stake amount not set");

        // Transfer stake tokens from user to this contract (CEI pattern)
        _safeTransferFrom(stakeToken, msg.sender, address(this), stakeAmount);

        uint256 tokenId = _mint(msg.sender, stakeAmount);

        emit Staked(tokenId, stakeAmount);
        return tokenId;
    }

    /**
     * @notice Burn NFT and redeem staked tokens
     */
    function burnToRedeem(uint256 tokenId) public nonReentrant {
        require(ownerOf[tokenId] == msg.sender, "Not token owner");
        require(stakedAmount[tokenId] > 0, "No staked amount");

        uint256 redeemAmount = stakedAmount[tokenId];
        address tokenOwner = msg.sender;

        // Check contract has enough balance
        require(IERC20(stakeToken).balanceOf(address(this)) >= redeemAmount, "Insufficient contract balance");

        // Burn NFT (CEI pattern - effects before interaction)
        balanceOf[tokenOwner]--;
        delete ownerOf[tokenId];
        delete stakedAmount[tokenId];
        totalSupply--;

        emit Transfer(tokenOwner, address(0), tokenId);

        // Return staked tokens (interaction last)
        _safeTransfer(stakeToken, tokenOwner, redeemAmount);

        emit Redeemed(tokenId, redeemAmount);
    }

    function _mint(address to, uint256 stakedAmt) internal returns (uint256) {
        require(to != address(0), "Invalid recipient");

        uint256 tokenId = nextTokenId++;
        ownerOf[tokenId] = to;
        balanceOf[to]++;
        totalSupply++;

        if (stakedAmt > 0) {
            stakedAmount[tokenId] = stakedAmt;
        }

        emit Transfer(address(0), to, tokenId);
        return tokenId;
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

    /**
     * @notice Check if a token can be redeemed
     */
    function canRedeem(uint256 tokenId) public view returns (bool) {
        return stakedAmount[tokenId] > 0 && ownerOf[tokenId] != address(0);
    }

    /**
     * @notice Get redeemable amount for a token
     */
    function getRedeemableAmount(uint256 tokenId) public view returns (uint256) {
        return stakedAmount[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f || interfaceId == 0x01ffc9a7;
    }

    /**
     * @notice Safe ERC20 transfer (handles non-standard tokens like USDT)
     */
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    /**
     * @notice Safe ERC20 transferFrom (handles non-standard tokens like USDT)
     */
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
}

/**
 * @title NFTFactory
 * @notice Factory to deploy ERC721 NFTs with CREATE2
 */
contract NFTFactory {
    struct NFTInfo {
        address nftAddress;
        string name;
        string symbol;
        address creator;
        bool stakeToMintEnabled;
        address stakeToken;
    }

    event NFTCreated(
        address indexed nftAddress,
        address indexed creator,
        string name,
        string symbol,
        bool stakeToMintEnabled,
        address stakeToken
    );

    address[] public allNFTs;
    mapping(address => address[]) public userNFTs;

    /**
     * @notice Create ERC721 NFT
     */
    function createERC721(
        string memory name,
        string memory symbol,
        string memory baseURI,
        bool publicMintEnabled,
        bool stakeToMintEnabled,
        address stakeToken,
        uint256 stakeAmount
    ) external returns (address) {
        require(bytes(name).length > 0, "Name empty");
        require(bytes(symbol).length > 0, "Symbol empty");

        if (stakeToMintEnabled) {
            require(stakeToken != address(0), "Stake token required");
            require(stakeAmount > 0, "Stake amount required");
        }

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, name, symbol, baseURI, stakeToken, stakeAmount));

        SimpleERC721 nft = new SimpleERC721{salt: salt}(
            name, symbol, baseURI, msg.sender, publicMintEnabled, stakeToMintEnabled, stakeToken, stakeAmount
        );

        address nftAddress = address(nft);
        allNFTs.push(nftAddress);
        userNFTs[msg.sender].push(nftAddress);

        emit NFTCreated(nftAddress, msg.sender, name, symbol, stakeToMintEnabled, stakeToken);

        return nftAddress;
    }

    /**
     * @notice Get NFT info from NFT address
     * @param nftAddress NFT contract address
     * @return info NFTInfo struct with all NFT details
     */
    function getNFTInfo(address nftAddress) public view returns (NFTInfo memory info) {
        SimpleERC721 nft = SimpleERC721(nftAddress);
        info = NFTInfo({
            nftAddress: nftAddress,
            name: nft.name(),
            symbol: nft.symbol(),
            creator: nft.owner(),
            stakeToMintEnabled: nft.stakeToMintEnabled(),
            stakeToken: nft.stakeToken()
        });
    }

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
     * @notice Get user NFTs with pagination (addresses only)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nfts Array of NFT addresses
     * @return total Total number of NFTs for this user
     */
    function getUserNFTsPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total)
    {
        total = userNFTs[user].length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        nfts = new address[](size);

        for (uint256 i = 0; i < size; i++) {
            nfts[i] = userNFTs[user][offset + i];
        }

        return (nfts, total);
    }

    /**
     * @notice Get user NFTs with pagination (with full NFT info)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nftInfos Array of NFTInfo structs
     * @return total Total number of NFTs for this user
     */
    function getUserNFTsInfoPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (NFTInfo[] memory nftInfos, uint256 total)
    {
        total = userNFTs[user].length;

        if (offset >= total) {
            return (new NFTInfo[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        nftInfos = new NFTInfo[](size);

        for (uint256 i = 0; i < size; i++) {
            nftInfos[i] = getNFTInfo(userNFTs[user][offset + i]);
        }

        return (nftInfos, total);
    }

    /**
     * @notice Get all NFTs with pagination (addresses only)
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nfts Array of NFT addresses
     * @return total Total number of NFTs
     */
    function getAllNFTsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory nfts, uint256 total)
    {
        total = allNFTs.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        nfts = new address[](size);

        for (uint256 i = 0; i < size; i++) {
            nfts[i] = allNFTs[offset + i];
        }

        return (nfts, total);
    }

    /**
     * @notice Get all NFTs with pagination (with full NFT info)
     * @param offset Starting index
     * @param limit Maximum number of NFTs to return
     * @return nftInfos Array of NFTInfo structs
     * @return total Total number of NFTs
     */
    function getAllNFTsInfoPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (NFTInfo[] memory nftInfos, uint256 total)
    {
        total = allNFTs.length;

        if (offset >= total) {
            return (new NFTInfo[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        nftInfos = new NFTInfo[](size);

        for (uint256 i = 0; i < size; i++) {
            nftInfos[i] = getNFTInfo(allNFTs[offset + i]);
        }

        return (nftInfos, total);
    }
}
