// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Strings
 * @notice Library for string conversion utilities
 * @dev Provides uint256 to decimal string and address to hex string conversions
 */
library Strings {
    bytes16 private constant HEX_ALPHABET = "0123456789abcdef";

    /**
     * @notice Convert uint256 to decimal string
     * @param value The number to convert
     * @return The decimal string representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

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
     * @notice Convert address to lowercase hex string with 0x prefix
     * @param addr The address to convert
     * @return The hex string representation (42 characters: "0x" + 40 hex chars)
     */
    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = HEX_ALPHABET[uint8(data[i] >> 4)];
            str[3 + i * 2] = HEX_ALPHABET[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    /**
     * @notice Convert uint256 to hex string with 0x prefix
     * @param value The number to convert
     * @return The hex string representation
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0x00";

        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }

        return toHexString(value, length);
    }

    /**
     * @notice Convert uint256 to hex string with fixed byte length
     * @param value The number to convert
     * @param length The number of bytes to represent
     * @return The hex string representation
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 + length * 2);
        buffer[0] = "0";
        buffer[1] = "x";

        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_ALPHABET[value & 0xf];
            value >>= 4;
        }

        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}
