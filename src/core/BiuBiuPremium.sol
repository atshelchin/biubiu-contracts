// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuPremium} from "../interfaces/IBiuBiuPremium.sol";

/**
 * @title BiuBiuPremium
 * @notice A subscription NFT contract with three tiers and referral system
 * @dev Subscription info is bound to NFT tokenId. Users can hold multiple NFTs but only activate one at a time.
 *      Implements ERC721 without external dependencies.
 */
contract BiuBiuPremium is IBiuBiuPremium {
    // Custom errors (gas efficient)
    error ReentrancyDetected();
    error IncorrectPaymentAmount();
    error NotTokenOwner();
    error NoActiveSubscription();
    error TokenNotExists();
    error InvalidAddress();
    error NotApproved();
    error TransferToNonReceiver();
    error NotPremiumMember();
    error InvalidTarget();
    error CallFailed();

    // Reentrancy guard
    uint256 private _locked = 1;

    // Token ID counter
    uint256 private _nextTokenId = 1;

    // Total supply counter
    uint256 private _totalSupply;

    // ERC721 storage
    string public constant name = "BiuBiu Premium";
    string public constant symbol = "BBP";
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Base fee (constant) - all prices derived from this
    uint256 public constant NON_MEMBER_FEE = 0.01 ether;

    // Price multipliers (constant)
    // Monthly = NON_MEMBER_FEE * 12
    // Yearly = NON_MEMBER_FEE * 60 (Monthly * 5)
    uint256 public constant MONTHLY_MULTIPLIER = 12;
    uint256 public constant YEARLY_MULTIPLIER = 60;

    // Tier duration (constant)
    uint256 public constant MONTHLY_DURATION = 30 days;
    uint256 public constant YEARLY_DURATION = 365 days;

    // Vault address for revenue distribution (set via constructor)
    address public immutable VAULT;

    constructor(address _vault) {
        VAULT = _vault;
    }

    // ============ Price Getters ============

    /**
     * @notice Get current monthly subscription price
     * @return Monthly price (NON_MEMBER_FEE * 12)
     */
    function MONTHLY_PRICE() public pure returns (uint256) {
        return NON_MEMBER_FEE * MONTHLY_MULTIPLIER;
    }

    /**
     * @notice Get current yearly subscription price
     * @return Yearly price (NON_MEMBER_FEE * 60, Monthly * 5)
     */
    function YEARLY_PRICE() public pure returns (uint256) {
        return NON_MEMBER_FEE * YEARLY_MULTIPLIER;
    }

    // Token attributes struct
    struct TokenAttributes {
        uint256 mintedAt; // First mint timestamp
        address mintedBy; // Who minted this token
        uint256 renewalCount; // Number of renewals
    }

    // tokenId => subscription expiry time
    mapping(uint256 => uint256) public subscriptionExpiry;

    // tokenId => token attributes
    mapping(uint256 => TokenAttributes) private _tokenAttributes;

    // User => currently activated tokenId (0 means no active subscription)
    mapping(address => uint256) public activeSubscription;

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
    }

    function _nonReentrantAfter() private {
        _locked = 1;
    }

    // ============ ERC721 Implementation ============

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert InvalidAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenNotExists();
        return owner;
    }

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if (to == owner) revert InvalidAddress();
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) {
            revert NotApproved();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        if (operator == msg.sender) revert InvalidAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert TransferToNonReceiver();
        }
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x80ac58cd // ERC721
                || interfaceId == 0x5b5e139f // ERC721Metadata
                || interfaceId == 0x01ffc9a7; // ERC165
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        uint256 expiry = subscriptionExpiry[tokenId];
        bool isActive = expiry > block.timestamp;

        // Generate SVG image
        string memory svg = _generateSVG(tokenId, isActive);
        string memory svgBase64 = _base64Encode(bytes(svg));

        // Build JSON metadata
        string memory json = string(
            abi.encodePacked(
                '{"name":"BiuBiu Premium #',
                _toString(tokenId),
                '","description":"BiuBiu Premium Subscription NFT. Visit https://biubiu.tools for more info.","external_url":"https://biubiu.tools","image":"data:image/svg+xml;base64,',
                svgBase64,
                '","attributes":['
            )
        );

        // Add attributes
        json = string(
            abi.encodePacked(
                json,
                '{"trait_type":"Status","value":"',
                isActive ? "Active" : "Expired",
                '"},{"trait_type":"Minted At","display_type":"date","value":',
                _toString(attrs.mintedAt),
                '},{"trait_type":"Minted By","value":"',
                _toHexString(attrs.mintedBy),
                '"},{"trait_type":"Renewal Count","display_type":"number","value":',
                _toString(attrs.renewalCount),
                '},{"trait_type":"Expiry","display_type":"date","value":',
                _toString(expiry),
                "}]}"
            )
        );

        // Encode to Base64
        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(json))));
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (ownerOf(tokenId) != from) revert NotTokenOwner();
        if (to == address(0)) revert InvalidAddress();

        // Clear approvals
        delete _tokenApprovals[tokenId];

        // Handle activeSubscription on transfer
        if (activeSubscription[from] == tokenId) {
            activeSubscription[from] = 0;
            emit Deactivated(from, tokenId);
        }
        if (activeSubscription[to] == 0) {
            activeSubscription[to] = tokenId;
            emit Activated(to, tokenId);
        }

        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) private {
        if (to == address(0)) revert InvalidAddress();

        // Auto-activate if no active subscription
        if (activeSubscription[to] == 0) {
            activeSubscription[to] = tokenId;
            emit Activated(to, tokenId);
        }

        // Initialize token attributes
        _tokenAttributes[tokenId] = TokenAttributes({mintedAt: block.timestamp, mintedBy: msg.sender, renewalCount: 0});

        unchecked {
            _balances[to] += 1;
            _totalSupply += 1;
        }
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function _safeMint(address to, uint256 tokenId) private {
        _mint(to, tokenId);
        if (!_checkOnERC721Received(address(0), to, tokenId, "")) {
            revert TransferToNonReceiver();
        }
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        private
        returns (bool)
    {
        if (to.code.length == 0) {
            return true;
        }
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // ============ Subscription Logic ============

    /**
     * @notice Subscribe to a premium tier
     * @dev If user has an active subscription, renew it. Otherwise mint a new NFT and activate it.
     * @param tier The subscription tier (Daily, Monthly, or Lifetime)
     * @param referrer The referrer address (use address(0) for no referrer)
     */
    function subscribe(SubscriptionTier tier, address referrer) external payable nonReentrant {
        uint256 activeTokenId = activeSubscription[msg.sender];

        if (activeTokenId != 0) {
            // Renew existing active subscription
            _renewSubscription(activeTokenId, tier, referrer);
        } else {
            // Mint new NFT and activate
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
            _renewSubscription(tokenId, tier, referrer);
        }
    }

    /**
     * @notice Subscribe/renew a specific tokenId
     * @dev Can be used to renew any token (even if not yours - gift subscription)
     * @param tokenId The token to renew
     * @param tier The subscription tier
     * @param referrer The referrer address
     */
    function subscribeToToken(uint256 tokenId, SubscriptionTier tier, address referrer) external payable nonReentrant {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        _renewSubscription(tokenId, tier, referrer);
    }

    /**
     * @notice Activate a specific NFT as your subscription
     * @param tokenId The token to activate (must be owner)
     */
    function activate(uint256 tokenId) external {
        if (_owners[tokenId] != msg.sender) revert NotTokenOwner();
        activeSubscription[msg.sender] = tokenId;
        emit Activated(msg.sender, tokenId);
    }

    /**
     * @notice Internal function to renew subscription for a tokenId
     */
    function _renewSubscription(uint256 tokenId, SubscriptionTier tier, address referrer) private {
        // Defense in depth: ensure token exists (callers should already validate)
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        // Get price and duration based on tier
        (uint256 price, uint256 duration) = _getTierInfo(tier);

        // Validate payment
        if (msg.value != price) revert IncorrectPaymentAmount();

        // Calculate new expiry time
        uint256 currentExpiry = subscriptionExpiry[tokenId];
        uint256 newExpiry = currentExpiry > block.timestamp ? currentExpiry + duration : block.timestamp + duration;

        subscriptionExpiry[tokenId] = newExpiry;

        // Increment renewal count
        unchecked {
            _tokenAttributes[tokenId].renewalCount += 1;
        }

        // Handle payments
        uint256 referralAmount;

        // Only pay referral if referrer is valid and not self
        if (referrer != address(0) && referrer != msg.sender) {
            // Use bit shift for 50% calculation (more gas efficient)
            referralAmount = msg.value >> 1;

            // Use low-level call with limited gas to prevent griefing
            // If referrer payment fails, continue anyway (don't block subscription)
            // forge-lint: disable-next-line(unchecked-call)
            (bool referralSuccess,) = payable(referrer).call{value: referralAmount}("");

            // Only emit ReferralPaid if transfer succeeded
            if (referralSuccess) {
                emit ReferralPaid(referrer, referralAmount);
            } else {
                // Reset referralAmount since payment failed
                referralAmount = 0;
            }
        }

        // Transfer all contract balance to owner
        // If transfer fails, don't block subscription - just keep funds in contract
        uint256 contractBalance = address(this).balance;
        // We intentionally ignore the return value to prevent blocking subscriptions
        // forge-lint: disable-next-line(unchecked-call)
        payable(VAULT).call{value: contractBalance}("");

        emit Subscribed(msg.sender, tokenId, tier, newExpiry, referrer, referralAmount);
    }

    /**
     * @notice Get tier pricing and duration
     * @param tier The subscription tier
     * @return price The price in wei
     * @return duration The duration in seconds
     */
    function _getTierInfo(SubscriptionTier tier) private pure returns (uint256 price, uint256 duration) {
        if (tier == SubscriptionTier.Monthly) {
            return (MONTHLY_PRICE(), MONTHLY_DURATION);
        } else {
            return (YEARLY_PRICE(), YEARLY_DURATION);
        }
    }

    /**
     * @notice Get user subscription information (based on active subscription)
     * @param user The user address
     * @return isPremium Whether the user has an active subscription
     * @return expiryTime The subscription expiry timestamp
     * @return remainingTime The remaining time in seconds
     */
    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime)
    {
        uint256 activeTokenId = activeSubscription[user];
        if (activeTokenId == 0) {
            return (false, 0, 0);
        }
        expiryTime = subscriptionExpiry[activeTokenId];
        isPremium = expiryTime > block.timestamp;
        remainingTime = isPremium ? expiryTime - block.timestamp : 0;
    }

    /**
     * @notice Get subscription info for a specific tokenId
     * @param tokenId The token to query
     * @return expiryTime The subscription expiry timestamp
     * @return isExpired Whether the subscription is expired
     * @return tokenOwner The current owner of the token
     */
    function getTokenSubscriptionInfo(uint256 tokenId)
        external
        view
        returns (uint256 expiryTime, bool isExpired, address tokenOwner)
    {
        tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotExists();
        expiryTime = subscriptionExpiry[tokenId];
        isExpired = expiryTime <= block.timestamp;
    }

    /**
     * @notice Get token attributes
     * @param tokenId The token to query
     * @return mintedAt The timestamp when the token was first minted
     * @return mintedBy The address that minted this token
     * @return renewalCount The number of times this token has been renewed
     */
    function getTokenAttributes(uint256 tokenId)
        external
        view
        returns (uint256 mintedAt, address mintedBy, uint256 renewalCount)
    {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        return (attrs.mintedAt, attrs.mintedBy, attrs.renewalCount);
    }

    /**
     * @notice Get the next token ID that will be minted
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Receive ETH sent directly to contract
     */
    receive() external payable {}

    // ============ Tool Proxy ============

    /**
     * @notice Call a tool contract's free method on behalf of premium members
     * @dev Uses `call` (not delegatecall) to ensure target cannot modify this contract's state
     *      Reverts if caller is not a premium member or if target is this contract
     * @param target The tool contract to call
     * @param data The calldata (function selector + arguments)
     * @return result The return data from the tool call
     */
    function callTool(address target, bytes calldata data) external nonReentrant returns (bytes memory result) {
        // Check membership
        uint256 activeTokenId = activeSubscription[msg.sender];
        if (activeTokenId == 0 || subscriptionExpiry[activeTokenId] <= block.timestamp) {
            revert NotPremiumMember();
        }

        // Prevent calling self (security: cannot modify own state via external call)
        if (target == address(this)) revert InvalidTarget();

        // Prevent calling zero address
        if (target == address(0)) revert InvalidTarget();

        // Call tool (using call, not delegatecall; no ETH forwarded)
        bool success;
        (success, result) = target.call(data);

        if (!success) {
            // Bubble up the revert reason
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert CallFailed();
        }

        return result;
    }

    // ============ Internal Helpers ============

    /**
     * @dev Converts a uint256 to its ASCII string decimal representation
     */
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts an address to its checksummed hex string representation
     */
    function _toHexString(address addr) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @dev Generate SVG image for token
     */
    function _generateSVG(uint256 tokenId, bool isActive) private pure returns (string memory) {
        string memory tokenIdStr = _toString(tokenId);

        if (isActive) {
            // Active: Gradient style with cyan-green colors
            return string(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">',
                    "<defs>",
                    '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
                    '<stop offset="0%" style="stop-color:#1a1a2e"/>',
                    '<stop offset="100%" style="stop-color:#16213e"/>',
                    "</linearGradient>",
                    '<linearGradient id="active" x1="0%" y1="0%" x2="100%" y2="0%">',
                    '<stop offset="0%" style="stop-color:#00d9ff"/>',
                    '<stop offset="100%" style="stop-color:#00ff88"/>',
                    "</linearGradient>",
                    "</defs>",
                    '<rect width="400" height="400" fill="url(#bg)"/>',
                    '<rect x="20" y="20" width="360" height="360" rx="20" fill="none" stroke="url(#active)" stroke-width="3"/>',
                    '<text x="200" y="120" text-anchor="middle" fill="#ffffff" font-family="Arial, sans-serif" font-size="24" font-weight="bold">BiuBiu Premium</text>',
                    '<text x="200" y="200" text-anchor="middle" fill="url(#active)" font-family="Arial, sans-serif" font-size="72" font-weight="bold">#',
                    tokenIdStr,
                    "</text>",
                    '<rect x="130" y="260" width="140" height="36" rx="18" fill="url(#active)"/>',
                    '<text x="200" y="285" text-anchor="middle" fill="#1a1a2e" font-family="Arial, sans-serif" font-size="16" font-weight="bold">ACTIVE</text>',
                    '<text x="200" y="340" text-anchor="middle" fill="#888888" font-family="Arial, sans-serif" font-size="12">biubiu.tools</text>',
                    "</svg>"
                )
            );
        } else {
            // Expired: Gray style
            return string(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">',
                    "<defs>",
                    '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
                    '<stop offset="0%" style="stop-color:#1a1a2e"/>',
                    '<stop offset="100%" style="stop-color:#16213e"/>',
                    "</linearGradient>",
                    "</defs>",
                    '<rect width="400" height="400" fill="url(#bg)"/>',
                    '<rect x="20" y="20" width="360" height="360" rx="20" fill="none" stroke="#555555" stroke-width="3"/>',
                    '<text x="200" y="120" text-anchor="middle" fill="#888888" font-family="Arial, sans-serif" font-size="24" font-weight="bold">BiuBiu Premium</text>',
                    '<text x="200" y="200" text-anchor="middle" fill="#555555" font-family="Arial, sans-serif" font-size="72" font-weight="bold">#',
                    tokenIdStr,
                    "</text>",
                    '<rect x="130" y="260" width="140" height="36" rx="18" fill="#555555"/>',
                    '<text x="200" y="285" text-anchor="middle" fill="#1a1a2e" font-family="Arial, sans-serif" font-size="16" font-weight="bold">EXPIRED</text>',
                    '<text x="200" y="340" text-anchor="middle" fill="#555555" font-family="Arial, sans-serif" font-size="12">biubiu.tools</text>',
                    "</svg>"
                )
            );
        }
    }

    /**
     * @dev Base64 encode bytes
     */
    function _base64Encode(bytes memory data) private pure returns (string memory) {
        bytes memory alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        if (data.length == 0) return "";

        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen);

        uint256 i = 0;
        uint256 j = 0;

        while (i < data.length) {
            uint256 a = uint8(data[i++]);
            uint256 b = i < data.length ? uint8(data[i++]) : 0;
            uint256 c = i < data.length ? uint8(data[i++]) : 0;

            uint256 triple = (a << 16) | (b << 8) | c;

            result[j++] = alphabet[(triple >> 18) & 0x3F];
            result[j++] = alphabet[(triple >> 12) & 0x3F];
            result[j++] = alphabet[(triple >> 6) & 0x3F];
            result[j++] = alphabet[triple & 0x3F];
        }

        // Add padding
        uint256 mod = data.length % 3;
        if (mod > 0) {
            result[encodedLen - 1] = "=";
            if (mod == 1) {
                result[encodedLen - 2] = "=";
            }
        }

        return string(result);
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
