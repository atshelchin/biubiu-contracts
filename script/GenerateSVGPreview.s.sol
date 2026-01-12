// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NFTMetadata} from "../src/tools/NFTMetadata.sol";

/**
 * @title GenerateSVGPreview
 * @notice Generate SVG previews for NFTFactory NFTs
 * @dev Run with: forge script script/GenerateSVGPreview.s.sol
 *      SVG files will be saved to ./svg-preview/ directory
 */
contract GenerateSVGPreview is Script {
    function run() external {
        NFTMetadata metadata = new NFTMetadata();

        console.log("=== NFT SVG Preview Generator ===");

        // Create output directory
        vm.createDir("./svg-preview", true);

        // Generate one sample for each rarity (0-3)
        string[4] memory rarityNames = ["common", "rare", "legendary", "epic"];
        string[4] memory rarityLabels = ["Common", "Rare", "Legendary", "Epic"];

        for (uint8 rarity = 0; rarity <= 3; rarity++) {
            uint8 bg = rarity * 2;
            uint8 pattern = rarity;
            uint8 glow = rarity * 2 + 2;
            uint256 luckyNumber = uint256(rarity * 1111 + 42);

            // generateSVG signature includes collectionName and externalURL
            string memory svg = metadata.generateSVG(
                "Genesis Collection", "https://biubiu.tools", rarity, bg, pattern, glow, luckyNumber
            );

            // Save to file
            string memory filename = string(abi.encodePacked("./svg-preview/nft_", rarityNames[rarity], ".svg"));
            vm.writeFile(filename, svg);

            console.log("Saved: %s (%s)", filename, rarityLabels[rarity]);
        }

        console.log("");
        console.log("SVG files saved to ./svg-preview/");
    }
}
