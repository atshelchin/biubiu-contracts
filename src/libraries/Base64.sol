// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Base64
 * @notice Library for encoding bytes to Base64 strings
 * @dev Based on the Base64 encoding specified in RFC 4648
 */
library Base64 {
    bytes private constant ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /**
     * @notice Encode bytes to Base64 string
     * @param data The bytes to encode
     * @return The Base64 encoded string
     */
    function encode(bytes memory data) internal pure returns (string memory) {
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

            result[j++] = ALPHABET[(triple >> 18) & 0x3F];
            result[j++] = ALPHABET[(triple >> 12) & 0x3F];
            result[j++] = ALPHABET[(triple >> 6) & 0x3F];
            result[j++] = ALPHABET[triple & 0x3F];
        }

        // Add padding
        uint256 mod = data.length % 3;
        if (mod > 0) {
            result[encodedLen - 1] = "=";
            if (mod == 1) result[encodedLen - 2] = "=";
        }

        return string(result);
    }
}
