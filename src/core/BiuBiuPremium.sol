// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuPremium} from "../interfaces/IBiuBiuPremium.sol";
import {IERC721Receiver} from "../interfaces/IERC721Receiver.sol";
import {Base64} from "../libraries/Base64.sol";
import {Strings} from "../libraries/Strings.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";

/**
 * @title BiuBiuPremium
 * @notice A subscription NFT contract with three tiers and referral system
 * @dev Subscription info is bound to NFT tokenId. Users can hold multiple NFTs but only activate one at a time.
 *      Implements ERC721 without external dependencies.
 */
contract BiuBiuPremium is IBiuBiuPremium, ReentrancyGuard {
    // ============ Constants & Immutables ============

    string public constant name = "BiuBiu Premium";
    string public constant symbol = "BBP";
    uint256 public constant NON_MEMBER_FEE = 0.01 ether;
    uint256 public constant MONTHLY_PRICE = 0.2 ether;
    uint256 public constant YEARLY_PRICE = 0.6 ether;
    uint256 public constant MONTHLY_DURATION = 30 days;
    uint256 public constant YEARLY_DURATION = 365 days;
    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;

    // ============ State Variables ============

    uint256 private _nextTokenId = 1;
    uint256 private _totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(uint256 => uint256) public subscriptionExpiry;
    mapping(uint256 => TokenAttributes) private _tokenAttributes;
    mapping(address => uint256) public activeSubscription;

    // ============ ERC721 ============

    // --- pure ---

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x5b5e139f ||
            interfaceId == 0x01ffc9a7;
    }

    // --- view ---

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

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        uint256 expiry = subscriptionExpiry[tokenId];
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

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(bytes(json))
                )
            );
    }

    // --- state-modifying ---

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if (to == owner) revert InvalidAddress();
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) {
            revert NotApproved();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        if (operator == msg.sender) revert InvalidAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert TransferToNonReceiver();
        }
    }

    // --- private ---

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) private view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (ownerOf(tokenId) != from) revert NotTokenOwner();
        if (to == address(0)) revert InvalidAddress();

        delete _tokenApprovals[tokenId];

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

        if (activeSubscription[to] == 0) {
            activeSubscription[to] = tokenId;
            emit Activated(to, tokenId);
        }

        _tokenAttributes[tokenId] = TokenAttributes({
            mintedAt: block.timestamp,
            mintedBy: msg.sender,
            renewalCount: 0
        });

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

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length == 0) return true;
        try
            IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            )
        returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // ============ Subscription ============

    // --- view ---

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function getSubscriptionInfo(
        address user
    )
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime)
    {
        uint256 activeTokenId = activeSubscription[user];
        if (activeTokenId == 0) return (false, 0, 0);
        expiryTime = subscriptionExpiry[activeTokenId];
        isPremium = expiryTime > block.timestamp;
        remainingTime = isPremium ? expiryTime - block.timestamp : 0;
    }

    function getTokenSubscriptionInfo(
        uint256 tokenId
    )
        external
        view
        returns (uint256 expiryTime, bool isExpired, address tokenOwner)
    {
        tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotExists();
        expiryTime = subscriptionExpiry[tokenId];
        isExpired = expiryTime <= block.timestamp;
    }

    function getTokenAttributes(
        uint256 tokenId
    )
        external
        view
        returns (uint256 mintedAt, address mintedBy, uint256 renewalCount)
    {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        TokenAttributes storage attrs = _tokenAttributes[tokenId];
        return (attrs.mintedAt, attrs.mintedBy, attrs.renewalCount);
    }

    // --- state-modifying ---

    function subscribe(
        SubscriptionTier tier,
        address referrer
    ) external payable nonReentrant {
        uint256 activeTokenId = activeSubscription[msg.sender];

        if (activeTokenId != 0) {
            _renewSubscription(activeTokenId, tier, referrer);
        } else {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
            _renewSubscription(tokenId, tier, referrer);
        }
    }

    function subscribeToToken(
        uint256 tokenId,
        SubscriptionTier tier,
        address referrer
    ) external payable nonReentrant {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        _renewSubscription(tokenId, tier, referrer);
    }

    function activate(uint256 tokenId) external {
        if (_owners[tokenId] != msg.sender) revert NotTokenOwner();
        activeSubscription[msg.sender] = tokenId;
        emit Activated(msg.sender, tokenId);
    }

    // --- private ---

    function _renewSubscription(
        uint256 tokenId,
        SubscriptionTier tier,
        address referrer
    ) private {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();

        (uint256 price, uint256 duration) = _getTierInfo(tier);
        if (msg.value != price) revert IncorrectPaymentAmount();

        uint256 currentExpiry = subscriptionExpiry[tokenId];
        uint256 newExpiry = currentExpiry > block.timestamp
            ? currentExpiry + duration
            : block.timestamp + duration;
        subscriptionExpiry[tokenId] = newExpiry;

        unchecked {
            _tokenAttributes[tokenId].renewalCount += 1;
        }

        uint256 referralAmount;
        if (referrer != address(0) && referrer != msg.sender) {
            referralAmount = msg.value >> 1;
            // forge-lint: disable-next-line(unchecked-call)
            (bool success, ) = payable(referrer).call{value: referralAmount}(
                ""
            );
            if (success) {
                emit ReferralPaid(referrer, referralAmount);
            } else {
                referralAmount = 0;
            }
        }

        // forge-lint: disable-next-line(unchecked-call)
        payable(VAULT).call{value: address(this).balance}("");

        emit Subscribed(
            msg.sender,
            tokenId,
            tier,
            newExpiry,
            referrer,
            referralAmount
        );
    }

    function _getTierInfo(
        SubscriptionTier tier
    ) private pure returns (uint256 price, uint256 duration) {
        if (tier == SubscriptionTier.Monthly) {
            return (MONTHLY_PRICE, MONTHLY_DURATION);
        } else {
            return (YEARLY_PRICE, YEARLY_DURATION);
        }
    }

    // ============ Tool Proxy ============

    function callTool(
        address target,
        bytes calldata data
    ) external nonReentrant returns (bytes memory result) {
        uint256 activeTokenId = activeSubscription[msg.sender];
        if (
            activeTokenId == 0 ||
            subscriptionExpiry[activeTokenId] <= block.timestamp
        ) {
            revert NotPremiumMember();
        }

        if (target == address(this)) revert InvalidTarget();
        if (target == address(0)) revert InvalidTarget();

        bool success;
        (success, result) = target.call(data);

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

    function _generateSVG(
        uint256 tokenId,
        bool isActive
    ) private pure returns (string memory) {
        string memory tokenIdStr = Strings.toString(tokenId);

        if (isActive) {
            return
                string(
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
            return
                string(
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
