// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NFTMetadata} from "../src/tools/NFTMetadata.sol";

contract GenerateSVGPreview is Script {
    function run() external {
        NFTMetadata metadata = new NFTMetadata();

        console.log("=== NFT SVG Preview Generator ===");

        // Generate one sample for each rarity (0-3)
        string[4] memory rarityNames = ["Common", "Rare", "Legendary", "Epic"];

        for (uint8 rarity = 0; rarity <= 3; rarity++) {
            uint8 bg = rarity * 2;
            uint8 pattern = rarity;
            uint8 glow = rarity * 2 + 2;
            uint256 luckyNumber = uint256(rarity * 1111 + 42);

            // generateSVG signature includes collectionName and externalURL
            string memory svg = metadata.generateSVG(
                "Genesis Collection", "https://biubiu.tools", rarity, bg, pattern, glow, luckyNumber
            );

            console.log("");
            console.log("=== %s ===", rarityNames[rarity]);
            console.log(svg);
        }
    }
}
