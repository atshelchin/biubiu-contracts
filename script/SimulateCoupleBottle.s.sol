// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NFTFactory, SocialNFT} from "../src/tools/NFTFactory.sol";
import {NFTMetadata} from "../src/tools/NFTMetadata.sol";

/**
 * @title SimulateCoupleBottle
 * @notice Simulate a couple's drift bottle - two people passing messages back and forth
 * @dev Run with: forge script script/SimulateCoupleBottle.s.sol -vvv
 */
contract SimulateCoupleBottle is Script {
    NFTFactory public factory;
    NFTMetadata public metadata;
    SocialNFT public nft;

    // Couple addresses
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    // Messages from their love story
    string[] public aliceMessages;
    string[] public bobMessages;

    function setUp() public {
        // Alice's messages (25 messages for ~50 total)
        // 2024 - Dating year
        aliceMessages.push(unicode"2024.02.14 - 第一次约会，你送了我一朵玫瑰 🌹");
        aliceMessages.push(unicode"2024.04.05 - 清明节一起去踏青，阳光正好");
        aliceMessages.push(unicode"2024.05.20 - 520快乐，我爱你 ❤️");
        aliceMessages.push(unicode"2024.07.07 - 七夕节，你给我讲牛郎织女的故事");
        aliceMessages.push(unicode"2024.08.15 - 一起看了流星雨，许愿永远在一起");
        aliceMessages.push(unicode"2024.10.01 - 国庆假期一起去了厦门，海边真美");
        aliceMessages.push(unicode"2024.11.11 - 双十一你给我买了好多礼物，感动");
        // 2025 - Engagement year
        aliceMessages.push(unicode"2025.01.01 - 新年快乐！希望我们永远这样幸福");
        aliceMessages.push(unicode"2025.02.14 - 一周年纪念日，感谢有你");
        aliceMessages.push(unicode"2025.03.08 - 你说我是你的女神，我好开心");
        aliceMessages.push(unicode"2025.05.01 - 劳动节在家做饭，你的厨艺进步了");
        aliceMessages.push(unicode"2025.06.01 - 儿童节我们去游乐园玩了一整天");
        aliceMessages.push(unicode"2025.07.20 - 夏天太热了，谢谢你每天给我送冰奶茶");
        aliceMessages.push(unicode"2025.08.28 - 你生日快乐！送你一个大蛋糕 🎂");
        aliceMessages.push(unicode"2025.10.01 - 我们订婚了！");
        aliceMessages.push(unicode"2025.11.22 - 开始筹备婚礼，好期待");
        // 2026 - Wedding year
        aliceMessages.push(unicode"2026.01.01 - 新的一年，我们要结婚了！");
        aliceMessages.push(unicode"2026.02.14 - 情人节，我们拍了婚纱照 📸");
        aliceMessages.push(unicode"2026.03.28 - 婚礼倒计时100天");
        aliceMessages.push(unicode"2026.05.20 - 今天是我们的婚礼！我爱你 👰💒");
        aliceMessages.push(unicode"2026.06.15 - 蜜月旅行在马尔代夫，太美了");
        aliceMessages.push(unicode"2026.08.08 - 有个好消息要告诉你...");
        aliceMessages.push(unicode"2026.10.10 - 宝宝第一次胎动，好神奇");
        aliceMessages.push(unicode"2026.12.25 - 圣诞节，宝宝应该能听到我们说话了");
        aliceMessages.push(unicode"2027.02.14 - 预产期快到了，好紧张又期待");

        // Bob's messages (25 messages)
        // 2024 - Dating year
        bobMessages.push(unicode"2024.03.08 - 女神节快乐，你是我的唯一");
        bobMessages.push(unicode"2024.04.20 - 周末一起去爬山，虽然累但很开心");
        bobMessages.push(unicode"2024.06.18 - 第一次见家长，有点紧张但很开心");
        bobMessages.push(unicode"2024.08.01 - 建军节，我会永远保护你");
        bobMessages.push(unicode"2024.09.10 - 教师节，谢谢你教会我什么是爱");
        bobMessages.push(unicode"2024.10.31 - 万圣节我们cosplay了，太搞笑了 🎃");
        bobMessages.push(unicode"2024.12.25 - 圣诞快乐，送你一颗星星 ⭐");
        // 2025 - Engagement year
        bobMessages.push(unicode"2025.01.15 - 一起看了雪，你说想和我白头偕老");
        bobMessages.push(unicode"2025.02.28 - 我们养了一只猫，取名叫团团 🐱");
        bobMessages.push(unicode"2025.04.04 - 清明节回老家，爷爷奶奶很喜欢你");
        bobMessages.push(unicode"2025.05.20 - 520，爱你比昨天更多一点");
        bobMessages.push(unicode"2025.06.18 - 认识你一年半了，每天都很幸福");
        bobMessages.push(unicode"2025.07.30 - 我要攒钱给你买个大钻戒 💍");
        bobMessages.push(unicode"2025.09.01 - 准备求婚了，好紧张！");
        bobMessages.push(unicode"2025.10.15 - 订婚宴上大家都祝福我们");
        bobMessages.push(unicode"2025.12.31 - 准备迎接我们的新年，也准备迎接新生活");
        // 2026 - Wedding year
        bobMessages.push(unicode"2026.01.23 - 过年带你回家，妈妈做了很多好吃的");
        bobMessages.push(unicode"2026.03.08 - 女神节，你永远是我最美的新娘");
        bobMessages.push(unicode"2026.04.15 - 婚礼请柬发出去了，朋友们都说要来");
        bobMessages.push(unicode"2026.05.19 - 明天就是婚礼了，一晚没睡着");
        bobMessages.push(unicode"2026.06.01 - 新婚快乐，老婆！");
        bobMessages.push(unicode"2026.07.20 - 开始布置婴儿房，粉色还是蓝色？");
        bobMessages.push(unicode"2026.09.09 - 陪你做产检，宝宝很健康");
        bobMessages.push(unicode"2026.11.11 - 今年的双十一都在买宝宝用品");
        bobMessages.push(unicode"2027.03.01 - 我们的宝宝出生了！欢迎来到这个世界 👶💕");
    }

    function run() external {
        console.log("=== Couple Drift Bottle Simulation ===");
        console.log("");

        // Deploy contracts
        metadata = new NFTMetadata();
        factory = new NFTFactory(address(metadata));

        // Alice creates the couple's drift bottle (onlyOwnerCanMint = true, private)
        vm.prank(alice);
        address nftAddress = factory.createERC721Free(
            unicode"Our Love Story 💕",
            "LOVE",
            unicode"A drift bottle between Alice and Bob, recording our love journey",
            "https://biubiu.tools",
            true // Only owner can mint - this is a private bottle
        );
        nft = SocialNFT(nftAddress);

        console.log("Collection created: %s", nftAddress);
        console.log("Alice: %s", alice);
        console.log("Bob: %s", bob);
        console.log("");

        // Alice mints the first token
        vm.prank(alice);
        uint256 tokenId = nft.mint(alice, unicode"Forever Us", unicode"Our eternal love capsule");
        console.log("Token minted: #%d", tokenId);
        console.log("");

        // Simulate the love story - alternating messages
        uint256 totalMessages = aliceMessages.length + bobMessages.length;
        uint256 aliceIdx = 0;
        uint256 bobIdx = 0;

        for (uint256 i = 0; i < totalMessages; i++) {
            if (i % 2 == 0 && aliceIdx < aliceMessages.length) {
                // Alice's turn
                vm.prank(alice);
                nft.driftWithMessage(bob, tokenId, aliceMessages[aliceIdx]);
                console.log("Alice -> Bob: %s", aliceMessages[aliceIdx]);
                aliceIdx++;
            } else if (bobIdx < bobMessages.length) {
                // Bob's turn
                vm.prank(bob);
                nft.driftWithMessage(alice, tokenId, bobMessages[bobIdx]);
                console.log("Bob -> Alice: %s", bobMessages[bobIdx]);
                bobIdx++;
            }
        }

        console.log("");
        console.log("=== Love Story Complete ===");
        console.log("Total messages: %d", nft.getDriftCount(tokenId));

        // Export to txt
        _exportToTxt(tokenId);
    }

    function _exportToTxt(uint256 tokenId) internal {
        // Use paginated query to get drift history
        uint256 pageSize = 10;
        uint256 offset = 0;

        (, uint256 total) = nft.getDriftHistoryPaginated(tokenId, 0, 1);

        // Collect all messages using pagination
        SocialNFT.DriftMessage[] memory allMessages = new SocialNFT.DriftMessage[](total);
        uint256 collected = 0;

        while (collected < total) {
            (SocialNFT.DriftMessage[] memory page,) = nft.getDriftHistoryPaginated(tokenId, offset, pageSize);
            for (uint256 i = 0; i < page.length; i++) {
                allMessages[collected] = page[i];
                collected++;
            }
            offset += pageSize;
        }

        string memory txt = string(
            abi.encodePacked(
                "=====================================================\n",
                "       OUR LOVE STORY - COUPLE DRIFT BOTTLE\n",
                "       A Blockchain-Based Love Journal\n",
                "=====================================================\n\n",
                "COLLECTION INFO\n",
                "---------------\n",
                "Name: ",
                nft.name(),
                "\n",
                "Symbol: ",
                nft.symbol(),
                "\n",
                "Token ID: 0\n",
                "Total Messages: ",
                _toString(total),
                "\n\n"
            )
        );

        txt = string(
            abi.encodePacked(
                txt,
                "PARTICIPANTS\n",
                "------------\n",
                "Alice: ",
                _toHexString(alice),
                "\n",
                "Bob:   ",
                _toHexString(bob),
                "\n\n",
                "=====================================================\n",
                "                  LOVE MESSAGES\n",
                "=====================================================\n\n"
            )
        );

        for (uint256 i = 0; i < total; i++) {
            string memory sender = allMessages[i].from == alice ? "Alice" : "Bob";
            string memory arrow = allMessages[i].from == alice ? "Alice -> Bob" : "Bob -> Alice";

            txt = string(
                abi.encodePacked(
                    txt,
                    "--- Message #",
                    _toString(i + 1),
                    " ---\n",
                    "Direction: ",
                    arrow,
                    "\n",
                    "From: ",
                    sender,
                    " (",
                    _toHexString(allMessages[i].from),
                    ")\n",
                    "Timestamp: ",
                    _toString(allMessages[i].timestamp),
                    "\n\n",
                    allMessages[i].message,
                    "\n\n"
                )
            );
        }

        txt = string(
            abi.encodePacked(
                txt,
                "=====================================================\n\n",
                "This love story is permanently recorded on the blockchain.\n",
                "No one can alter or delete these precious memories.\n\n",
                "Generated by BiuBiu Tools - https://biubiu.tools\n"
            )
        );

        // Create output directory and save
        vm.createDir("./simulation-output", true);
        vm.writeFile("./simulation-output/couple-bottle.txt", txt);
        console.log("");
        console.log("TXT exported to: ./simulation-output/couple-bottle.txt");
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        bytes memory hexChars = "0123456789abcdef";
        uint160 value = uint160(addr);
        for (uint256 i = 41; i > 1; i--) {
            buffer[i] = hexChars[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
