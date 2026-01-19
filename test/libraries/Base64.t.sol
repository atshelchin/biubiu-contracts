// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Base64} from "../../src/libraries/Base64.sol";

contract Base64Test is Test {
    function test_encode_empty() public pure {
        assertEq(Base64.encode(""), "");
    }

    function test_encode_single_char() public pure {
        // "a" -> "YQ=="
        assertEq(Base64.encode("a"), "YQ==");
    }

    function test_encode_two_chars() public pure {
        // "ab" -> "YWI="
        assertEq(Base64.encode("ab"), "YWI=");
    }

    function test_encode_three_chars() public pure {
        // "abc" -> "YWJj" (no padding needed)
        assertEq(Base64.encode("abc"), "YWJj");
    }

    function test_encode_hello_world() public pure {
        // "Hello, World!" -> "SGVsbG8sIFdvcmxkIQ=="
        assertEq(Base64.encode("Hello, World!"), "SGVsbG8sIFdvcmxkIQ==");
    }

    function test_encode_json() public pure {
        // Test JSON encoding (common use case for NFT metadata)
        bytes memory json = '{"name":"test"}';
        assertEq(Base64.encode(json), "eyJuYW1lIjoidGVzdCJ9");
    }

    function test_encode_svg() public pure {
        // Test SVG encoding (common use case for on-chain NFT images)
        bytes memory svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
        assertEq(Base64.encode(svg), "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==");
    }

    function test_encode_binary_data() public pure {
        // Test binary data with all byte values
        bytes memory data = hex"000102030405060708090a0b0c0d0e0f";
        assertEq(Base64.encode(data), "AAECAwQFBgcICQoLDA0ODw==");
    }

    function test_encode_special_chars() public pure {
        // Characters that produce + and / in Base64
        bytes memory data = hex"fbff";
        assertEq(Base64.encode(data), "+/8=");
    }

    function test_encode_long_string() public pure {
        // Test longer string to verify multi-block encoding
        bytes memory data = "The quick brown fox jumps over the lazy dog";
        assertEq(Base64.encode(data), "VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZw==");
    }

    function testFuzz_encode_padding(uint8 len) public pure {
        // Verify padding is correct for any length
        vm.assume(len <= 100);

        bytes memory data = new bytes(len);
        for (uint8 i = 0; i < len; i++) {
            data[i] = bytes1(i);
        }

        string memory encoded = Base64.encode(data);
        bytes memory encodedBytes = bytes(encoded);

        if (len == 0) {
            assertEq(encodedBytes.length, 0);
        } else {
            // Encoded length should be 4 * ceil(len / 3)
            uint256 expectedLen = 4 * ((len + 2) / 3);
            assertEq(encodedBytes.length, expectedLen);

            // Check padding
            uint256 mod = len % 3;
            if (mod == 1) {
                assertEq(encodedBytes[expectedLen - 1], "=");
                assertEq(encodedBytes[expectedLen - 2], "=");
            } else if (mod == 2) {
                assertEq(encodedBytes[expectedLen - 1], "=");
                assertTrue(encodedBytes[expectedLen - 2] != "=");
            } else {
                assertTrue(encodedBytes[expectedLen - 1] != "=");
            }
        }
    }
}
