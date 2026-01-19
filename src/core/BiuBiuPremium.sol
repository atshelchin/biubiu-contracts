// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuPremium} from "../interfaces/IBiuBiuPremium.sol";
import {ERC721Base} from "../libraries/ERC721Base.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";
import {Base64} from "../libraries/Base64.sol";
import {Strings} from "../libraries/Strings.sol";

/**
 * @title BiuBiuPremium
 * @notice A subscription NFT contract with three tiers and referral system
 * @dev Subscription info is bound to NFT tokenId. Users can hold multiple NFTs but only activate one at a time.
 *      Inherits ERC721Base for standard NFT functionality.
 */
contract BiuBiuPremium is ERC721Base, IBiuBiuPremium, ReentrancyGuard {
    // ============ Constants ============

    uint256 public constant MONTHLY_PRICE = 0.2 ether;
    uint256 public constant YEARLY_PRICE = 0.4 ether;
    uint256 public constant MONTHLY_DURATION = 30 days;
    uint256 public constant YEARLY_DURATION = 365 days;
    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;

    // ============ State Variables ============

    uint256 private _nextTokenId = 1;
    mapping(uint256 => TokenAttributes) private _tokenAttributes;
    mapping(address => uint256) public activeSubscription;

    // ============ ERC721 Overrides ============

    function name() public pure override returns (string memory) {
        return "BiuBiu Premium";
    }

    function symbol() public pure override returns (string memory) {
        return "BBP";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        uint256 expiry = attrs.expiry;
        bool isActive = expiry > block.timestamp;

        string memory svg = _generateSVG(tokenId, isActive);
        string memory svgBase64 = Base64.encode(bytes(svg));

        string memory json = string(
            abi.encodePacked(
                '{"name":"BiuBiu Premium #',
                Strings.toString(tokenId),
                '","description":"BiuBiu Premium Subscription NFT. Visit https://biubiu.tools for more info.","external_url":"https://biubiu.tools","image":"data:image/svg+xml;base64,',
                svgBase64,
                '","attributes":['
            )
        );

        json = string(
            abi.encodePacked(
                json,
                '{"trait_type":"Status","value":"',
                isActive ? "Active" : "Expired",
                '"},{"trait_type":"Minted At","display_type":"date","value":',
                Strings.toString(attrs.mintedAt),
                '},{"trait_type":"Minted By","value":"',
                Strings.toHexString(attrs.mintedBy),
                '"},{"trait_type":"Renewal Count","display_type":"number","value":',
                Strings.toString(attrs.renewalCount),
                '},{"trait_type":"Expiry","display_type":"date","value":',
                Strings.toString(expiry),
                "}]}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // ============ ERC721 Hooks ============

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        // Handle mint
        if (from == address(0)) {
            if (activeSubscription[to] == 0) {
                activeSubscription[to] = tokenId;
                emit Activated(to, tokenId);
            }
            _tokenAttributes[tokenId] =
                TokenAttributes({mintedAt: block.timestamp, mintedBy: msg.sender, renewalCount: 0, expiry: 0});
        }
        // Handle transfer (not mint or burn)
        else if (to != address(0)) {
            if (activeSubscription[from] == tokenId) {
                activeSubscription[from] = 0;
                emit Deactivated(from, tokenId);
            }
            if (activeSubscription[to] == 0) {
                activeSubscription[to] = tokenId;
                emit Activated(to, tokenId);
            }
        }
    }

    // ============ Subscription ============

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime)
    {
        uint256 activeTokenId = activeSubscription[user];
        if (activeTokenId == 0) return (false, 0, 0);
        expiryTime = _tokenAttributes[activeTokenId].expiry;
        isPremium = expiryTime > block.timestamp;
        remainingTime = isPremium ? expiryTime - block.timestamp : 0;
    }

    function getTokenSubscriptionInfo(uint256 tokenId)
        external
        view
        returns (uint256 expiryTime, bool isExpired, address tokenOwner)
    {
        tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotExists();
        expiryTime = _tokenAttributes[tokenId].expiry;
        isExpired = expiryTime <= block.timestamp;
    }

    function getTokenAttributes(uint256 tokenId)
        external
        view
        returns (uint256 mintedAt, address mintedBy, uint256 renewalCount, uint256 expiry)
    {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        return (attrs.mintedAt, attrs.mintedBy, attrs.renewalCount, attrs.expiry);
    }

    function subscriptionExpiry(uint256 tokenId) external view returns (uint256) {
        return _tokenAttributes[tokenId].expiry;
    }

    function subscribe(SubscriptionTier tier, address referrer, address recipient) external payable nonReentrant {
        address to = recipient == address(0) ? msg.sender : recipient;
        uint256 activeTokenId = activeSubscription[to];

        if (activeTokenId != 0) {
            _renewSubscription(activeTokenId, tier, referrer);
        } else {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            _renewSubscription(tokenId, tier, referrer);
        }
    }

    function subscribeToToken(uint256 tokenId, SubscriptionTier tier, address referrer) external payable nonReentrant {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        _renewSubscription(tokenId, tier, referrer);
    }

    function activate(uint256 tokenId) external {
        if (_owners[tokenId] != msg.sender) revert NotTokenOwner();
        activeSubscription[msg.sender] = tokenId;
        emit Activated(msg.sender, tokenId);
    }

    function _renewSubscription(uint256 tokenId, SubscriptionTier tier, address referrer) private {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        (uint256 price, uint256 duration) = _getTierInfo(tier);
        if (msg.value != price) revert IncorrectPaymentAmount();

        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        uint256 currentExpiry = attrs.expiry;
        uint256 newExpiry = currentExpiry > block.timestamp ? currentExpiry + duration : block.timestamp + duration;
        attrs.expiry = newExpiry;

        unchecked {
            attrs.renewalCount += 1;
        }

        uint256 referralAmount;
        if (referrer != address(0) && referrer != msg.sender) {
            referralAmount = msg.value >> 1;
            // forge-lint: disable-next-line(unchecked-call)
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, referralAmount);
            } else {
                referralAmount = 0;
            }
        }

        // forge-lint: disable-next-line(unchecked-call)
        payable(VAULT).call{value: address(this).balance}("");

        emit Subscribed(msg.sender, tokenId, tier, newExpiry, referrer, referralAmount);
    }

    function _getTierInfo(SubscriptionTier tier) private pure returns (uint256 price, uint256 duration) {
        if (tier == SubscriptionTier.Monthly) {
            return (MONTHLY_PRICE, MONTHLY_DURATION);
        } else {
            return (YEARLY_PRICE, YEARLY_DURATION);
        }
    }

    // ============ Tool Proxy ============

    function callTool(address target, bytes calldata data) external payable nonReentrant returns (bytes memory result) {
        uint256 activeTokenId = activeSubscription[msg.sender];
        if (activeTokenId == 0 || _tokenAttributes[activeTokenId].expiry <= block.timestamp) {
            revert NotPremiumMember();
        }

        if (target == address(this)) revert InvalidTarget();
        if (target == address(0)) revert InvalidTarget();

        bool success;
        (success, result) = target.call{value: msg.value}(data);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert CallFailed();
        }
    }

    receive() external payable {}

    // ============ Internal Helpers ============

    function _generateSVG(uint256 tokenId, bool isActive) private pure returns (string memory) {
        string memory tokenIdStr = Strings.toString(tokenId);

        if (isActive) {
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
}
