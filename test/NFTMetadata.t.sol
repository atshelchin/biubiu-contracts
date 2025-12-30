// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTMetadata} from "../src/NFTMetadata.sol";

contract NFTMetadataTest is Test {
    NFTMetadata public metadata;

    string constant COLLECTION_NAME = "Genesis Collection";
    string constant TOKEN_NAME = "Genesis #1";
    string constant DESCRIPTION = "A unique NFT from the Genesis Collection";
    string constant EXTERNAL_URL = "https://biubiu.tools";

    function setUp() public {
        metadata = new NFTMetadata();
    }

    // ============ generateMetadata Tests ============

    function test_GenerateMetadataCommon() public view {
        string memory result = metadata.generateMetadata(
            COLLECTION_NAME,
            TOKEN_NAME,
            DESCRIPTION,
            EXTERNAL_URL,
            0, // rarity: Common
            0, // background
            0, // pattern
            2, // glow
            42, // luckyNumber
            0 // driftCount
        );

        // Should start with base64 data URI
        assertTrue(bytes(result).length > 0);
        assertTrue(_startsWith(result, "data:application/json;base64,"));
    }

    function test_GenerateMetadataRare() public view {
        string memory result = metadata.generateMetadata(
            COLLECTION_NAME,
            TOKEN_NAME,
            DESCRIPTION,
            EXTERNAL_URL,
            1, // rarity: Rare
            2, // background
            1, // pattern
            4, // glow
            1153, // luckyNumber
            5 // driftCount
        );

        assertTrue(bytes(result).length > 0);
        assertTrue(_startsWith(result, "data:application/json;base64,"));
    }

    function test_GenerateMetadataLegendary() public view {
        string memory result = metadata.generateMetadata(
            COLLECTION_NAME,
            TOKEN_NAME,
            DESCRIPTION,
            EXTERNAL_URL,
            2, // rarity: Legendary
            4, // background
            5, // pattern
            6, // glow
            2264, // luckyNumber
            10 // driftCount
        );

        assertTrue(bytes(result).length > 0);
        assertTrue(_startsWith(result, "data:application/json;base64,"));
    }

    function test_GenerateMetadataEpic() public view {
        string memory result = metadata.generateMetadata(
            COLLECTION_NAME,
            TOKEN_NAME,
            DESCRIPTION,
            EXTERNAL_URL,
            3, // rarity: Epic
            6, // background
            7, // pattern
            8, // glow
            3375, // luckyNumber
            25 // driftCount
        );

        assertTrue(bytes(result).length > 0);
        assertTrue(_startsWith(result, "data:application/json;base64,"));
    }

    function testFuzz_GenerateMetadata(
        uint8 rarity,
        uint8 bg,
        uint8 pattern,
        uint8 glow,
        uint256 luckyNumber,
        uint256 driftCount
    ) public view {
        // Bound inputs to valid ranges
        rarity = uint8(bound(rarity, 0, 3));
        bg = uint8(bound(bg, 0, 9));
        pattern = uint8(bound(pattern, 0, 9));
        glow = uint8(bound(glow, 0, 9));
        luckyNumber = bound(luckyNumber, 0, 9999);
        driftCount = bound(driftCount, 0, 1000);

        string memory result = metadata.generateMetadata(
            COLLECTION_NAME, TOKEN_NAME, DESCRIPTION, EXTERNAL_URL, rarity, bg, pattern, glow, luckyNumber, driftCount
        );

        assertTrue(bytes(result).length > 0);
        assertTrue(_startsWith(result, "data:application/json;base64,"));
    }

    // ============ generateSVG Tests ============

    function test_GenerateSVGCommon() public view {
        string memory svg = metadata.generateSVG(
            COLLECTION_NAME,
            EXTERNAL_URL,
            0, // rarity: Common
            0, // background
            0, // pattern
            2, // glow
            42 // luckyNumber
        );

        assertTrue(bytes(svg).length > 0);
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "Common"));
        assertTrue(_contains(svg, "#0042")); // Lucky number formatted
    }

    function test_GenerateSVGRare() public view {
        string memory svg = metadata.generateSVG(
            COLLECTION_NAME,
            EXTERNAL_URL,
            1, // rarity: Rare
            2, // background
            1, // pattern
            4, // glow
            1153 // luckyNumber
        );

        assertTrue(bytes(svg).length > 0);
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "Rare"));
        assertTrue(_contains(svg, "#1153"));
    }

    function test_GenerateSVGLegendary() public view {
        string memory svg = metadata.generateSVG(
            COLLECTION_NAME,
            EXTERNAL_URL,
            2, // rarity: Legendary
            4, // background
            5, // pattern
            6, // glow
            2264 // luckyNumber
        );

        assertTrue(bytes(svg).length > 0);
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "Legendary"));
        assertTrue(_contains(svg, "#2264"));
    }

    function test_GenerateSVGEpic() public view {
        string memory svg = metadata.generateSVG(
            COLLECTION_NAME,
            EXTERNAL_URL,
            3, // rarity: Epic
            6, // background
            7, // pattern
            8, // glow
            3375 // luckyNumber
        );

        assertTrue(bytes(svg).length > 0);
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "Epic"));
        assertTrue(_contains(svg, "#3375"));
    }

    function test_GenerateSVGContainsCollectionName() public view {
        string memory svg = metadata.generateSVG("My Custom Collection", EXTERNAL_URL, 0, 0, 0, 2, 42);

        // Collection name is uppercased in header
        assertTrue(_contains(svg, "MY CUSTOM COLLECTION"));
    }

    function test_GenerateSVGContainsExternalUrl() public view {
        string memory svg = metadata.generateSVG(COLLECTION_NAME, "https://example.com", 0, 0, 0, 2, 42);

        assertTrue(_contains(svg, "example.com"));
    }

    function test_GenerateSVGDifferentPatterns() public view {
        // Pattern < 3: circles
        string memory svg0 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(_contains(svg0, "circle cx=\"200\" cy=\"250\" r=\"120\""));

        // Pattern 3-5: lines
        string memory svg3 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 4, 2, 42);
        assertTrue(_contains(svg3, "line x1=\"40\""));

        // Pattern >= 6: diamonds
        string memory svg6 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 7, 2, 42);
        assertTrue(_contains(svg6, "polygon points="));
    }

    function test_GenerateSVGDifferentGlowLevels() public view {
        // Glow <= 4: stdDeviation="5"
        string memory svg1 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 3, 42);
        assertTrue(_contains(svg1, "stdDeviation=\"5\""));

        // Glow 5-7: stdDeviation="8"
        string memory svg2 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 6, 42);
        assertTrue(_contains(svg2, "stdDeviation=\"8\""));

        // Glow > 7: stdDeviation="12"
        string memory svg3 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 9, 42);
        assertTrue(_contains(svg3, "stdDeviation=\"12\""));
    }

    function testFuzz_GenerateSVG(uint8 rarity, uint8 bg, uint8 pattern, uint8 glow, uint256 luckyNumber) public view {
        rarity = uint8(bound(rarity, 0, 3));
        bg = uint8(bound(bg, 0, 9));
        pattern = uint8(bound(pattern, 0, 9));
        glow = uint8(bound(glow, 0, 9));
        luckyNumber = bound(luckyNumber, 0, 9999);

        string memory svg = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, rarity, bg, pattern, glow, luckyNumber);

        assertTrue(bytes(svg).length > 0);
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "</svg>"));
    }

    // ============ Lucky Number Formatting Tests ============

    function test_LuckyNumberFormatting() public view {
        // Single digit: #000X
        string memory svg1 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 7);
        assertTrue(_contains(svg1, "#0007"));

        // Two digits: #00XX
        string memory svg2 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(_contains(svg2, "#0042"));

        // Three digits: #0XXX
        string memory svg3 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 123);
        assertTrue(_contains(svg3, "#0123"));

        // Four digits: #XXXX
        string memory svg4 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 9999);
        assertTrue(_contains(svg4, "#9999"));

        // Zero: #0000
        string memory svg0 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 0);
        assertTrue(_contains(svg0, "#0000"));
    }

    // ============ URL Stripping Tests ============

    function test_UrlStrippingHttps() public view {
        string memory svg = metadata.generateSVG(COLLECTION_NAME, "https://biubiu.tools", 0, 0, 0, 2, 42);
        // Should strip https:// and show only domain
        assertTrue(_contains(svg, "biubiu.tools"));
    }

    function test_UrlStrippingHttp() public view {
        string memory svg = metadata.generateSVG(COLLECTION_NAME, "http://biubiu.tools", 0, 0, 0, 2, 42);
        // Should strip http:// and show only domain
        assertTrue(_contains(svg, "biubiu.tools"));
    }

    // ============ Animation Tests ============

    function test_AnimationForRarities() public view {
        // Common (rarity 0): no animation style expected
        string memory svgCommon = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        // Common doesn't have animation in the optimized version
        assertFalse(_contains(svgCommon, "@keyframes"));

        // Rare (rarity 1): breathe animation
        string memory svgRare = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 1, 0, 0, 2, 42);
        assertTrue(_contains(svgRare, "@keyframes br"));
        assertTrue(_contains(svgRare, "class=\"br\""));

        // Legendary (rarity 2): sparkle animation
        string memory svgLegendary = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 2, 0, 0, 2, 42);
        assertTrue(_contains(svgLegendary, "@keyframes s"));
        assertTrue(_contains(svgLegendary, "class=\"p\""));

        // Epic (rarity 3): float + sparkle animation
        string memory svgEpic = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 3, 0, 0, 8, 42);
        assertTrue(_contains(svgEpic, "@keyframes f"));
        assertTrue(_contains(svgEpic, "@keyframes s"));
        assertTrue(_contains(svgEpic, "class=\"og\""));
    }

    // ============ Frame Tests ============

    function test_FrameForRarities() public view {
        // Common/Rare: single frame
        string memory svgCommon = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertFalse(_contains(svgCommon, "rx=\"15\""));

        // Legendary/Epic: double frame
        string memory svgLegendary = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 2, 0, 0, 6, 42);
        assertTrue(_contains(svgLegendary, "rx=\"15\""));

        string memory svgEpic = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 3, 0, 0, 8, 42);
        assertTrue(_contains(svgEpic, "rx=\"15\""));
    }

    // ============ Color Tests ============

    function test_ColorSchemesForRarities() public view {
        // Common: Silver (#4a5568, #718096, #a0aec0, #cbd5e0)
        string memory svgCommon = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(_contains(svgCommon, "#4a5568"));
        assertTrue(_contains(svgCommon, "#718096"));

        // Rare: Blue (#2b6cb0, #4299e1, #63b3ed, #90cdf4)
        string memory svgRare = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 1, 0, 0, 2, 42);
        assertTrue(_contains(svgRare, "#2b6cb0"));
        assertTrue(_contains(svgRare, "#4299e1"));

        // Legendary: Purple (#6b21a8, #9333ea, #a855f7, #c084fc)
        string memory svgLegendary = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 2, 0, 0, 6, 42);
        assertTrue(_contains(svgLegendary, "#6b21a8"));
        assertTrue(_contains(svgLegendary, "#9333ea"));

        // Epic: Gold (#b45309, #d97706, #f59e0b, #fcd34d)
        string memory svgEpic = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 3, 0, 0, 8, 42);
        assertTrue(_contains(svgEpic, "#b45309"));
        assertTrue(_contains(svgEpic, "#d97706"));
    }

    // ============ Background Tests ============

    function test_BackgroundGradients() public view {
        // Background 0: #0f0f23 -> #1a1a3e
        string memory svg0 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(_contains(svg0, "#0f0f23"));
        assertTrue(_contains(svg0, "#1a1a3e"));

        // Background 5: #1c1917 -> #292524
        string memory svg5 = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 5, 0, 2, 42);
        assertTrue(_contains(svg5, "#1c1917"));
        assertTrue(_contains(svg5, "#292524"));
    }

    // ============ Edge Cases ============

    function test_EmptyCollectionName() public view {
        string memory svg = metadata.generateSVG("", EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(bytes(svg).length > 0);
    }

    function test_EmptyUrl() public view {
        string memory svg = metadata.generateSVG(COLLECTION_NAME, "", 0, 0, 0, 2, 42);
        assertTrue(bytes(svg).length > 0);
    }

    function test_LargeLuckyNumber() public view {
        string memory svg = metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 0, 0, 0, 2, 999999);
        assertTrue(bytes(svg).length > 0);
        assertTrue(_contains(svg, "#999999"));
    }

    function test_SpecialCharactersInName() public view {
        // Note: Special characters might cause issues in XML, but we test basic cases
        string memory svg = metadata.generateSVG("Test-Collection_123", EXTERNAL_URL, 0, 0, 0, 2, 42);
        assertTrue(_contains(svg, "TEST-COLLECTION_123"));
    }

    // ============ Gas Tests ============

    function test_GasUsage() public {
        uint256 gasBefore = gasleft();
        metadata.generateMetadata(COLLECTION_NAME, TOKEN_NAME, DESCRIPTION, EXTERNAL_URL, 3, 6, 7, 8, 3375, 25);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for Epic generateMetadata:", gasUsed);
        // Gas usage is high due to on-chain SVG + base64 encoding, but should stay under 10M
        assertTrue(gasUsed < 10_000_000);
    }

    function test_GasUsageSVGOnly() public {
        uint256 gasBefore = gasleft();
        metadata.generateSVG(COLLECTION_NAME, EXTERNAL_URL, 3, 6, 7, 8, 3375);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for Epic generateSVG:", gasUsed);
        assertTrue(gasUsed < 300000);
    }

    // ============ Helper Functions ============

    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (strBytes.length < prefixBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);
        if (substrBytes.length > strBytes.length) return false;
        if (substrBytes.length == 0) return true;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
