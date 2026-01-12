// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NFTFactory, SocialNFT} from "../src/tools/NFTFactory.sol";
import {NFTMetadata} from "../src/tools/NFTMetadata.sol";

/**
 * @title SimulateHeritageBottle
 * @notice Simulate a heritage drift bottle - messages passing across generations
 * @dev Run with: forge script script/SimulateHeritageBottle.s.sol -vvv
 */
contract SimulateHeritageBottle is Script {
    NFTFactory public factory;
    NFTMetadata public metadata;
    SocialNFT public nft;

    // Family addresses (6 generations for ~50 messages)
    address public greatGreatGrandpa = address(0x1920); // Born ~1920
    address public greatGrandpa = address(0x1940); // Born ~1940
    address public grandpa = address(0x1960); // Born ~1960
    address public father = address(0x1985); // Born ~1985
    address public son = address(0x2010); // Born ~2010
    address public grandson = address(0x2035); // Born ~2035

    function run() external {
        console.log("=== Heritage Drift Bottle Simulation ===");
        console.log("=== A Family's Cross-Generational Journey ===");
        console.log("");

        // Deploy contracts
        metadata = new NFTMetadata();
        factory = new NFTFactory(address(metadata));

        // Great-great-grandpa creates the heritage bottle in 1970
        vm.prank(greatGreatGrandpa);
        address nftAddress = factory.createERC721Free(
            unicode"Wang Family Heritage",
            "HERITAGE",
            unicode"Messages across generations - from ancestors to future descendants",
            "https://biubiu.tools",
            true
        );
        nft = SocialNFT(nftAddress);

        console.log("Collection created: %s", nftAddress);
        console.log("");
        console.log("Family Tree (6 Generations):");
        console.log("  Great-Great-Grandpa (1920): %s", greatGreatGrandpa);
        console.log("  Great-Grandpa (1940):       %s", greatGrandpa);
        console.log("  Grandpa (1960):             %s", grandpa);
        console.log("  Father (1985):              %s", father);
        console.log("  Son (2010):                 %s", son);
        console.log("  Grandson (2035):            %s", grandson);
        console.log("");

        // Great-great-grandpa mints the heritage token
        vm.prank(greatGreatGrandpa);
        uint256 tokenId = nft.mint(
            greatGreatGrandpa, unicode"Family Time Capsule", unicode"Words for my children and their children, forever"
        );
        console.log("Token minted: #%d", tokenId);
        console.log("");

        uint256 msgCount = 0;

        // ========== Great-Great-Grandpa's Era (1970-1985) ==========
        // Message 1
        vm.warp(31536000); // 1971
        vm.prank(greatGreatGrandpa);
        nft.driftWithMessage(
            greatGrandpa,
            tokenId,
            unicode"1971 - 儿子，这是我们家的第一个时间胶囊。战争年代出生的我，见证了太多苦难。希望你们这一代能过上和平的生活。"
        );
        console.log("[1971] Great-Great-Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 2
        vm.warp(94608000); // 1973
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            greatGreatGrandpa,
            tokenId,
            unicode"1973 - 父亲，感谢您的教诲。我刚结婚了，会好好经营这个家。"
        );
        console.log("[1973] Great-Grandpa -> Great-Great-Grandpa: Message %d", ++msgCount);

        // Message 3
        vm.warp(157680000); // 1975
        vm.prank(greatGreatGrandpa);
        nft.driftWithMessage(
            greatGrandpa,
            tokenId,
            unicode"1975 - 听说你有孩子了？太好了！记住要教育孩子勤俭节约。"
        );
        console.log("[1975] Great-Great-Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 4
        vm.warp(220752000); // 1977
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            greatGreatGrandpa,
            tokenId,
            unicode"1977 - 是的父亲，我给他取名叫建国。他很聪明，将来一定有出息。"
        );
        console.log("[1977] Great-Grandpa -> Great-Great-Grandpa: Message %d", ++msgCount);

        // Message 5
        vm.warp(283824000); // 1979
        vm.prank(greatGreatGrandpa);
        nft.driftWithMessage(
            greatGrandpa,
            tokenId,
            unicode"1979 - 改革开放了！这是个好时代，要把握机会。我老了，这个传家宝交给你保管。"
        );
        console.log("[1979] Great-Great-Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 6
        vm.warp(346896000); // 1981
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            greatGreatGrandpa,
            tokenId,
            unicode"1981 - 父亲走了...但他的话永远在这里。我会把这个传承下去。"
        );
        console.log("[1981] Great-Grandpa -> (to record): Message %d", ++msgCount);

        // Message 7
        vm.warp(410000000); // 1983
        vm.prank(greatGreatGrandpa);
        nft.driftWithMessage(
            greatGrandpa, tokenId, unicode"1983 - 建国考上大学了！第一个大学生！我在天上看着呢。"
        );
        console.log("[1983] Great-Great-Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 8
        vm.warp(473385600); // 1985
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa,
            tokenId,
            unicode"1985 - 建国，你大学毕业了。这是咱家的传家宝，从你太爷爷那传下来的。好好保管。"
        );
        console.log("[1985] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // ========== Grandpa's Era (1985-2010) ==========
        // Message 9
        vm.warp(536457600); // 1987
        vm.prank(grandpa);
        nft.driftWithMessage(
            greatGrandpa, tokenId, unicode"1987 - 爸，我找到工作了，在国企上班。会努力的！"
        );
        console.log("[1987] Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 10
        vm.warp(599616000); // 1989
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"1989 - 好好干！听说你谈恋爱了？什么时候带回家看看？"
        );
        console.log("[1989] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // Message 11
        vm.warp(662688000); // 1991
        vm.prank(grandpa);
        nft.driftWithMessage(greatGrandpa, tokenId, unicode"1991 - 爸，我结婚了！她叫小红，很贤惠。");
        console.log("[1991] Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 12
        vm.warp(725846400); // 1993
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"1993 - 恭喜你们有孩子了！我当爷爷了！哈哈哈！"
        );
        console.log("[1993] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // Message 13
        vm.warp(788918400); // 1995
        vm.prank(grandpa);
        nft.driftWithMessage(
            greatGrandpa, tokenId, unicode"1995 - 小明两岁了，会叫爷爷了。您什么时候来看看？"
        );
        console.log("[1995] Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 14
        vm.warp(852076800); // 1997
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"1997 - 香港回归了！我活着看到了这一天！太激动了！"
        );
        console.log("[1997] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // Message 15
        vm.warp(915148800); // 1999
        vm.prank(grandpa);
        nft.driftWithMessage(
            greatGrandpa, tokenId, unicode"1999 - 新世纪要来了！小明上学了，成绩很好。"
        );
        console.log("[1999] Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 16
        vm.warp(978307200); // 2001
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2001 - 中国入世了！申奥成功了！我们国家越来越好了！"
        );
        console.log("[2001] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // Message 17
        vm.warp(1041379200); // 2003
        vm.prank(grandpa);
        nft.driftWithMessage(
            greatGrandpa, tokenId, unicode"2003 - 非典那年，全家平安。小明10岁了，想当科学家。"
        );
        console.log("[2003] Grandpa -> Great-Grandpa: Message %d", ++msgCount);

        // Message 18
        vm.warp(1104537600); // 2005
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa,
            tokenId,
            unicode"2005 - 我身体不太好了...但看到家族兴旺，很欣慰。这个传家宝，你要好好传下去。"
        );
        console.log("[2005] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // Message 19
        vm.warp(1167609600); // 2007
        vm.prank(grandpa);
        nft.driftWithMessage(
            greatGrandpa,
            tokenId,
            unicode"2007 - 爸走了...但区块链会永远保存他的话。小明说要学计算机。"
        );
        console.log("[2007] Grandpa -> (to record): Message %d", ++msgCount);

        // Message 20
        vm.warp(1230768000); // 2009
        vm.prank(greatGrandpa);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2009 - 比特币诞生了！虽然我不在了，但科技在进步。"
        );
        console.log("[2009] Great-Grandpa -> Grandpa: Message %d", ++msgCount);

        // ========== Father's Era (2010-2035) ==========
        // Message 21
        vm.warp(1293840000); // 2011
        vm.prank(grandpa);
        nft.driftWithMessage(
            father,
            tokenId,
            unicode"2011 - 小明，你考上大学了！计算机专业，将来一定有出息。这是咱家的传家宝。"
        );
        console.log("[2011] Grandpa -> Father: Message %d", ++msgCount);

        // Message 22
        vm.warp(1356998400); // 2013
        vm.prank(father);
        nft.driftWithMessage(
            grandpa,
            tokenId,
            unicode"2013 - 爸，大学很有意思！我学了区块链，这个传家宝太适合放在链上了！"
        );
        console.log("[2013] Father -> Grandpa: Message %d", ++msgCount);

        // Message 23
        vm.warp(1420070400); // 2015
        vm.prank(grandpa);
        nft.driftWithMessage(
            father, tokenId, unicode"2015 - 你说的那个什么链？听不太懂，但只要是好东西就行。"
        );
        console.log("[2015] Grandpa -> Father: Message %d", ++msgCount);

        // Message 24
        vm.warp(1483228800); // 2017
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2017 - 爸，我毕业了，找到好工作了！在互联网公司上班。"
        );
        console.log("[2017] Father -> Grandpa: Message %d", ++msgCount);

        // Message 25
        vm.warp(1546300800); // 2019
        vm.prank(grandpa);
        nft.driftWithMessage(
            father, tokenId, unicode"2019 - 好好干！对了，你什么时候结婚？我想抱孙子了。"
        );
        console.log("[2019] Grandpa -> Father: Message %d", ++msgCount);

        // Message 26
        vm.warp(1609459200); // 2021
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2021 - 爸，我结婚了！疫情期间，婚礼简单但很温馨。"
        );
        console.log("[2021] Father -> Grandpa: Message %d", ++msgCount);

        // Message 27
        vm.warp(1672531200); // 2023
        vm.prank(grandpa);
        nft.driftWithMessage(
            father, tokenId, unicode"2023 - 恭喜！听说你们有宝宝了？我终于当太爷爷了！"
        );
        console.log("[2023] Grandpa -> Father: Message %d", ++msgCount);

        // Message 28
        vm.warp(1704067200); // 2024
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2024 - 是的爸！我把传家宝升级成NFT了，永远不会丢失！"
        );
        console.log("[2024] Father -> Grandpa: Message %d", ++msgCount);

        // Message 29
        vm.warp(1735689600); // 2025
        vm.prank(grandpa);
        nft.driftWithMessage(
            father, tokenId, unicode"2025 - NFT？虽然不太懂，但只要家族的记忆能传下去就好。"
        );
        console.log("[2025] Grandpa -> Father: Message %d", ++msgCount);

        // Message 30
        vm.warp(1767225600); // 2026
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2026 - 小宝三岁了，会看这些留言了。他问太太太爷爷是谁。"
        );
        console.log("[2026] Father -> Grandpa: Message %d", ++msgCount);

        // Message 31
        vm.warp(1798761600); // 2027
        vm.prank(grandpa);
        nft.driftWithMessage(
            father,
            tokenId,
            unicode"2027 - 告诉他，那是我们家族的根。我身体还硬朗，想多陪陪曾孙。"
        );
        console.log("[2027] Grandpa -> Father: Message %d", ++msgCount);

        // Message 32
        vm.warp(1830297600); // 2028
        vm.prank(father);
        nft.driftWithMessage(
            grandpa,
            tokenId,
            unicode"2028 - 爸您放心，小宝很喜欢听您讲故事。这个周末带他去看您。"
        );
        console.log("[2028] Father -> Grandpa: Message %d", ++msgCount);

        // Message 33
        vm.warp(1861920000); // 2029
        vm.prank(grandpa);
        nft.driftWithMessage(
            father,
            tokenId,
            unicode"2029 - AI时代来了，但人情味不能丢。这个传家宝要一直传下去。"
        );
        console.log("[2029] Grandpa -> Father: Message %d", ++msgCount);

        // Message 34
        vm.warp(1893456000); // 2030
        vm.prank(father);
        nft.driftWithMessage(
            grandpa,
            tokenId,
            unicode"2030 - 小宝开始上学了，成绩很好。我会教他珍惜这个传家宝的。"
        );
        console.log("[2030] Father -> Grandpa: Message %d", ++msgCount);

        // Message 35
        vm.warp(1924992000); // 2031
        vm.prank(grandpa);
        nft.driftWithMessage(father, tokenId, unicode"2031 - 我今年71了...看着曾孙长大，人生无憾了。");
        console.log("[2031] Grandpa -> Father: Message %d", ++msgCount);

        // Message 36
        vm.warp(1956528000); // 2032
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2032 - 爸您会长命百岁的！小宝说要给您画一幅画。"
        );
        console.log("[2032] Father -> Grandpa: Message %d", ++msgCount);

        // Message 37
        vm.warp(1988150400); // 2033
        vm.prank(grandpa);
        nft.driftWithMessage(father, tokenId, unicode"2033 - 收到画了，很漂亮！这孩子有艺术天赋。");
        console.log("[2033] Grandpa -> Father: Message %d", ++msgCount);

        // Message 38
        vm.warp(2019686400); // 2034
        vm.prank(father);
        nft.driftWithMessage(
            grandpa, tokenId, unicode"2034 - 爸，您的健康检查结果很好！我们全家都很开心。"
        );
        console.log("[2034] Father -> Grandpa: Message %d", ++msgCount);

        // Message 39
        vm.warp(2051222400); // 2035
        vm.prank(grandpa);
        nft.driftWithMessage(
            father, tokenId, unicode"2035 - 小宝25岁了，该成家了。这个传家宝也该传给他了。"
        );
        console.log("[2035] Grandpa -> Father: Message %d", ++msgCount);

        // Message 40
        vm.warp(2082758400); // 2036
        vm.prank(father);
        nft.driftWithMessage(
            son,
            tokenId,
            unicode"2036 - 儿子，这是咱家传了五代的宝贝。从你太太太爷爷开始，每一代人都在这里留下了话。好好珍惜。"
        );
        console.log("[2036] Father -> Son: Message %d", ++msgCount);

        // ========== Son's Era (2036-2060) ==========
        // Message 41
        vm.warp(2114294400); // 2037
        vm.prank(son);
        nft.driftWithMessage(
            father,
            tokenId,
            unicode"2037 - 爸，我看了所有留言，太感动了。从1971年到现在，66年了！"
        );
        console.log("[2037] Son -> Father: Message %d", ++msgCount);

        // Message 42
        vm.warp(2145830400); // 2038
        vm.prank(father);
        nft.driftWithMessage(
            son, tokenId, unicode"2038 - 是啊，这是区块链最好的用途——保存家族记忆。"
        );
        console.log("[2038] Father -> Son: Message %d", ++msgCount);

        // Message 43
        vm.warp(2177452800); // 2039
        vm.prank(son);
        nft.driftWithMessage(father, tokenId, unicode"2039 - 我结婚了！她很喜欢这个传家宝的故事。");
        console.log("[2039] Son -> Father: Message %d", ++msgCount);

        // Message 44
        vm.warp(2208988800); // 2040
        vm.prank(father);
        nft.driftWithMessage(
            son, tokenId, unicode"2040 - 恭喜！爷爷今年80了，身体还不错。他很高兴看到你成家。"
        );
        console.log("[2040] Father -> Son: Message %d", ++msgCount);

        // Message 45
        vm.warp(2240524800); // 2041
        vm.prank(son);
        nft.driftWithMessage(
            father, tokenId, unicode"2041 - 我们有孩子了！取名叫小龙，寓意龙的传人。"
        );
        console.log("[2041] Son -> Father: Message %d", ++msgCount);

        // Message 46
        vm.warp(2272147200); // 2042
        vm.prank(father);
        nft.driftWithMessage(
            son, tokenId, unicode"2042 - 爷爷走了...但他的话永远在链上。小龙以后会读到的。"
        );
        console.log("[2042] Father -> Son: Message %d", ++msgCount);

        // Message 47
        vm.warp(2303683200); // 2043
        vm.prank(son);
        nft.driftWithMessage(
            father, tokenId, unicode"2043 - 我会把爷爷的故事讲给小龙听的。这个传家宝太珍贵了。"
        );
        console.log("[2043] Son -> Father: Message %d", ++msgCount);

        // Message 48
        vm.warp(2335219200); // 2044
        vm.prank(father);
        nft.driftWithMessage(
            son, tokenId, unicode"2044 - 我也老了...但看到家族繁荣，很欣慰。继续传下去。"
        );
        console.log("[2044] Father -> Son: Message %d", ++msgCount);

        // Message 49
        vm.warp(2366841600); // 2045
        vm.prank(son);
        nft.driftWithMessage(
            grandson,
            tokenId,
            unicode"2045 - 小龙，你也长大了。这是咱家的传家宝，从1971年传下来的。现在轮到你保管了。"
        );
        console.log("[2045] Son -> Grandson: Message %d", ++msgCount);

        // Message 50
        vm.warp(2398377600); // 2046
        vm.prank(grandson);
        nft.leaveMessage(
            tokenId,
            unicode"2046 - 我读完了所有留言，从太太太太爷爷到现在，跨越了75年。这是真正的时间胶囊。我会继续传递下去，让王家的爱永远流传。"
        );
        console.log("[2046] Grandson: Message %d (Final)", ++msgCount);

        console.log("");
        console.log("=== Heritage Journey Complete ===");
        console.log("Total messages spanning 75 years (1971-2046): %d", nft.getDriftCount(tokenId));

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
                "       WANG FAMILY HERITAGE - TIME CAPSULE\n",
                "       A Blockchain-Based Cross-Generational Journey\n",
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
                "FAMILY TREE (6 Generations)\n",
                "---------------------------\n",
                "Great-Great-Grandpa (1920): ",
                _toHexString(greatGreatGrandpa),
                "\n",
                "Great-Grandpa (1940):       ",
                _toHexString(greatGrandpa),
                "\n",
                "Grandpa (1960):             ",
                _toHexString(grandpa),
                "\n"
            )
        );

        txt = string(
            abi.encodePacked(
                txt,
                "Father (1985):              ",
                _toHexString(father),
                "\n",
                "Son (2010):                 ",
                _toHexString(son),
                "\n",
                "Grandson (2035):            ",
                _toHexString(grandson),
                "\n\n",
                "=====================================================\n",
                "                    MESSAGES\n",
                "=====================================================\n\n"
            )
        );

        for (uint256 i = 0; i < total; i++) {
            string memory generation = _getGeneration(allMessages[i].from);

            txt = string(
                abi.encodePacked(
                    txt,
                    "--- Message #",
                    _toString(i + 1),
                    " ---\n",
                    "From: ",
                    generation,
                    "\n",
                    "Address: ",
                    _toHexString(allMessages[i].from),
                    "\n",
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
                "This heritage record is permanently stored on the blockchain.\n",
                "No government, company, or individual can alter or delete it.\n",
                "These words will exist as long as the blockchain exists.\n\n",
                "Generated by BiuBiu Tools - https://biubiu.tools\n"
            )
        );

        // Create output directory and save
        vm.createDir("./simulation-output", true);
        vm.writeFile("./simulation-output/heritage-bottle.txt", txt);
        console.log("");
        console.log("TXT exported to: ./simulation-output/heritage-bottle.txt");
    }

    function _getGeneration(address addr) internal view returns (string memory) {
        if (addr == greatGreatGrandpa) return "Great-Great-Grandpa (1st Gen)";
        if (addr == greatGrandpa) return "Great-Grandpa (2nd Gen)";
        if (addr == grandpa) return "Grandpa (3rd Gen)";
        if (addr == father) return "Father (4th Gen)";
        if (addr == son) return "Son (5th Gen)";
        if (addr == grandson) return "Grandson (6th Gen)";
        return "Unknown";
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
