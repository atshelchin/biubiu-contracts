// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IKnockCard} from "./interfaces/IKnockCard.sol";

/// @title KnockCardMetadata - On-chain SVG metadata for Knock Cards
/// @notice Generates dynamic SVG reputation cards
contract KnockCardMetadata {
    // Reputation levels
    string[4] internal LEVELS = ["Newcomer", "Active", "Trusted", "Elite"];

    // [primary, secondary, accent, glow]
    string[4][4] internal COLORS = [
        ["#10b981", "#34d399", "#6ee7b7", "#a7f3d0"], // Newcomer - Green
        ["#3b82f6", "#60a5fa", "#93c5fd", "#bfdbfe"], // Active - Blue
        ["#8b5cf6", "#a78bfa", "#c4b5fd", "#ddd6fe"], // Trusted - Purple
        ["#f59e0b", "#fbbf24", "#fcd34d", "#fde68a"] // Elite - Gold
    ];

    // Background gradients [start, end]
    string[2][4] internal BG = [
        ["#064e3b", "#059669"], // Green
        ["#1e3a5f", "#2563eb"], // Blue
        ["#4c1d95", "#7c3aed"], // Purple
        ["#78350f", "#b45309"] // Gold
    ];

    IKnockCard public immutable knockCard;

    constructor(address _knockCard) {
        knockCard = IKnockCard(_knockCard);
    }

    /// @notice Generate full metadata JSON for a card
    function generateMetadata(address owner) external view returns (string memory) {
        IKnockCard.Card memory card = knockCard.getCard(owner);
        uint8 level = _getLevel(card.knocksSent, card.knocksAccepted);

        string memory svg = generateSVG(owner);
        string memory attrs = _attributes(card, level);

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                _b64(
                    bytes(
                        string(
                            abi.encodePacked(
                                '{"name":"Knock Card: ',
                                bytes(card.nickname).length > 0 ? card.nickname : _addressToString(owner),
                                '","description":"On-chain reputation card for Knock Protocol. This SBT represents your identity and reputation in the attention market.","image":"data:image/svg+xml;base64,',
                                _b64(bytes(svg)),
                                '","attributes":',
                                attrs,
                                "}"
                            )
                        )
                    )
                )
            )
        );
    }

    /// @notice Generate SVG image for a card
    function generateSVG(address owner) public view returns (string memory) {
        IKnockCard.Card memory card = knockCard.getCard(owner);
        uint8 level = _getLevel(card.knocksSent, card.knocksAccepted);
        string[4] memory c = COLORS[level];
        string[2] memory bg = BG[level];

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">',
                _defs(c, bg, level),
                '<rect width="400" height="600" fill="url(#bg)"/>',
                _frame(c, level),
                _levelBadge(level, c),
                _nickname(card.nickname, owner, c),
                _bio(card.bio, c),
                _reputation(
                    card.twitter,
                    card.github,
                    card.website,
                    card.ethReceived,
                    card.knocksSent,
                    card.knocksAccepted,
                    card.knocksRejected,
                    c
                ),
                _footer(level, c),
                "</svg>"
            )
        );
    }

    // ============ Internal SVG Components ============

    function _defs(string[4] memory c, string[2] memory bg, uint8 level) internal pure returns (string memory) {
        string memory animation = level >= 3
            ? "<style>@keyframes glow{0%,100%{filter:drop-shadow(0 0 8px rgba(251,191,36,0.6))}50%{filter:drop-shadow(0 0 16px rgba(251,191,36,0.9))}}.elite{animation:glow 2s infinite}</style>"
            : (level >= 2
                    ? "<style>@keyframes pulse{0%,100%{opacity:0.8}50%{opacity:1}}.pulse{animation:pulse 3s infinite}</style>"
                    : "");

        return string(
            abi.encodePacked(
                "<defs>",
                '<linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" stop-color="',
                bg[0],
                '"/>',
                '<stop offset="100%" stop-color="',
                bg[1],
                '"/>',
                "</linearGradient>",
                '<linearGradient id="bar" x1="0%" y1="0%" x2="100%" y2="0%">',
                '<stop offset="0%" stop-color="',
                c[1],
                '"/>',
                '<stop offset="100%" stop-color="',
                c[2],
                '"/>',
                "</linearGradient>",
                "</defs>",
                animation
            )
        );
    }

    function _frame(string[4] memory c, uint8 level) internal pure returns (string memory) {
        string memory cls = level >= 3 ? ' class="elite"' : (level >= 2 ? ' class="pulse"' : "");
        return string(
            abi.encodePacked(
                "<g",
                cls,
                ">",
                '<rect x="15" y="15" width="370" height="570" rx="20" fill="none" stroke="',
                c[1],
                '" stroke-width="2" stroke-opacity="0.8"/>',
                '<rect x="25" y="25" width="350" height="550" rx="15" fill="none" stroke="',
                c[2],
                '" stroke-opacity="0.3"/>',
                "</g>"
            )
        );
    }

    function _nickname(string memory name, address owner, string[4] memory c) internal pure returns (string memory) {
        string memory displayName = bytes(name).length > 0 ? _toUpper(name) : _shortenAddress(owner);
        uint256 charLen = _utf8Length(displayName);

        // If nickname is short enough, single line (leave space for stamp)
        if (charLen <= 10) {
            return string(
                abi.encodePacked(
                    '<text x="200" y="80" font-family="Arial,sans-serif" font-size="24" fill="',
                    c[3],
                    '" text-anchor="middle" font-weight="bold" letter-spacing="2">',
                    displayName,
                    "</text>"
                )
            );
        }

        // Long nickname: split into two lines (using character count, not bytes)
        string memory line1 = _truncateUtf8(displayName, 10);
        string memory line2 = _substringUtf8(displayName, 10, charLen > 20 ? 20 : charLen);

        return string(
            abi.encodePacked(
                '<text x="200" y="65" font-family="Arial,sans-serif" font-size="20" fill="',
                c[3],
                '" text-anchor="middle" font-weight="bold" letter-spacing="2">',
                line1,
                '</text><text x="200" y="90" font-family="Arial,sans-serif" font-size="20" fill="',
                c[3],
                '" text-anchor="middle" font-weight="bold" letter-spacing="2">',
                line2,
                "</text>"
            )
        );
    }

    function _bio(string memory bio, string[4] memory c) internal pure returns (string memory) {
        if (bytes(bio).length == 0) {
            return "";
        }

        uint256 charLen = _utf8Length(bio);

        // Short bio: single line
        if (charLen <= 35) {
            return string(
                abi.encodePacked(
                    '<text x="200" y="130" font-family="Arial,sans-serif" font-size="12" fill="',
                    c[2],
                    '" text-anchor="middle" opacity="0.9">',
                    bio,
                    "</text>"
                )
            );
        }

        // Long bio: split into two lines (using character count, not bytes)
        string memory line1 = _truncateUtf8(bio, 35);
        string memory line2 = charLen > 70
            ? string(abi.encodePacked(_substringUtf8(bio, 35, 67), "..."))
            : _substringUtf8(bio, 35, charLen);

        return string(
            abi.encodePacked(
                '<text x="200" y="122" font-family="Arial,sans-serif" font-size="11" fill="',
                c[2],
                '" text-anchor="middle" opacity="0.9">',
                line1,
                '</text><text x="200" y="138" font-family="Arial,sans-serif" font-size="11" fill="',
                c[2],
                '" text-anchor="middle" opacity="0.9">',
                line2,
                "</text>"
            )
        );
    }

    function _reputation(
        string memory twitter,
        string memory github,
        string memory website,
        uint256 ethReceived,
        uint256 sent,
        uint256 accepted,
        uint256 rejected,
        string[4] memory c
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _reputationHeader(c),
                _reputationStats(ethReceived, sent, accepted, rejected, c),
                _socialSection(twitter, github, website, c)
            )
        );
    }

    function _reputationHeader(string[4] memory c) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<line x1="60" y1="170" x2="340" y2="170" stroke="',
                c[2],
                '" stroke-opacity="0.3"/>',
                '<text x="200" y="200" font-family="Arial,sans-serif" font-size="14" fill="',
                c[3],
                '" text-anchor="middle" font-weight="bold" letter-spacing="1">REPUTATION</text>'
            )
        );
    }

    function _reputationStats(uint256 ethReceived, uint256 sent, uint256 accepted, uint256 rejected, string[4] memory c)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                _dataRow(225, "Earned", _formatNative(ethReceived), c, true),
                _dataRow(261, "Sent", _ts(sent), c, true),
                _dataRow(297, "Accepted", _ts(accepted), c, true),
                _dataRow(333, "Rejected", _ts(rejected), c, true)
            )
        );
    }

    function _socialSection(string memory twitter, string memory github, string memory website, string[4] memory c)
        internal
        pure
        returns (string memory)
    {
        if (bytes(twitter).length == 0 && bytes(github).length == 0 && bytes(website).length == 0) {
            return "";
        }

        // SOCIAL section starts after Rejected row (y=333+28=361, add spacing)
        string memory result = string(
            abi.encodePacked(
                '<line x1="60" y1="386" x2="340" y2="386" stroke="',
                c[2],
                '" stroke-opacity="0.3"/>',
                '<text x="200" y="416" font-family="Arial,sans-serif" font-size="14" fill="',
                c[3],
                '" text-anchor="middle" font-weight="bold" letter-spacing="1">SOCIAL</text>'
            )
        );

        uint256 y = 441;
        if (bytes(twitter).length > 0) {
            result = string(abi.encodePacked(result, _dataRow(y, "X", twitter, c, false)));
            y += 36;
        }
        if (bytes(github).length > 0) {
            result = string(abi.encodePacked(result, _dataRow(y, "GitHub", github, c, false)));
            y += 36;
        }
        if (bytes(website).length > 0) {
            result = string(abi.encodePacked(result, _dataRow(y, "Web", _stripProtocol(website), c, false)));
        }

        return result;
    }

    function _dataRow(uint256 y, string memory label, string memory value, string[4] memory c, bool isStat)
        internal
        pure
        returns (string memory)
    {
        // Unified height: 28px for all rows
        return string(
            abi.encodePacked(
                '<rect x="60" y="',
                _ts(y),
                '" width="280" height="28" rx="6" fill="',
                c[0],
                '" fill-opacity="0.2"/>',
                '<text x="80" y="',
                _ts(y + 18),
                '" font-family="Arial,sans-serif" font-size="12" fill="',
                c[2],
                '">',
                label,
                "</text>",
                '<text x="320" y="',
                _ts(y + 18),
                '" font-family="Arial,sans-serif" font-size="',
                isStat ? "14" : "12",
                '" fill="',
                c[3],
                '" text-anchor="end"',
                isStat ? ' font-weight="bold"' : "",
                ">",
                value,
                "</text>"
            )
        );
    }

    function _levelBadge(uint8 level, string[4] memory c) internal view returns (string memory) {
        // Stamp style badge in top-right corner with rotation
        return string(
            abi.encodePacked(
                '<g transform="translate(340, 70) rotate(15)">',
                '<circle cx="0" cy="0" r="32" fill="none" stroke="',
                c[1],
                '" stroke-width="3" stroke-opacity="0.9"/>',
                '<circle cx="0" cy="0" r="26" fill="none" stroke="',
                c[1],
                '" stroke-width="1" stroke-opacity="0.6"/>',
                '<text x="0" y="5" font-family="Arial,sans-serif" font-size="11" fill="',
                c[1],
                '" text-anchor="middle" font-weight="bold" letter-spacing="1">',
                _toUpper(LEVELS[level]),
                "</text></g>"
            )
        );
    }

    function _footer(uint8, string[4] memory c) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="200" y="560" font-family="Arial,sans-serif" font-size="10" fill="',
                c[2],
                '" text-anchor="middle" opacity="0.6" letter-spacing="2">KNOCK PROTOCOL</text>'
            )
        );
    }

    // ============ Internal Helpers ============

    function _attributes(IKnockCard.Card memory card, uint8 level) internal view returns (string memory) {
        uint256 rate = card.knocksSent > 0 ? (card.knocksAccepted * 100) / card.knocksSent : 0;
        return string(
            abi.encodePacked(
                '[{"trait_type":"Level","value":"',
                LEVELS[level],
                '"},{"trait_type":"Knocks Sent","value":',
                _ts(card.knocksSent),
                '},{"trait_type":"Knocks Accepted","value":',
                _ts(card.knocksAccepted),
                '},{"trait_type":"Knocks Rejected","value":',
                _ts(card.knocksRejected),
                '},{"trait_type":"ETH Earned","value":',
                _ts(card.ethReceived),
                '},{"trait_type":"Success Rate","value":',
                _ts(rate),
                '},{"trait_type":"Member Since","value":',
                _ts(card.createdAt),
                "}]"
            )
        );
    }

    function _getLevel(uint256 sent, uint256 accepted) internal pure returns (uint8) {
        if (sent < 5) return 0; // Newcomer
        uint256 rate = (accepted * 100) / sent;
        if (sent > 50 && rate >= 70) return 3; // Elite
        if (sent > 20 && rate >= 50) return 2; // Trusted
        return 1; // Active
    }

    function _toUpper(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);

        // Check if string contains non-ASCII characters (UTF-8 multi-byte)
        // If so, return as-is to avoid corrupting multi-byte sequences
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) > 0x7F) {
                // Contains non-ASCII, truncate at character boundary (max 20 chars)
                return _truncateUtf8(s, 20);
            }
        }

        // Pure ASCII string - safe to uppercase and truncate by bytes
        uint256 len = b.length > 20 ? 20 : b.length;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            if (b[i] >= 0x61 && b[i] <= 0x7a) {
                result[i] = bytes1(uint8(b[i]) - 32);
            } else {
                result[i] = b[i];
            }
        }
        return string(result);
    }

    function _truncateUtf8(string memory s, uint256 maxChars) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 charCount = 0;
        uint256 byteIndex = 0;

        while (byteIndex < b.length && charCount < maxChars) {
            uint8 firstByte = uint8(b[byteIndex]);
            uint256 charBytes;

            if (firstByte < 0x80) {
                charBytes = 1; // ASCII
            } else if (firstByte < 0xE0) {
                charBytes = 2; // 2-byte UTF-8
            } else if (firstByte < 0xF0) {
                charBytes = 3; // 3-byte UTF-8 (CJK characters)
            } else {
                charBytes = 4; // 4-byte UTF-8 (emoji, etc)
            }

            if (byteIndex + charBytes > b.length) break;
            byteIndex += charBytes;
            charCount++;
        }

        if (byteIndex >= b.length) return s;

        bytes memory result = new bytes(byteIndex);
        for (uint256 i = 0; i < byteIndex; i++) {
            result[i] = b[i];
        }
        return string(result);
    }

    function _truncate(string memory s, uint256 maxLen) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length <= maxLen) return s;
        bytes memory result = new bytes(maxLen);
        for (uint256 i = 0; i < maxLen; i++) {
            result[i] = b[i];
        }
        return string(result);
    }

    function _substring(string memory s, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (start >= b.length) return "";
        if (end > b.length) end = b.length;
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = b[i];
        }
        return string(result);
    }

    function _substringUtf8(string memory s, uint256 startChar, uint256 endChar) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 charCount = 0;
        uint256 startByte = 0;
        uint256 byteIndex = 0;

        // Find start byte position
        while (byteIndex < b.length && charCount < startChar) {
            uint8 firstByte = uint8(b[byteIndex]);
            uint256 charBytes = _utf8CharBytes(firstByte);
            if (byteIndex + charBytes > b.length) break;
            byteIndex += charBytes;
            charCount++;
        }
        startByte = byteIndex;

        // Find end byte position
        while (byteIndex < b.length && charCount < endChar) {
            uint8 firstByte = uint8(b[byteIndex]);
            uint256 charBytes = _utf8CharBytes(firstByte);
            if (byteIndex + charBytes > b.length) break;
            byteIndex += charBytes;
            charCount++;
        }

        if (startByte >= byteIndex) return "";

        bytes memory result = new bytes(byteIndex - startByte);
        for (uint256 i = startByte; i < byteIndex; i++) {
            result[i - startByte] = b[i];
        }
        return string(result);
    }

    function _utf8CharBytes(uint8 firstByte) internal pure returns (uint256) {
        if (firstByte < 0x80) return 1;
        if (firstByte < 0xE0) return 2;
        if (firstByte < 0xF0) return 3;
        return 4;
    }

    function _utf8Length(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 charCount = 0;
        uint256 byteIndex = 0;

        while (byteIndex < b.length) {
            uint8 firstByte = uint8(b[byteIndex]);
            uint256 charBytes = _utf8CharBytes(firstByte);
            if (byteIndex + charBytes > b.length) break;
            byteIndex += charBytes;
            charCount++;
        }
        return charCount;
    }

    function _shortenAddress(address addr) internal pure returns (string memory) {
        return string(abi.encodePacked("0x", _toHex(uint160(addr) >> 144), "...", _toHex(uint160(addr) & 0xFFFF)));
    }

    function _addressToString(address addr) internal pure returns (string memory) {
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

    function _toHex(uint256 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(4);
        for (uint256 i = 0; i < 4; i++) {
            str[3 - i] = alphabet[value & 0xf];
            value >>= 4;
        }
        return string(str);
    }

    function _stripProtocol(string memory url) internal pure returns (string memory) {
        bytes memory b = bytes(url);
        uint256 start = 0;
        if (b.length > 8 && b[0] == "h" && b[4] == "s" && b[7] == "/") {
            start = 8; // https://
        } else if (b.length > 7 && b[0] == "h" && b[4] == ":" && b[6] == "/") {
            start = 7; // http://
        }
        bytes memory result = new bytes(b.length - start);
        for (uint256 i = start; i < b.length; i++) {
            result[i - start] = b[i];
        }
        return string(result);
    }

    function _ts(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v;
        uint256 d;
        while (t != 0) {
            d++;
            t /= 10;
        }
        bytes memory b = new bytes(d);
        while (v != 0) {
            d--;
            b[d] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    /// @dev Format wei to native token with 2 decimal places (e.g., 1.23)
    function _formatNative(uint256 wei_) internal pure returns (string memory) {
        uint256 whole = wei_ / 1e18;
        uint256 decimals = (wei_ % 1e18) / 1e16; // 2 decimal places

        if (whole == 0 && decimals == 0) return "0";

        string memory wholeStr = _ts(whole);
        string memory decStr;

        if (decimals == 0) {
            return wholeStr;
        } else if (decimals < 10) {
            decStr = string(abi.encodePacked("0", _ts(decimals)));
        } else {
            decStr = _ts(decimals);
        }

        return string(abi.encodePacked(wholeStr, ".", decStr));
    }

    bytes internal constant TB = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function _b64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 len = 4 * ((data.length + 2) / 3);
        bytes memory r = new bytes(len);
        uint256 i;
        uint256 j;
        while (i < data.length) {
            uint256 a = uint8(data[i++]);
            uint256 b = i < data.length ? uint8(data[i++]) : 0;
            uint256 c = i < data.length ? uint8(data[i++]) : 0;
            uint256 x = (a << 16) | (b << 8) | c;
            r[j++] = TB[(x >> 18) & 0x3F];
            r[j++] = TB[(x >> 12) & 0x3F];
            r[j++] = TB[(x >> 6) & 0x3F];
            r[j++] = TB[x & 0x3F];
        }
        uint256 m = data.length % 3;
        if (m == 1) {
            r[len - 1] = "=";
            r[len - 2] = "=";
        } else if (m == 2) {
            r[len - 1] = "=";
        }
        return string(r);
    }
}
