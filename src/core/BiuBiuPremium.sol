// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuPremium} from "../interfaces/IBiuBiuPremium.sol";
import {ERC721Base} from "../libraries/ERC721Base.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";
import {Base64} from "../libraries/Base64.sol";
import {Strings} from "../libraries/Strings.sol";

/**
 * @title BiuBiuPremium
 * @notice A subscription NFT contract with two tiers (Monthly/Yearly), referral system,
 *         source/tool tracking, and EIP-712 + EIP-1271 promo code discounts
 * @dev Subscription info is bound to NFT tokenId. Users can hold multiple NFTs but only activate one at a time.
 *      Inherits ERC721Base for standard NFT functionality.
 */
contract BiuBiuPremium is ERC721Base, IBiuBiuPremium, ReentrancyGuard {
    // ============ Constants ============

    uint256 public constant MONTHLY_PRICE = 0.02 ether;
    uint256 public constant YEARLY_PRICE = 0.1 ether;
    uint256 public constant MONTHLY_DURATION = 30 days;
    uint256 public constant YEARLY_DURATION = 365 days;

    bytes4 private constant _EIP1271_MAGIC = 0x1626ba7e;

    bytes32 public constant PROMO_TYPEHASH = keccak256(
        "PromoCode(uint256 discountBps,uint256 expiry,uint256 maxUses,bool singleUse,uint256[] validChainIds)"
    );

    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;

    // ============ Immutables ============

    bytes32 public immutable DOMAIN_SEPARATOR;

    // ============ State Variables ============

    uint256 private _nextTokenId = 1;
    mapping(uint256 => TokenAttributes) private _tokenAttributes;
    mapping(address => uint256) public activeSubscription;

    // ============ Tracking Stats ============

    mapping(bytes32 => uint256) public sourceSubscribeCount;
    mapping(bytes32 => uint256) public toolSubscribeCount;
    mapping(bytes32 => uint256) public sourceRevenue;
    mapping(bytes32 => uint256) public toolRevenue;

    // ============ Promo Code State ============

    mapping(bytes32 => uint256) public promoCodeUsedCount;
    mapping(bytes32 => mapping(address => bool)) public promoCodeUsedBy;

    // ============ Constructor ============

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version)"),
                keccak256("BiuBiuPremium"),
                keccak256("1")
            )
        );
    }

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

        string memory svg = _generateSVG(tokenId, isActive, attrs.mintedAt);
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

    function subscribe(
        SubscriptionTier tier,
        address referrer,
        address recipient,
        string calldata source,
        string calldata toolId,
        bytes calldata promoCode
    ) external payable nonReentrant {
        address to = recipient == address(0) ? msg.sender : recipient;
        uint256 activeTokenId = activeSubscription[to];

        if (activeTokenId != 0) {
            _renewSubscription(activeTokenId, tier, referrer, source, toolId, promoCode);
        } else {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            _renewSubscription(tokenId, tier, referrer, source, toolId, promoCode);
        }
    }

    function subscribeToToken(
        uint256 tokenId,
        SubscriptionTier tier,
        address referrer,
        string calldata source,
        string calldata toolId,
        bytes calldata promoCode
    ) external payable nonReentrant {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        _renewSubscription(tokenId, tier, referrer, source, toolId, promoCode);
    }

    function activate(uint256 tokenId) external {
        if (_owners[tokenId] != msg.sender) revert NotTokenOwner();
        activeSubscription[msg.sender] = tokenId;
        emit Activated(msg.sender, tokenId);
    }

    function _renewSubscription(
        uint256 tokenId,
        SubscriptionTier tier,
        address referrer,
        string calldata source,
        string calldata toolId,
        bytes calldata promoCode
    ) private {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        (uint256 basePrice, uint256 duration) = _getTierInfo(tier);

        // Apply promo code discount if provided
        uint256 price = basePrice;
        bytes32 promoId;
        uint256 discountBps;
        if (promoCode.length > 0) {
            (price, promoId, discountBps) = _applyPromoCode(promoCode, basePrice);
        }

        if (msg.value != price) revert IncorrectPaymentAmount();

        // Update subscription expiry
        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        uint256 currentExpiry = attrs.expiry;
        uint256 newExpiry = currentExpiry > block.timestamp ? currentExpiry + duration : block.timestamp + duration;
        attrs.expiry = newExpiry;

        unchecked {
            attrs.renewalCount += 1;
        }

        // Referral split (50% of actual paid amount)
        uint256 referralAmount;
        if (referrer != address(0) && referrer != msg.sender) {
            referralAmount = price >> 1;
            // forge-lint: disable-next-line(unchecked-call)
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, referralAmount);
            } else {
                referralAmount = 0;
            }
        }

        // Sweep remaining balance to VAULT
        // forge-lint: disable-next-line(unchecked-call)
        payable(VAULT).call{value: address(this).balance}("");

        // Update tracking stats
        _updateTrackingStats(source, toolId, price);

        emit Subscribed(msg.sender, tokenId, tier, newExpiry, referrer, referralAmount, price, source, toolId, promoId, discountBps);
    }

    function _getTierInfo(SubscriptionTier tier) private pure returns (uint256 price, uint256 duration) {
        if (tier == SubscriptionTier.Monthly) {
            return (MONTHLY_PRICE, MONTHLY_DURATION);
        } else {
            return (YEARLY_PRICE, YEARLY_DURATION);
        }
    }

    // ============ Promo Code Verification (EIP-712 + EIP-1271) ============

    function _applyPromoCode(bytes calldata promoCode, uint256 basePrice)
        private
        returns (uint256 discountedPrice, bytes32 promoId_, uint256 discountBps_)
    {
        // Decode promo code: (discountBps, expiry, maxUses, singleUse, validChainIds, signature)
        (
            uint256 discountBps,
            uint256 expiry,
            uint256 maxUses,
            bool singleUse,
            uint256[] memory validChainIds,
            bytes memory signature
        ) = abi.decode(promoCode, (uint256, uint256, uint256, bool, uint256[], bytes));

        if (discountBps == 0 || discountBps >= 10000) revert InvalidDiscountBps();

        // Compute EIP-712 struct hash (also serves as promoId)
        bytes32 structHash = keccak256(
            abi.encode(PROMO_TYPEHASH, discountBps, expiry, maxUses, singleUse, keccak256(abi.encodePacked(validChainIds)))
        );

        // Compute EIP-712 digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // EIP-1271 verification: VAULT must have code deployed on this chain
        if (VAULT.code.length == 0) revert PromoCodeNotAvailable();

        // Call isValidSignature on VAULT (Safe wallet)
        // forge-lint: disable-next-line(unchecked-call)
        (bool success, bytes memory returnData) =
            VAULT.staticcall(abi.encodeWithSelector(_EIP1271_MAGIC, digest, signature));

        if (!success || returnData.length < 32) revert InvalidPromoCode();

        bytes4 magicValue = abi.decode(returnData, (bytes4));
        if (magicValue != _EIP1271_MAGIC) revert InvalidPromoCode();

        // Check expiry
        if (expiry != 0 && block.timestamp > expiry) revert PromoCodeExpired();

        // Check chain validity
        if (validChainIds.length > 0) {
            bool chainValid;
            for (uint256 i; i < validChainIds.length; ++i) {
                if (validChainIds[i] == block.chainid) {
                    chainValid = true;
                    break;
                }
            }
            if (!chainValid) revert PromoCodeChainNotValid();
        }

        // Check max uses
        bytes32 promoId = structHash;
        if (maxUses != 0 && promoCodeUsedCount[promoId] >= maxUses) revert PromoCodeMaxUsesReached();

        // Check per-address usage
        if (singleUse && promoCodeUsedBy[promoId][msg.sender]) revert PromoCodeAlreadyUsed();

        // Update usage tracking
        promoCodeUsedCount[promoId] += 1;
        if (singleUse) {
            promoCodeUsedBy[promoId][msg.sender] = true;
        }

        // Calculate discounted price
        discountedPrice = basePrice * (10000 - discountBps) / 10000;
        promoId_ = promoId;
        discountBps_ = discountBps;

        emit PromoCodeUsed(promoId, msg.sender, discountBps, discountedPrice);
    }

    // ============ Tracking Stats ============

    function _updateTrackingStats(string calldata source, string calldata toolId, uint256 paidAmount) private {
        if (bytes(source).length > 0) {
            bytes32 sourceHash = keccak256(bytes(source));
            unchecked {
                sourceSubscribeCount[sourceHash] += 1;
            }
            sourceRevenue[sourceHash] += paidAmount;
        }
        if (bytes(toolId).length > 0) {
            bytes32 toolHash = keccak256(bytes(toolId));
            unchecked {
                toolSubscribeCount[toolHash] += 1;
            }
            toolRevenue[toolHash] += paidAmount;
        }
    }

    // ============ View Functions ============

    function getDiscountedPrice(SubscriptionTier tier, uint256 discountBps) external pure returns (uint256) {
        (uint256 basePrice,) = _getTierInfo(tier);
        if (discountBps == 0 || discountBps >= 10000) return basePrice;
        return basePrice * (10000 - discountBps) / 10000;
    }

    /// @notice Validate a promo code without executing. Returns decoded parameters and validity status.
    function validatePromoCode(bytes calldata promoCode, address user)
        external
        view
        returns (
            bool isValid,
            uint256 discountBps,
            uint256 expiry,
            uint256 maxUses,
            bool singleUse,
            uint256[] memory validChainIds,
            uint256 usedCount,
            bool usedByUser,
            string memory reason
        )
    {
        // Decode
        bytes memory signature;
        (discountBps, expiry, maxUses, singleUse, validChainIds, signature) =
            abi.decode(promoCode, (uint256, uint256, uint256, bool, uint256[], bytes));

        // Check discount range
        if (discountBps == 0 || discountBps >= 10000) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "invalid discount bps");
        }

        // Compute EIP-712 digest
        bytes32 structHash = keccak256(
            abi.encode(PROMO_TYPEHASH, discountBps, expiry, maxUses, singleUse, keccak256(abi.encodePacked(validChainIds)))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // EIP-1271 signature verification
        if (VAULT.code.length == 0) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "vault not deployed on this chain");
        }

        (bool success, bytes memory returnData) =
            VAULT.staticcall(abi.encodeWithSelector(_EIP1271_MAGIC, digest, signature));
        if (!success || returnData.length < 32) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "invalid signature");
        }
        bytes4 magicValue = abi.decode(returnData, (bytes4));
        if (magicValue != _EIP1271_MAGIC) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "invalid signature");
        }

        // Check expiry
        if (expiry != 0 && block.timestamp > expiry) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "expired");
        }

        // Check chain validity
        if (validChainIds.length > 0) {
            bool chainValid;
            for (uint256 i; i < validChainIds.length; ++i) {
                if (validChainIds[i] == block.chainid) {
                    chainValid = true;
                    break;
                }
            }
            if (!chainValid) {
                return (false, discountBps, expiry, maxUses, singleUse, validChainIds, 0, false, "chain not valid");
            }
        }

        // Check usage
        bytes32 promoId = structHash;
        usedCount = promoCodeUsedCount[promoId];
        usedByUser = promoCodeUsedBy[promoId][user];

        if (maxUses != 0 && usedCount >= maxUses) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, usedCount, usedByUser, "max uses reached");
        }
        if (singleUse && usedByUser) {
            return (false, discountBps, expiry, maxUses, singleUse, validChainIds, usedCount, usedByUser, "already used by user");
        }

        isValid = true;
        reason = "valid";
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

    function _generateSVG(uint256 tokenId, bool isActive, uint256 mintedAt) private pure returns (string memory) {
        string memory tokenIdStr = Strings.toString(tokenId);
        string memory dateStr = _formatDate(mintedAt);
        uint256 idLen = bytes(tokenIdStr).length;
        string memory fontSize;
        if (idLen <= 2) fontSize = "72";
        else if (idLen <= 4) fontSize = "48";
        else if (idLen <= 6) fontSize = "36";
        else if (idLen <= 9) fontSize = "26";
        else fontSize = "20";

        if (isActive) {
            return _generateActiveSVG(tokenIdStr, dateStr, fontSize);
        } else {
            return _generateExpiredSVG(tokenIdStr, dateStr, fontSize);
        }
    }

    function _generateActiveSVG(string memory tokenIdStr, string memory dateStr, string memory fontSize)
        private
        pure
        returns (string memory)
    {
        // Part 1: defs — deep purple bg + gold gradient
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560">',
                "<defs>",
                '<radialGradient id="bg" cx="30%" cy="25%" r="80%">',
                '<stop offset="0%" stop-color="#1a1040"/>',
                '<stop offset="100%" stop-color="#0a0a12"/>',
                "</radialGradient>",
                '<linearGradient id="gd" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" stop-color="#f7d06b"/>',
                '<stop offset="50%" stop-color="#c9952e"/>'
            )
        );

        // Part 2: close gradient + glow filter + close defs
        svg = string(
            abi.encodePacked(
                svg,
                '<stop offset="100%" stop-color="#f7d06b"/>',
                "</linearGradient>",
                '<filter id="gl"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                "</defs>"
            )
        );

        // Part 3: background + gold double border + chain-link logo
        svg = string(
            abi.encodePacked(
                svg,
                '<rect width="400" height="560" fill="url(#bg)"/>',
                '<rect x="10" y="10" width="380" height="540" rx="16" fill="none" stroke="url(#gd)" stroke-width="0.6" opacity="0.3"/>',
                '<rect x="18" y="18" width="364" height="524" rx="12" fill="none" stroke="url(#gd)" stroke-width="1.5"/>',
                '<g transform="translate(183,50)" fill="none" stroke="url(#gd)" stroke-width="2.2" opacity="0.85" filter="url(#gl)">',
                '<rect width="22" height="22" rx="5.5"/>',
                '<rect x="12" y="12" width="22" height="22" rx="5.5"/>',
                "</g>"
            )
        );

        // Part 4: PREMIUM label + divider + token ID
        svg = string(
            abi.encodePacked(
                svg,
                '<text x="200" y="115" text-anchor="middle" fill="url(#gd)" font-family="Georgia,serif" font-size="16" letter-spacing="8">PREMIUM</text>',
                '<line x1="100" y1="138" x2="300" y2="138" stroke="url(#gd)" stroke-width="0.5" opacity="0.3"/>',
                '<text x="200" y="300" text-anchor="middle" fill="#fff" font-family="Georgia,serif" font-size="',
                fontSize,
                '" font-weight="bold" filter="url(#gl)">#',
                tokenIdStr,
                "</text>"
            )
        );

        // Part 5: divider + date + footer + close
        svg = string(
            abi.encodePacked(
                svg,
                '<line x1="100" y1="340" x2="300" y2="340" stroke="url(#gd)" stroke-width="0.5" opacity="0.3"/>',
                '<text x="200" y="385" text-anchor="middle" fill="url(#gd)" font-family="Georgia,serif" font-size="13" letter-spacing="4">',
                dateStr,
                "</text>",
                '<text x="200" y="510" text-anchor="middle" fill="#f7d06b" font-family="Georgia,serif" font-size="11" opacity="0.4" letter-spacing="3">biubiu.tools</text>',
                "</svg>"
            )
        );

        return svg;
    }

    function _generateExpiredSVG(string memory tokenIdStr, string memory dateStr, string memory fontSize)
        private
        pure
        returns (string memory)
    {
        // Part 1: defs + background + outer border
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560">',
                "<defs>",
                '<radialGradient id="bg" cx="30%" cy="25%" r="80%">',
                '<stop offset="0%" stop-color="#111113"/>',
                '<stop offset="100%" stop-color="#090909"/>',
                "</radialGradient>",
                "</defs>",
                '<rect width="400" height="560" fill="url(#bg)"/>',
                '<rect x="10" y="10" width="380" height="540" rx="16" fill="none" stroke="#3a3a3a" stroke-width="0.6" opacity="0.3"/>'
            )
        );

        // Part 2: inner border + chain-link logo (gray) + PREMIUM + divider
        svg = string(
            abi.encodePacked(
                svg,
                '<rect x="18" y="18" width="364" height="524" rx="12" fill="none" stroke="#3a3a3a" stroke-width="1.5"/>',
                '<g transform="translate(183,50)" fill="none" stroke="#3a3a3a" stroke-width="2.2" opacity="0.5">',
                '<rect width="22" height="22" rx="5.5"/>',
                '<rect x="12" y="12" width="22" height="22" rx="5.5"/>',
                "</g>",
                '<text x="200" y="115" text-anchor="middle" fill="#4a4a4a" font-family="Georgia,serif" font-size="16" letter-spacing="8">PREMIUM</text>',
                '<line x1="100" y1="138" x2="300" y2="138" stroke="#3a3a3a" stroke-width="0.5" opacity="0.3"/>'
            )
        );

        // Part 3: token ID + divider + EXPIRED
        svg = string(
            abi.encodePacked(
                svg,
                '<text x="200" y="300" text-anchor="middle" fill="#3a3a3a" font-family="Georgia,serif" font-size="',
                fontSize,
                '" font-weight="bold">#',
                tokenIdStr,
                "</text>",
                '<line x1="100" y1="340" x2="300" y2="340" stroke="#3a3a3a" stroke-width="0.5" opacity="0.3"/>',
                '<text x="200" y="378" text-anchor="middle" fill="#4a4a4a" font-family="Georgia,serif" font-size="13" letter-spacing="6">EXPIRED</text>'
            )
        );

        // Part 4: date + footer + close
        svg = string(
            abi.encodePacked(
                svg,
                '<text x="200" y="408" text-anchor="middle" fill="#3a3a3a" font-family="Georgia,serif" font-size="11" letter-spacing="3">',
                dateStr,
                "</text>",
                '<text x="200" y="510" text-anchor="middle" fill="#3a3a3a" font-family="Georgia,serif" font-size="11" opacity="0.4" letter-spacing="3">biubiu.tools</text>',
                "</svg>"
            )
        );

        return svg;
    }

    function _formatDate(uint256 timestamp) private pure returns (string memory) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 d = doy - (153 * mp + 2) / 5 + 1;
        uint256 m = mp < 10 ? mp + 3 : mp - 9;
        if (m <= 2) y += 1;
        return string(
            abi.encodePacked(
                Strings.toString(y),
                ".",
                m < 10 ? "0" : "",
                Strings.toString(m),
                ".",
                d < 10 ? "0" : "",
                Strings.toString(d)
            )
        );
    }
}
