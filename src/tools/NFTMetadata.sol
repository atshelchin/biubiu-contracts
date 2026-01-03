// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INFTMetadata} from "../interfaces/INFTMetadata.sol";

/**
 * @title NFTMetadata
 * @notice On-chain NFT metadata with SVG
 * @dev Part of BiuBiu Tools
 */
contract NFTMetadata is INFTMetadata {
    string[4] internal R = ["Common", "Rare", "Legendary", "Epic"];

    // [primary, secondary, accent, glow]
    string[4][4] internal C = [
        ["#4a5568", "#718096", "#a0aec0", "#cbd5e0"], // Common - Silver
        ["#2b6cb0", "#4299e1", "#63b3ed", "#90cdf4"], // Rare - Blue
        ["#6b21a8", "#9333ea", "#a855f7", "#c084fc"], // Legendary - Purple
        ["#b45309", "#d97706", "#f59e0b", "#fcd34d"] // Epic - Gold
    ];

    // [start, end]
    string[2][10] internal B = [
        ["#0f0f23", "#1a1a3e"],
        ["#0d1117", "#161b22"],
        ["#1a1a2e", "#16213e"],
        ["#0f172a", "#1e293b"],
        ["#18181b", "#27272a"],
        ["#1c1917", "#292524"],
        ["#0c0a09", "#1c1917"],
        ["#0f1419", "#15202b"],
        ["#0a0a0a", "#171717"],
        ["#020617", "#0f172a"]
    ];

    function generateMetadata(
        string memory cn,
        string memory tn,
        string memory desc,
        string memory url,
        uint8 r,
        uint8 bg,
        uint8 p,
        uint8 g,
        uint256 ln,
        uint256 dc
    ) external view returns (string memory) {
        string memory svg = generateSVG(cn, url, r, bg, p, g, ln);
        string memory attrs = _attrs(r, bg, p, g, ln, dc);
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                _b64(
                    bytes(
                        string(
                            abi.encodePacked(
                                '{"name":"',
                                tn,
                                '","description":"',
                                desc,
                                '","external_url":"',
                                url,
                                '","image":"data:image/svg+xml;base64,',
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

    function _attrs(uint8 r, uint8 bg, uint8 p, uint8 g, uint256 ln, uint256 dc) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '[{"trait_type":"Rarity","value":"',
                R[r],
                '"},{"trait_type":"Background","value":"',
                _ts(bg),
                '"},{"trait_type":"Pattern","value":"',
                _ts(p),
                '"},{"trait_type":"Aura","value":"',
                _ts(g),
                '"},{"trait_type":"Lucky Number","value":',
                _ts(ln),
                '},{"trait_type":"Drift Count","value":',
                _ts(dc),
                "}]"
            )
        );
    }

    function generateSVG(string memory cn, string memory url, uint8 r, uint8 bg, uint8 p, uint8 g, uint256 ln)
        public
        view
        returns (string memory)
    {
        string[4] memory t = C[r];
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 500">',
                _defs(t, B[bg], g, r),
                '<rect width="400" height="500" fill="url(#b)"/>',
                _frame(t, r),
                _ptn(p, t[2]),
                _orb(t, ln, r),
                _hdr(cn, t),
                _ftr(r, t, url),
                "</svg>"
            )
        );
    }

    function _defs(string[4] memory t, string[2] memory bg, uint8 g, uint8 r) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<defs><linearGradient id="b" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="',
                bg[0],
                '"/><stop offset="100%" stop-color="',
                bg[1],
                '"/></linearGradient><filter id="g"><feGaussianBlur stdDeviation="',
                g > 7 ? "12" : (g > 4 ? "8" : "5"),
                '" result="x"/><feMerge><feMergeNode in="x"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                _og(t, r),
                "</defs>",
                r >= 1 ? _an(r) : ""
            )
        );
    }

    function _og(string[4] memory t, uint8 r) internal pure returns (string memory) {
        if (r >= 3) {
            return string(
                abi.encodePacked(
                    '<radialGradient id="o" cx="35%" cy="30%" r="65%" fx="30%" fy="25%"><stop offset="0%" stop-color="#fff8e7"/><stop offset="15%" stop-color="',
                    t[3],
                    '"/><stop offset="45%" stop-color="',
                    t[2],
                    '"/><stop offset="75%" stop-color="',
                    t[1],
                    '"/><stop offset="100%" stop-color="',
                    t[0],
                    '"/></radialGradient><radialGradient id="d" cx="60%" cy="65%" r="50%"><stop offset="0%" stop-color="',
                    t[0],
                    '" stop-opacity=".5"/><stop offset="100%" stop-color="',
                    t[0],
                    '" stop-opacity="0"/></radialGradient><radialGradient id="h" cx="50%" cy="50%" r="50%"><stop offset="0%" stop-color="#fff" stop-opacity=".9"/><stop offset="100%" stop-color="',
                    t[3],
                    '" stop-opacity="0"/></radialGradient><radialGradient id="l" cx="50%" cy="50%" r="50%"><stop offset="85%" stop-color="',
                    t[2],
                    '" stop-opacity="0"/><stop offset="100%" stop-color="',
                    t[3],
                    '" stop-opacity=".4"/></radialGradient>'
                )
            );
        }
        return string(
            abi.encodePacked(
                '<radialGradient id="o" cx="50%" cy="30%" r="60%"><stop offset="0%" stop-color="',
                t[3],
                '"/><stop offset="60%" stop-color="',
                t[1],
                '"/><stop offset="100%" stop-color="',
                t[0],
                '"/></radialGradient>'
            )
        );
    }

    function _an(uint8 r) internal pure returns (string memory) {
        if (r >= 3) {
            return "<style>@keyframes f{0%,100%{transform:translateY(0)}50%{transform:translateY(-6px)}}@keyframes s{0%,100%{opacity:0}50%{opacity:1}}.og{animation:f 4s infinite}.p{animation:s 2s infinite}</style>";
        }
        if (r >= 2) return "<style>@keyframes s{0%,100%{opacity:.2}50%{opacity:1}}.p{animation:s 2s infinite}</style>";
        return "<style>@keyframes br{0%,100%{opacity:.7}50%{opacity:1}}.br{animation:br 3s infinite}</style>";
    }

    function _frame(string[4] memory t, uint8 r) internal pure returns (string memory) {
        if (r >= 2) {
            return string(
                abi.encodePacked(
                    '<rect x="20" y="20" width="360" height="460" rx="20" fill="none" stroke="',
                    t[1],
                    '" stroke-width="',
                    r >= 3 ? "3" : "2",
                    '" stroke-opacity=".8"/><rect x="30" y="30" width="340" height="440" rx="15" fill="none" stroke="',
                    t[2],
                    '" stroke-opacity=".3"/>'
                )
            );
        }
        return string(
            abi.encodePacked(
                '<rect x="20" y="20" width="360" height="460" rx="20" fill="none" stroke="',
                t[1],
                '" stroke-width="',
                r >= 1 ? "2" : "1",
                '" stroke-opacity=".5"/>'
            )
        );
    }

    function _ptn(uint8 p, string memory c) internal pure returns (string memory) {
        if (p < 3) {
            return string(
                abi.encodePacked(
                    '<circle cx="200" cy="250" r="120" fill="none" stroke="',
                    c,
                    '" stroke-opacity=".08"/><circle cx="200" cy="250" r="90" fill="none" stroke="',
                    c,
                    '" stroke-opacity=".06"/><circle cx="200" cy="250" r="60" fill="none" stroke="',
                    c,
                    '" stroke-opacity=".04"/>'
                )
            );
        }
        if (p < 6) {
            return string(
                abi.encodePacked(
                    '<g stroke="',
                    c,
                    '" stroke-opacity=".05"><line x1="40" y1="120" x2="360" y2="120"/><line x1="40" y1="200" x2="360" y2="200"/><line x1="40" y1="280" x2="360" y2="280"/><line x1="40" y1="360" x2="360" y2="360"/></g>'
                )
            );
        }
        return string(
            abi.encodePacked(
                '<polygon points="200,130 280,250 200,370 120,250" fill="none" stroke="',
                c,
                '" stroke-opacity=".1"/><polygon points="200,170 250,250 200,330 150,250" fill="none" stroke="',
                c,
                '" stroke-opacity=".06"/>'
            )
        );
    }

    function _orb(string[4] memory t, uint256 n, uint8 r) internal pure returns (string memory) {
        string memory num = _fn(n);
        if (r >= 3) {
            return string(
                abi.encodePacked(
                    '<g class="og">',
                    _pt(t[3]),
                    '<circle cx="200" cy="250" r="65" fill="url(#o)"/><circle cx="200" cy="250" r="65" fill="url(#d)"/><circle cx="200" cy="250" r="65" fill="url(#l)"/><ellipse cx="175" cy="225" rx="20" ry="12" fill="url(#h)"/><text x="200" y="258" font-family="Arial" font-size="26" fill="',
                    t[0],
                    '" text-anchor="middle" font-weight="700">',
                    num,
                    "</text></g>"
                )
            );
        }
        if (r >= 2) {
            return string(
                abi.encodePacked(
                    _pt(t[3]),
                    '<circle cx="200" cy="250" r="60" fill="url(#o)" filter="url(#g)"/><circle cx="200" cy="250" r="45" fill="',
                    t[0],
                    '"/><text x="200" y="258" font-family="Arial" font-size="28" fill="',
                    t[3],
                    '" text-anchor="middle" font-weight="700">',
                    num,
                    "</text>"
                )
            );
        }
        if (r >= 1) {
            return string(
                abi.encodePacked(
                    '<g class="br"><circle cx="200" cy="250" r="60" fill="url(#o)" filter="url(#g)"/><circle cx="200" cy="250" r="45" fill="',
                    t[0],
                    '"/><text x="200" y="258" font-family="Arial" font-size="28" fill="',
                    t[3],
                    '" text-anchor="middle" font-weight="700">',
                    num,
                    "</text></g>"
                )
            );
        }
        return string(
            abi.encodePacked(
                '<circle cx="200" cy="250" r="50" fill="url(#o)" filter="url(#g)"/><circle cx="200" cy="250" r="35" fill="',
                t[0],
                '"/><text x="200" y="258" font-family="Arial" font-size="28" fill="',
                t[3],
                '" text-anchor="middle" font-weight="700">',
                num,
                "</text>"
            )
        );
    }

    function _pt(string memory c) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<g class="p"><circle cx="125" cy="195" r="2" fill="',
                c,
                '"/></g><g class="p" style="animation-delay:.5s"><circle cx="275" cy="185" r="1.5" fill="',
                c,
                '"/></g><g class="p" style="animation-delay:1s"><circle cx="145" cy="305" r="1.5" fill="',
                c,
                '"/></g><g class="p" style="animation-delay:1.5s"><circle cx="255" cy="315" r="1.5" fill="',
                c,
                '"/></g>'
            )
        );
    }

    function _hdr(string memory n, string[4] memory t) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="200" y="65" font-family="Arial" font-size="18" fill="',
                t[2],
                '" text-anchor="middle" font-weight="600" letter-spacing="2">',
                _up(n),
                '</text><line x1="80" y1="80" x2="320" y2="80" stroke="',
                t[1],
                '" stroke-opacity=".3"/>'
            )
        );
    }

    function _ftr(uint8 r, string[4] memory t, string memory url) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="130" y="400" width="140" height="36" rx="18" fill="',
                t[0],
                '" fill-opacity=".9"/><rect x="130" y="400" width="140" height="36" rx="18" fill="none" stroke="',
                t[2],
                '" stroke-opacity=".5"/><text x="200" y="424" font-family="Arial" font-size="14" fill="',
                t[3],
                '" text-anchor="middle" font-weight="600" letter-spacing="1">',
                R[r],
                '</text><a href="',
                url,
                '" target="_blank"><text x="200" y="465" font-family="Arial" font-size="11" fill="',
                t[2],
                '" text-anchor="middle" opacity=".7">',
                _sp(url),
                "</text></a>"
            )
        );
    }

    function _sp(string memory u) internal pure returns (string memory) {
        bytes memory b = bytes(u);
        uint256 s = (b.length > 8 && b[0] == "h" && b[4] == "s" && b[7] == "/")
            ? 8
            : ((b.length > 7 && b[0] == "h" && b[4] == ":" && b[6] == "/") ? 7 : 0);
        bytes memory r = new bytes(b.length - s);
        for (uint256 i = s; i < b.length; i++) {
            r[i - s] = b[i];
        }
        return string(r);
    }

    function _fn(uint256 n) internal pure returns (string memory) {
        if (n < 10) return string(abi.encodePacked("#000", _ts(n)));
        if (n < 100) return string(abi.encodePacked("#00", _ts(n)));
        if (n < 1000) return string(abi.encodePacked("#0", _ts(n)));
        return string(abi.encodePacked("#", _ts(n)));
    }

    function _up(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x61 && b[i] <= 0x7a) b[i] = bytes1(uint8(b[i]) - 32);
        }
        return string(b);
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
