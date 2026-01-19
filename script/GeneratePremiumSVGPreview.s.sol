// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";
import {IBiuBiuPremium} from "../src/interfaces/IBiuBiuPremium.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title GeneratePremiumSVGPreview
 * @notice Generate SVG previews for BiuBiuPremium NFTs
 * @dev Run with: forge script script/GeneratePremiumSVGPreview.s.sol -vvv
 *      SVG files will be saved to ./svg-preview/ directory
 */
contract GeneratePremiumSVGPreview is Script {
    function run() external {
        // Deploy a fresh BiuBiuPremium for testing
        BiuBiuPremium premium = new BiuBiuPremium();

        console.log("=== BiuBiu Premium SVG Preview Generator ===");
        console.log("Contract deployed at:", address(premium));

        // Create output directory
        vm.createDir("./svg-preview", true);

        // Generate Active subscription NFT
        _generateAndSave(premium, "active", true, address(0x1111));

        // Generate Expired subscription NFT
        _generateAndSave(premium, "expired", false, address(0x2222));

        console.log("");
        console.log("SVG files saved to ./svg-preview/");
    }

    function _generateAndSave(BiuBiuPremium premium, string memory name, bool isActive, address testUser) internal {
        // Fund and subscribe to mint NFT
        vm.deal(testUser, 10 ether);
        vm.startPrank(testUser);
        premium.subscribe{value: premium.MONTHLY_PRICE()}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0), address(0));
        vm.stopPrank();

        uint256 tokenId = premium.nextTokenId() - 1;

        if (!isActive) {
            // Warp time to expire the subscription
            vm.warp(block.timestamp + 31 days);
        }

        // Get tokenURI
        string memory tokenURI = premium.tokenURI(tokenId);

        // Extract SVG from base64 JSON
        string memory svg = _extractSVGFromTokenURI(tokenURI);

        // Save to file
        string memory filename = string(abi.encodePacked("./svg-preview/premium_", name, ".svg"));
        vm.writeFile(filename, svg);

        console.log("Saved:", filename);
    }

    function _extractSVGFromTokenURI(string memory tokenURI) internal pure returns (string memory) {
        // tokenURI format: "data:application/json;base64,{base64_json}"
        // JSON contains: {"image":"data:image/svg+xml;base64,{base64_svg}"}

        // Skip "data:application/json;base64," prefix (29 chars)
        bytes memory tokenURIBytes = bytes(tokenURI);
        uint256 base64Start = 29;

        // Extract base64 JSON
        bytes memory base64Json = new bytes(tokenURIBytes.length - base64Start);
        for (uint256 i = 0; i < base64Json.length; i++) {
            base64Json[i] = tokenURIBytes[base64Start + i];
        }

        // Decode base64 JSON
        bytes memory jsonBytes = _base64Decode(string(base64Json));
        string memory json = string(jsonBytes);

        // Find "image":"data:image/svg+xml;base64," in JSON
        bytes memory jsonBytesSearch = bytes(json);
        bytes memory searchPattern = bytes('"image":"data:image/svg+xml;base64,');
        uint256 imageStart = 0;

        for (uint256 i = 0; i < jsonBytesSearch.length - searchPattern.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchPattern.length; j++) {
                if (jsonBytesSearch[i + j] != searchPattern[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                imageStart = i + searchPattern.length;
                break;
            }
        }

        // Find the closing quote
        uint256 imageEnd = imageStart;
        for (uint256 i = imageStart; i < jsonBytesSearch.length; i++) {
            if (jsonBytesSearch[i] == '"') {
                imageEnd = i;
                break;
            }
        }

        // Extract base64 SVG
        bytes memory base64Svg = new bytes(imageEnd - imageStart);
        for (uint256 i = 0; i < base64Svg.length; i++) {
            base64Svg[i] = jsonBytesSearch[imageStart + i];
        }

        // Decode base64 SVG
        bytes memory svgBytes = _base64Decode(string(base64Svg));
        return string(svgBytes);
    }

    function _base64Decode(string memory data) internal pure returns (bytes memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        bytes memory input = bytes(data);
        if (input.length == 0) return new bytes(0);

        // Remove padding
        uint256 len = input.length;
        while (len > 0 && input[len - 1] == "=") {
            len--;
        }

        // Calculate output length
        uint256 outputLen = (len * 3) / 4;
        bytes memory output = new bytes(outputLen);

        // Build decode table
        uint8[128] memory decodeTable;
        for (uint8 i = 0; i < 64; i++) {
            decodeTable[uint8(table[i])] = i;
        }

        uint256 outputIdx = 0;
        for (uint256 i = 0; i < len; i += 4) {
            uint256 n = 0;
            uint256 chars = 0;

            for (uint256 j = 0; j < 4 && i + j < len; j++) {
                n = n << 6;
                if (uint8(input[i + j]) < 128) {
                    n |= decodeTable[uint8(input[i + j])];
                }
                chars++;
            }

            // Pad remaining with zeros
            n = n << (6 * (4 - chars));

            if (outputIdx < outputLen) output[outputIdx++] = bytes1(uint8(n >> 16));
            if (outputIdx < outputLen) output[outputIdx++] = bytes1(uint8(n >> 8));
            if (outputIdx < outputLen) output[outputIdx++] = bytes1(uint8(n));
        }

        return output;
    }
}
