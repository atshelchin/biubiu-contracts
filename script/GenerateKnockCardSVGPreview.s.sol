// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {KnockCard} from "../src/knock/KnockCard.sol";
import {KnockCardMetadata} from "../src/knock/KnockCardMetadata.sol";

/**
 * @title GenerateKnockCardSVGPreview
 * @notice Generate SVG previews for KnockCard reputation cards
 * @dev Run with: forge script script/GenerateKnockCardSVGPreview.s.sol --tc GenerateKnockCardSVGPreview
 *      SVG files will be saved to ./svg-preview/ directory
 */
contract GenerateKnockCardSVGPreview is Script {
    function run() external {
        console.log("=== KnockCard SVG Preview Generator ===");
        console.log("");

        // Deploy mock protocol and card
        MockKnockProtocol protocol = new MockKnockProtocol();
        KnockCard card = KnockCard(address(protocol.knockCard()));
        KnockCardMetadata metadata = new KnockCardMetadata(address(card));

        // Set metadata contract
        protocol.setMetadataContract(address(metadata));

        // Create output directory
        vm.createDir("./svg-preview", true);

        // ============ Level Samples ============
        console.log("--- Level Samples ---");

        // Level 0 (Newcomer): < 5 knocks sent
        _generateCard(
            card, metadata, address(0x1001),
            "Vitalik",
            "Ethereum co-founder. Building the future.",
            "@VitalikButerin", "vbuterin", "https://vitalik.ca",
            500, 2, 1, 0,  // 500 received - very popular
            "level_newcomer"
        );

        // Level 1 (Active): >= 5 knocks sent
        _generateCard(
            card, metadata, address(0x1002),
            "CZ",
            "Building. 4.",
            "@cz_binance", "", "https://binance.com",
            250, 15, 8, 3,  // 250 received
            "level_active"
        );

        // Level 2 (Trusted): > 20 sent, >= 50% acceptance
        _generateCard(
            card, metadata, address(0x1003),
            "Hayden",
            "Uniswap founder. DeFi builder.",
            "@haaboron", "haydenadams", "",
            180, 35, 20, 5,  // 180 received
            "level_trusted"
        );

        // Level 3 (Elite): > 50 sent, >= 70% acceptance
        _generateCard(
            card, metadata, address(0x1004),
            "Satoshi",
            "Chancellor on brink of second bailout for banks.",
            "", "satoshi", "https://bitcoin.org",
            9999, 100, 85, 5,  // 9999 received - legendary
            "level_elite"
        );

        // ============ Edge Cases: Bio Length ============
        console.log("");
        console.log("--- Bio Length Edge Cases ---");

        // No bio
        _generateCard(
            card, metadata, address(0x2001),
            "NoBio",
            "",
            "@nobio", "", "",
            15, 10, 5, 2,
            "edge_no_bio"
        );

        // Short bio
        _generateCard(
            card, metadata, address(0x2002),
            "ShortBio",
            "Hi!",
            "@shortbio", "", "",
            20, 10, 5, 2,
            "edge_short_bio"
        );

        // Long bio (will be truncated at 60 chars)
        _generateCard(
            card, metadata, address(0x2003),
            "LongBio",
            "This is a very long bio that exceeds the maximum display length and should be truncated with ellipsis at the end.",
            "@longbio", "", "",
            30, 10, 5, 2,
            "edge_long_bio"
        );

        // Exactly 60 chars bio
        _generateCard(
            card, metadata, address(0x2004),
            "ExactBio",
            "This bio is exactly sixty characters long, no more no less!",
            "@exactbio", "", "",
            25, 10, 5, 2,
            "edge_exact_bio"
        );

        // ============ Edge Cases: Social Combinations ============
        console.log("");
        console.log("--- Social Combinations ---");

        // All socials filled
        _generateCard(
            card, metadata, address(0x3001),
            "FullSocial",
            "All social links filled.",
            "@fullsocial", "fullsocial", "https://fullsocial.xyz",
            50, 20, 15, 2,
            "social_all_filled"
        );

        // Only Twitter
        _generateCard(
            card, metadata, address(0x3002),
            "OnlyTwitter",
            "Only has Twitter.",
            "@onlytwitter", "", "",
            35, 20, 15, 2,
            "social_twitter_only"
        );

        // Only GitHub
        _generateCard(
            card, metadata, address(0x3003),
            "OnlyGithub",
            "Only has GitHub.",
            "", "onlygithub", "",
            28, 20, 15, 2,
            "social_github_only"
        );

        // Only Website
        _generateCard(
            card, metadata, address(0x3004),
            "OnlyWebsite",
            "Only has Website.",
            "", "", "https://onlywebsite.com",
            22, 20, 15, 2,
            "social_website_only"
        );

        // No socials at all
        _generateCard(
            card, metadata, address(0x3005),
            "NoSocials",
            "No social links.",
            "", "", "",
            18, 20, 15, 2,
            "social_none"
        );

        // Twitter + GitHub (no website)
        _generateCard(
            card, metadata, address(0x3006),
            "TwGh",
            "Twitter and GitHub only.",
            "@twgh", "twgh", "",
            40, 20, 15, 2,
            "social_tw_gh"
        );

        // Twitter + Website (no GitHub)
        _generateCard(
            card, metadata, address(0x3007),
            "TwWeb",
            "Twitter and Website only.",
            "@twweb", "", "https://twweb.io",
            33, 20, 15, 2,
            "social_tw_web"
        );

        // GitHub + Website (no Twitter)
        _generateCard(
            card, metadata, address(0x3008),
            "GhWeb",
            "GitHub and Website only.",
            "", "ghweb", "https://ghweb.dev",
            27, 20, 15, 2,
            "social_gh_web"
        );

        // ============ Edge Cases: Nickname Length ============
        console.log("");
        console.log("--- Nickname Length ---");

        // Short nickname (1 char)
        _generateCard(
            card, metadata, address(0x4001),
            "X",
            "Single character nickname.",
            "@x", "", "",
            100, 5, 3, 1,  // 100 received - like Elon's X
            "nick_short"
        );

        // Max length nickname (20 chars)
        _generateCard(
            card, metadata, address(0x4002),
            "TwentyCharNickname12",
            "Maximum length nickname.",
            "@twentychar", "", "",
            12, 5, 3, 1,
            "nick_max_length"
        );

        // ============ Edge Cases: Stats ============
        console.log("");
        console.log("--- Stats Edge Cases ---");

        // Zero stats (brand new)
        _generateCard(
            card, metadata, address(0x5001),
            "ZeroStats",
            "Brand new user, no activity.",
            "", "", "",
            0, 0, 0, 0,
            "stats_zero"
        );

        // High numbers
        _generateCard(
            card, metadata, address(0x5002),
            "HighStats",
            "Very active user.",
            "@highstats", "", "",
            8888, 999, 888, 77,  // 8888 received - influencer level
            "stats_high"
        );

        // 100% acceptance rate
        _generateCard(
            card, metadata, address(0x5003),
            "Perfect",
            "Perfect acceptance rate!",
            "@perfect", "", "",
            200, 50, 50, 0,  // 200 received
            "stats_perfect"
        );

        // 0% acceptance rate (all rejected)
        _generateCard(
            card, metadata, address(0x5004),
            "AllReject",
            "All knocks rejected.",
            "@allreject", "", "",
            5, 20, 0, 20,  // Only 5 received - not popular
            "stats_all_rejected"
        );

        // ============ Edge Cases: Minimal vs Maximal ============
        console.log("");
        console.log("--- Minimal vs Maximal ---");

        // Absolutely minimal
        _generateCard(
            card, metadata, address(0x6001),
            "Min",
            "",
            "", "", "",
            0, 0, 0, 0,
            "minimal"
        );

        // Absolutely maximal
        _generateCard(
            card, metadata, address(0x6002),
            "MaximalInfoCard1234",
            "This is the longest possible bio text that will definitely get truncated because it exceeds sixty chars.",
            "@maximaluser123", "maximaluser123456789", "https://maximal-website-url-example.com/path/to/page",
            5000, 200, 180, 10,  // 5000 received
            "maximal"
        );

        // ============ Edge Cases: Website URL formats ============
        console.log("");
        console.log("--- Website URL Formats ---");

        // http:// (should strip)
        _generateCard(
            card, metadata, address(0x7001),
            "HttpUser",
            "HTTP website.",
            "", "", "http://httpuser.com",
            15, 10, 5, 2,
            "url_http"
        );

        // https:// (should strip)
        _generateCard(
            card, metadata, address(0x7002),
            "HttpsUser",
            "HTTPS website.",
            "", "", "https://httpsuser.com",
            20, 10, 5, 2,
            "url_https"
        );

        // No protocol (raw domain)
        _generateCard(
            card, metadata, address(0x7003),
            "RawDomain",
            "Raw domain without protocol.",
            "", "", "rawdomain.xyz",
            18, 10, 5, 2,
            "url_raw"
        );

        // ============ Multilingual Text ============
        console.log("");
        console.log("--- Multilingual Text ---");

        // Japanese
        _generateCard(
            card, metadata, address(0x8001),
            unicode"サトシ",
            unicode"ビットコインの創設者。分散化を信じる。",
            "@satoshi_jp", "", "",
            300, 50, 40, 5,  // 300 received
            "lang_japanese"
        );

        // Chinese
        _generateCard(
            card, metadata, address(0x8002),
            unicode"中本聪",
            unicode"比特币创始人，去中心化的信仰者。",
            "@zhongben", "", "https://bitcoin.org",
            1000, 100, 85, 10,  // 1000 received
            "lang_chinese"
        );

        // Korean
        _generateCard(
            card, metadata, address(0x8003),
            unicode"김철수",
            unicode"블록체인 개발자. 탈중앙화를 믿습니다.",
            "@kimdev", "kimdev", "",
            150, 30, 25, 3,
            "lang_korean"
        );

        // Arabic (RTL)
        _generateCard(
            card, metadata, address(0x8004),
            unicode"أحمد",
            unicode"مطور بلوكتشين من الشرق الأوسط",
            "@ahmed_dev", "", "",
            80, 20, 15, 2,
            "lang_arabic"
        );

        // Thai
        _generateCard(
            card, metadata, address(0x8005),
            unicode"สมชาย",
            unicode"นักพัฒนาบล็อกเชนจากประเทศไทย",
            "@somchai", "", "",
            60, 15, 10, 2,
            "lang_thai"
        );

        // Hindi
        _generateCard(
            card, metadata, address(0x8006),
            unicode"राहुल",
            unicode"ब्लॉकचेन डेवलपर। विकेंद्रीकरण में विश्वास।",
            "@rahul_dev", "", "",
            120, 25, 20, 3,
            "lang_hindi"
        );

        // Emoji in bio
        _generateCard(
            card, metadata, address(0x8007),
            "EmojiUser",
            unicode"Building the future 🚀 Web3 enthusiast 💎",
            "@emoji_user", "", "",
            45, 10, 8, 1,
            "lang_emoji"
        );

        // Mixed languages
        _generateCard(
            card, metadata, address(0x8008),
            unicode"Web3Dev",
            unicode"Developer 开发者 開発者 개발자",
            "@web3dev", "web3dev", "https://web3.dev",
            250, 60, 50, 5,
            "lang_mixed"
        );

        console.log("");
        console.log("=== All SVG files saved to ./svg-preview/ ===");
    }

    function _generateCard(
        KnockCard card,
        KnockCardMetadata metadata,
        address user,
        string memory nickname,
        string memory bio,
        string memory twitter,
        string memory github,
        string memory website,
        uint256 ethReceivedInEth,
        uint256 knocksSent,
        uint256 knocksAccepted,
        uint256 knocksRejected,
        string memory filename
    ) internal {
        // Fund user and create card
        vm.deal(user, 1 ether);
        vm.prank(user);
        card.createCard{value: 0.1 ether}(nickname, bio, twitter, github, website);

        // Set stats using protocol mock
        MockKnockProtocol protocol = MockKnockProtocol(card.protocol());
        protocol.setCardStats(user, ethReceivedInEth * 1 ether, knocksSent, knocksAccepted, knocksRejected);

        // Generate SVG
        string memory svg = metadata.generateSVG(user);

        // Save to file
        string memory path = string(abi.encodePacked("./svg-preview/knockcard_", filename, ".svg"));
        vm.writeFile(path, svg);

        console.log("  [OK] %s", filename);
    }
}

/**
 * @title MockKnockProtocol
 * @notice Mock protocol for testing SVG generation
 */
contract MockKnockProtocol {
    KnockCard public knockCard;

    constructor() {
        knockCard = new KnockCard(address(this));
    }

    function setMetadataContract(address _metadata) external {
        knockCard.setMetadataContract(_metadata);
    }

    function setCardStats(address user, uint256 ethReceived, uint256 sent, uint256 accepted, uint256 rejected) external {
        knockCard.addEthReceived(user, ethReceived);
        for (uint256 i = 0; i < sent; i++) {
            knockCard.incrementKnocksSent(user);
        }
        for (uint256 i = 0; i < accepted; i++) {
            knockCard.incrementKnocksAccepted(user);
        }
        for (uint256 i = 0; i < rejected; i++) {
            knockCard.incrementKnocksRejected(user);
        }
    }
}
