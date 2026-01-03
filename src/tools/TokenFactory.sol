// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBiuBiuPremium {
    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime);
    function VAULT() external view returns (address);
    function NON_MEMBER_FEE() external view returns (uint256);
}

/**
 * @title SimpleToken
 * @notice A simple ERC20 token with optional minting capability
 * @dev Part of BiuBiu Tools - https://biubiu.tools
 */
contract SimpleToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    bool public mintable;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "SimpleToken: caller is not the owner");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply,
        bool _mintable,
        address _owner
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        mintable = _mintable;
        owner = _owner;

        if (_initialSupply > 0) {
            totalSupply = _initialSupply;
            balanceOf[_owner] = _initialSupply;
            emit Transfer(address(0), _owner, _initialSupply);
        }
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(to != address(0), "SimpleToken: transfer to the zero address");
        require(balanceOf[msg.sender] >= value, "SimpleToken: insufficient balance");

        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        require(spender != address(0), "SimpleToken: approve to the zero address");

        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(from != address(0), "SimpleToken: transfer from the zero address");
        require(to != address(0), "SimpleToken: transfer to the zero address");
        require(balanceOf[from] >= value, "SimpleToken: insufficient balance");
        require(allowance[from][msg.sender] >= value, "SimpleToken: insufficient allowance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @notice Mint new tokens (only if mintable is true)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(mintable, "SimpleToken: minting is disabled");
        require(to != address(0), "SimpleToken: mint to the zero address");
        require(amount > 0, "SimpleToken: mint amount must be greater than 0");

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title TokenFactory
 * @notice Factory contract to deploy custom ERC20 tokens
 * @dev Part of BiuBiu Tools - https://biubiu.tools
 */
contract TokenFactory {
    // Immutables (set via constructor for cross-chain deterministic deployment)
    IBiuBiuPremium public immutable PREMIUM_CONTRACT;

    constructor(address _premiumContract) {
        PREMIUM_CONTRACT = IBiuBiuPremium(_premiumContract);
    }

    /// @notice Get the vault address from PREMIUM_CONTRACT
    function VAULT() public view returns (address) {
        return PREMIUM_CONTRACT.VAULT();
    }

    /// @notice Get the non-member fee from PREMIUM_CONTRACT
    function NON_MEMBER_FEE() public view returns (uint256) {
        return PREMIUM_CONTRACT.NON_MEMBER_FEE();
    }

    // Usage types
    uint8 public constant USAGE_FREE = 0;
    uint8 public constant USAGE_PREMIUM = 1;
    uint8 public constant USAGE_PAID = 2;

    // Statistics
    uint256 public totalFreeUsage;
    uint256 public totalPremiumUsage;
    uint256 public totalPaidUsage;

    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        bool mintable;
        address owner;
    }

    // Errors
    error InsufficientPayment();

    // Events
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        uint8 usageType
    );
    event ReferralPaid(address indexed referrer, address indexed payer, uint256 amount);
    event FeePaid(address indexed payer, uint256 amount);

    // Track all created tokens
    address[] public allTokens;
    mapping(address => address[]) public userTokens;

    /**
     * @notice Create a new ERC20 token (paid version)
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals (usually 18)
     * @param initialSupply Initial token supply (will be minted to creator)
     * @param mintable Whether the token can be minted after deployment
     * @param referrer Referrer address for fee sharing
     * @return tokenAddress Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        address referrer
    ) external payable returns (address tokenAddress) {
        // Check premium status and collect fee
        uint8 usageType = _checkAndCollectFee(referrer);

        // Create token
        tokenAddress = _createToken(name, symbol, decimals, initialSupply, mintable, usageType);

        return tokenAddress;
    }

    /**
     * @notice Create a new ERC20 token (free version)
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals (usually 18)
     * @param initialSupply Initial token supply (will be minted to creator)
     * @param mintable Whether the token can be minted after deployment
     * @return tokenAddress Address of the newly created token
     */
    function createTokenFree(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable
    ) external returns (address tokenAddress) {
        totalFreeUsage++;
        tokenAddress = _createToken(name, symbol, decimals, initialSupply, mintable, USAGE_FREE);
        return tokenAddress;
    }

    /**
     * @dev Internal function to create token
     */
    function _createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        uint8 usageType
    ) internal returns (address tokenAddress) {
        require(bytes(name).length > 0, "TokenFactory: name cannot be empty");
        require(bytes(symbol).length > 0, "TokenFactory: symbol cannot be empty");

        // Use CREATE2 for deterministic address across chains
        // Salt includes all parameters to ensure same params = same address across chains
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, name, symbol, decimals, initialSupply, mintable));

        // Deploy new token contract with CREATE2
        SimpleToken token = new SimpleToken{salt: salt}(name, symbol, decimals, initialSupply, mintable, msg.sender);

        tokenAddress = address(token);

        // Track the token
        allTokens.push(tokenAddress);
        userTokens[msg.sender].push(tokenAddress);

        emit TokenCreated(tokenAddress, msg.sender, name, symbol, decimals, initialSupply, mintable, usageType);

        return tokenAddress;
    }

    /**
     * @dev Check premium status and collect fee if needed
     */
    function _checkAndCollectFee(address referrer) internal returns (uint8 usageType) {
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(msg.sender);

        if (isPremium) {
            totalPremiumUsage++;
            return USAGE_PREMIUM;
        }

        // Non-member must pay
        if (msg.value < NON_MEMBER_FEE()) revert InsufficientPayment();

        totalPaidUsage++;

        // Split fee with referrer (50%)
        if (referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = msg.value >> 1; // 50%
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, msg.sender, referralAmount);
            }
        }

        // Transfer remaining to owner
        uint256 ownerAmount = address(this).balance;
        if (ownerAmount > 0) {
            (bool success,) = payable(VAULT()).call{value: ownerAmount}("");
            if (success) {
                emit FeePaid(msg.sender, ownerAmount);
            }
        }

        return USAGE_PAID;
    }

    /**
     * @notice Predict the token address before deployment
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals
     * @param initialSupply Initial supply
     * @param mintable Whether mintable
     * @param owner Token owner (creator)
     * @return predictedAddress The address where the token will be deployed
     */
    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        address owner
    ) external view returns (address predictedAddress) {
        bytes32 salt = keccak256(abi.encodePacked(owner, name, symbol, decimals, initialSupply, mintable));

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(SimpleToken).creationCode,
                        abi.encode(name, symbol, decimals, initialSupply, mintable, owner)
                    )
                )
            )
        );

        predictedAddress = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get total number of tokens created
     */
    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    /**
     * @notice Get number of tokens created by a specific user
     */
    function userTokensLength(address user) external view returns (uint256) {
        return userTokens[user].length;
    }

    /**
     * @notice Get all tokens created by a specific user
     */
    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }

    /**
     * @notice Get token info from token address
     * @param tokenAddress Token contract address
     * @return info TokenInfo struct with all token details
     */
    function getTokenInfo(address tokenAddress) public view returns (TokenInfo memory info) {
        SimpleToken token = SimpleToken(tokenAddress);
        info = TokenInfo({
            tokenAddress: tokenAddress,
            name: token.name(),
            symbol: token.symbol(),
            decimals: token.decimals(),
            totalSupply: token.totalSupply(),
            mintable: token.mintable(),
            owner: token.owner()
        });
    }

    /**
     * @notice Get user tokens with pagination (addresses only)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokens Array of token addresses
     * @return total Total number of tokens for this user
     */
    function getUserTokensPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory tokens, uint256 total)
    {
        total = userTokens[user].length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        tokens = new address[](size);

        for (uint256 i = 0; i < size; i++) {
            tokens[i] = userTokens[user][offset + i];
        }

        return (tokens, total);
    }

    /**
     * @notice Get user tokens with pagination (with full token info)
     * @param user User address
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokenInfos Array of TokenInfo structs
     * @return total Total number of tokens for this user
     */
    function getUserTokensInfoPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory tokenInfos, uint256 total)
    {
        total = userTokens[user].length;

        if (offset >= total) {
            return (new TokenInfo[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        tokenInfos = new TokenInfo[](size);

        for (uint256 i = 0; i < size; i++) {
            tokenInfos[i] = getTokenInfo(userTokens[user][offset + i]);
        }

        return (tokenInfos, total);
    }

    /**
     * @notice Get all tokens created through this factory
     */
    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    /**
     * @notice Get all tokens with pagination (addresses only)
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokens Array of token addresses
     * @return total Total number of tokens
     */
    function getAllTokensPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory tokens, uint256 total)
    {
        total = allTokens.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        tokens = new address[](size);

        for (uint256 i = 0; i < size; i++) {
            tokens[i] = allTokens[offset + i];
        }

        return (tokens, total);
    }

    /**
     * @notice Get all tokens with pagination (with full token info)
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokenInfos Array of TokenInfo structs
     * @return total Total number of tokens
     */
    function getAllTokensInfoPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory tokenInfos, uint256 total)
    {
        total = allTokens.length;

        if (offset >= total) {
            return (new TokenInfo[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        tokenInfos = new TokenInfo[](size);

        for (uint256 i = 0; i < size; i++) {
            tokenInfos[i] = getTokenInfo(allTokens[offset + i]);
        }

        return (tokenInfos, total);
    }
}
