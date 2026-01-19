// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Strings} from "../../src/libraries/Strings.sol";

contract StringsTest is Test {
    // ============ toString Tests ============

    function test_toString_zero() public pure {
        assertEq(Strings.toString(0), "0");
    }

    function test_toString_singleDigit() public pure {
        assertEq(Strings.toString(1), "1");
        assertEq(Strings.toString(5), "5");
        assertEq(Strings.toString(9), "9");
    }

    function test_toString_multipleDigits() public pure {
        assertEq(Strings.toString(10), "10");
        assertEq(Strings.toString(123), "123");
        assertEq(Strings.toString(999), "999");
        assertEq(Strings.toString(1000), "1000");
    }

    function test_toString_largeNumbers() public pure {
        assertEq(Strings.toString(1000000), "1000000");
        assertEq(Strings.toString(123456789), "123456789");
    }

    function test_toString_maxUint256() public pure {
        // 2^256 - 1
        assertEq(
            Strings.toString(type(uint256).max),
            "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        );
    }

    function test_toString_powers_of_10() public pure {
        assertEq(Strings.toString(1), "1");
        assertEq(Strings.toString(10), "10");
        assertEq(Strings.toString(100), "100");
        assertEq(Strings.toString(1000), "1000");
        assertEq(Strings.toString(10000), "10000");
    }

    function testFuzz_toString_roundtrip(uint256 value) public pure {
        string memory str = Strings.toString(value);
        // Verify the string is not empty (unless value is 0)
        if (value == 0) {
            assertEq(str, "0");
        } else {
            assertTrue(bytes(str).length > 0);
            // First char should not be '0' for non-zero values
            assertTrue(bytes(str)[0] != "0");
        }
    }

    // ============ toHexString(address) Tests ============

    function test_toHexString_address_zero() public pure {
        assertEq(Strings.toHexString(address(0)), "0x0000000000000000000000000000000000000000");
    }

    function test_toHexString_address_one() public pure {
        assertEq(Strings.toHexString(address(1)), "0x0000000000000000000000000000000000000001");
    }

    function test_toHexString_address_typical() public pure {
        address addr = 0xdEad000000000000000000000000000000000000;
        assertEq(Strings.toHexString(addr), "0xdead000000000000000000000000000000000000");
    }

    function test_toHexString_address_allF() public pure {
        address addr = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
        assertEq(Strings.toHexString(addr), "0xffffffffffffffffffffffffffffffffffffffff");
    }

    function test_toHexString_address_mixed() public pure {
        address addr = 0x1234567890AbcdEF1234567890aBcdef12345678;
        assertEq(Strings.toHexString(addr), "0x1234567890abcdef1234567890abcdef12345678");
    }

    function test_toHexString_address_length() public pure {
        // All address hex strings should be exactly 42 characters
        assertEq(bytes(Strings.toHexString(address(0))).length, 42);
        assertEq(bytes(Strings.toHexString(address(1))).length, 42);
        assertEq(bytes(Strings.toHexString(address(type(uint160).max))).length, 42);
    }

    function testFuzz_toHexString_address(address addr) public pure {
        string memory str = Strings.toHexString(addr);

        // Length should always be 42
        assertEq(bytes(str).length, 42);

        // Should start with "0x"
        bytes memory strBytes = bytes(str);
        assertEq(strBytes[0], "0");
        assertEq(strBytes[1], "x");

        // All remaining chars should be valid hex
        for (uint256 i = 2; i < 42; i++) {
            bytes1 c = strBytes[i];
            bool isValidHex = (c >= "0" && c <= "9") || (c >= "a" && c <= "f");
            assertTrue(isValidHex);
        }
    }

    // ============ toHexString(uint256) Tests ============

    function test_toHexString_uint_zero() public pure {
        assertEq(Strings.toHexString(uint256(0)), "0x00");
    }

    function test_toHexString_uint_small() public pure {
        assertEq(Strings.toHexString(uint256(1)), "0x01");
        assertEq(Strings.toHexString(uint256(15)), "0x0f");
        assertEq(Strings.toHexString(uint256(16)), "0x10");
        assertEq(Strings.toHexString(uint256(255)), "0xff");
    }

    function test_toHexString_uint_larger() public pure {
        assertEq(Strings.toHexString(uint256(256)), "0x0100");
        assertEq(Strings.toHexString(uint256(0xabcd)), "0xabcd");
        assertEq(Strings.toHexString(uint256(0x123456)), "0x123456");
    }

    // ============ toHexString(uint256, length) Tests ============

    function test_toHexString_uint_fixedLength() public pure {
        assertEq(Strings.toHexString(uint256(0), 1), "0x00");
        assertEq(Strings.toHexString(uint256(1), 1), "0x01");
        assertEq(Strings.toHexString(uint256(255), 1), "0xff");
        assertEq(Strings.toHexString(uint256(0), 20), "0x0000000000000000000000000000000000000000");
    }

    function test_toHexString_uint_fixedLength_padding() public pure {
        assertEq(Strings.toHexString(uint256(1), 4), "0x00000001");
        assertEq(Strings.toHexString(uint256(0xab), 4), "0x000000ab");
    }
}
