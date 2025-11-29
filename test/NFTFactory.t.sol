// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTFactory, SimpleERC721} from "../src/NFTFactory.sol";

// Mock ERC20 for testing
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract NFTFactoryTest is Test {
    NFTFactory public factory;
    MockERC20 public memeToken;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        factory = new NFTFactory();
        memeToken = new MockERC20();

        // Give users some tokens
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        memeToken.mint(alice, 1000000 ether);
        memeToken.mint(bob, 1000000 ether);
        memeToken.mint(charlie, 1000000 ether);
    }

    // ========== ERC721 Tests ==========

    function test_CreateERC721Basic() public {
        vm.prank(alice);
        address nftAddr = factory.createERC721("My NFT", "MNFT", "ipfs://base/", true, false, address(0), 0);

        SimpleERC721 nft = SimpleERC721(nftAddr);
        assertEq(nft.name(), "My NFT");
        assertEq(nft.symbol(), "MNFT");
        assertEq(nft.owner(), alice);
    }

    function test_ERC721StakeToMint() public {
        // Alice creates NFT with stake-to-mint
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("Meme NFT", "MEME", "ipfs://meme/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Bob stakes to mint
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.stakedAmount(tokenId), 1000 ether);
        assertEq(memeToken.balanceOf(nftAddr), 1000 ether);
    }

    function test_ERC721BurnToRedeem() public {
        // Create and mint
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("Meme NFT", "MEME", "ipfs://meme/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 tokenId = nft.stakeToMint();

        uint256 balanceBefore = memeToken.balanceOf(bob);

        // Burn to redeem
        nft.burnToRedeem(tokenId);
        vm.stopPrank();

        assertEq(nft.balanceOf(bob), 0);
        assertEq(memeToken.balanceOf(bob), balanceBefore + 1000 ether);
        assertEq(memeToken.balanceOf(nftAddr), 0);
    }

    function test_ERC721MultipleStakeAndRedeem() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("Meme NFT", "MEME", "ipfs://meme/", true, true, address(memeToken), 500 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Bob mints 3 NFTs
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1500 ether);

        uint256 tokenId1 = nft.stakeToMint();
        uint256 tokenId2 = nft.stakeToMint();
        uint256 tokenId3 = nft.stakeToMint();

        assertEq(nft.balanceOf(bob), 3);
        assertEq(memeToken.balanceOf(nftAddr), 1500 ether);

        // Redeem only tokenId2
        nft.burnToRedeem(tokenId2);

        assertEq(nft.balanceOf(bob), 2);
        assertEq(memeToken.balanceOf(nftAddr), 1000 ether);

        vm.stopPrank();
    }

    function test_ERC721StakeToMintNotEnabled() public {
        vm.prank(alice);
        address nftAddr = factory.createERC721("Regular NFT", "REG", "ipfs://reg/", true, false, address(0), 0);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        vm.startPrank(bob);
        vm.expectRevert("Stake-to-mint not enabled");
        nft.stakeToMint();
        vm.stopPrank();
    }

    // ========== Factory Tests ==========

    function test_TrackUserNFTs() public {
        vm.startPrank(alice);
        address nft1 = factory.createERC721("NFT1", "N1", "ipfs://1/", true, false, address(0), 0);
        address nft2 = factory.createERC721("NFT2", "N2", "ipfs://2/", true, false, address(0), 0);
        vm.stopPrank();

        address[] memory aliceNFTs = factory.getUserNFTs(alice);
        assertEq(aliceNFTs.length, 2);
        assertEq(aliceNFTs[0], nft1);
        assertEq(aliceNFTs[1], nft2);

        assertEq(factory.allNFTsLength(), 2);
    }

    function test_GetNFTInfo() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("InfoNFT", "INFO", "ipfs://info/", true, true, address(memeToken), 1000 ether);

        NFTFactory.NFTInfo memory info = factory.getNFTInfo(nftAddr);

        assertEq(info.nftAddress, nftAddr);
        assertEq(info.name, "InfoNFT");
        assertEq(info.symbol, "INFO");
        assertEq(info.creator, alice);
        assertTrue(info.stakeToMintEnabled);
        assertEq(info.stakeToken, address(memeToken));
    }

    function test_PaginationUserNFTs() public {
        // Alice creates 5 NFTs
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            factory.createERC721(
                string(abi.encodePacked("NFT", _toString(i))),
                string(abi.encodePacked("N", _toString(i))),
                "ipfs://test/",
                true,
                false,
                address(0),
                0
            );
        }
        vm.stopPrank();

        // Get page 1 (offset 0, limit 2)
        (address[] memory page1, uint256 total1) = factory.getUserNFTsPaginated(alice, 0, 2);
        assertEq(total1, 5);
        assertEq(page1.length, 2);

        // Get page 2 (offset 2, limit 2)
        (address[] memory page2, uint256 total2) = factory.getUserNFTsPaginated(alice, 2, 2);
        assertEq(total2, 5);
        assertEq(page2.length, 2);

        // Get page 3 (offset 4, limit 2) - should only get 1
        (address[] memory page3, uint256 total3) = factory.getUserNFTsPaginated(alice, 4, 2);
        assertEq(total3, 5);
        assertEq(page3.length, 1);

        // Out of bounds
        (address[] memory page4, uint256 total4) = factory.getUserNFTsPaginated(alice, 10, 2);
        assertEq(total4, 5);
        assertEq(page4.length, 0);
    }

    function test_PaginationUserNFTsInfo() public {
        // Alice creates 3 NFTs
        vm.startPrank(alice);
        factory.createERC721("NFT0", "N0", "ipfs://0/", true, false, address(0), 0);
        factory.createERC721("NFT1", "N1", "ipfs://1/", true, true, address(memeToken), 100 ether);
        factory.createERC721("NFT2", "N2", "ipfs://2/", true, false, address(0), 0);
        vm.stopPrank();

        (NFTFactory.NFTInfo[] memory infos, uint256 total) = factory.getUserNFTsInfoPaginated(alice, 0, 10);

        assertEq(total, 3);
        assertEq(infos.length, 3);
        assertEq(infos[0].name, "NFT0");
        assertEq(infos[1].name, "NFT1");
        assertEq(infos[2].name, "NFT2");
        assertFalse(infos[0].stakeToMintEnabled);
        assertTrue(infos[1].stakeToMintEnabled);
        assertEq(infos[1].stakeToken, address(memeToken));
    }

    function test_PaginationAllNFTs() public {
        // Alice creates 2, Bob creates 3
        vm.startPrank(alice);
        factory.createERC721("Alice1", "A1", "ipfs://a1/", true, false, address(0), 0);
        factory.createERC721("Alice2", "A2", "ipfs://a2/", true, false, address(0), 0);
        vm.stopPrank();

        vm.startPrank(bob);
        factory.createERC721("Bob1", "B1", "ipfs://b1/", true, false, address(0), 0);
        factory.createERC721("Bob2", "B2", "ipfs://b2/", true, false, address(0), 0);
        factory.createERC721("Bob3", "B3", "ipfs://b3/", true, false, address(0), 0);
        vm.stopPrank();

        (address[] memory allNFTs, uint256 total) = factory.getAllNFTsPaginated(0, 3);
        assertEq(total, 5);
        assertEq(allNFTs.length, 3);

        (NFTFactory.NFTInfo[] memory allInfos, uint256 totalInfos) = factory.getAllNFTsInfoPaginated(0, 10);
        assertEq(totalInfos, 5);
        assertEq(allInfos.length, 5);
        assertEq(allInfos[0].name, "Alice1");
        assertEq(allInfos[4].name, "Bob3");
    }

    // Helper function
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

    // ========== Transfer with Stake Tests ==========

    function test_TransferNFTWithStake() public {
        // Alice creates NFT with stake-to-mint
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("StakeNFT", "SNFT", "ipfs://stake/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Bob mints NFT by staking 1000 MEME
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Verify Bob owns the NFT with 1000 MEME staked
        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.stakedAmount(tokenId), 1000 ether);

        // Bob transfers NFT to Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        // Charlie now owns the NFT
        assertEq(nft.ownerOf(tokenId), charlie);
        // Staked amount is still bound to tokenId
        assertEq(nft.stakedAmount(tokenId), 1000 ether);

        // Charlie can redeem the staked tokens
        vm.prank(charlie);
        nft.burnToRedeem(tokenId);

        // Charlie got the 1000 MEME
        assertEq(memeToken.balanceOf(charlie), 1000000 ether + 1000 ether);
    }

    function test_TransferNFTWithStakeValue() public {
        // Demonstrate that NFT with stake has more value
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("ValueNFT", "VNFT", "ipfs://value/", true, true, address(memeToken), 5000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Bob mints NFT by staking 5000 MEME
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 5000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Bob sells NFT to Charlie (transfer = sale in this scenario)
        // The NFT is worth: NFT value + 5000 MEME guaranteed redemption value
        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        // Charlie can always redeem minimum 5000 MEME
        uint256 charlieBalanceBefore = memeToken.balanceOf(charlie);
        vm.prank(charlie);
        nft.burnToRedeem(tokenId);

        assertEq(memeToken.balanceOf(charlie), charlieBalanceBefore + 5000 ether);
    }

    function test_MultipleTransfersPreserveStake() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("MultiNFT", "MNFT", "ipfs://multi/", true, true, address(memeToken), 2000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Bob mints
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 2000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Bob → Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);
        assertEq(nft.stakedAmount(tokenId), 2000 ether);

        // Charlie → Alice
        vm.prank(charlie);
        nft.transferFrom(charlie, alice, tokenId);
        assertEq(nft.stakedAmount(tokenId), 2000 ether);

        // Alice redeems
        vm.prank(alice);
        nft.burnToRedeem(tokenId);
        // Alice should get the full 2000 MEME
        assertEq(memeToken.balanceOf(alice), 1000000 ether + 2000 ether);
    }

    function test_BobCannotRedeemAfterTransfer() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("NoRedeemNFT", "NR", "ipfs://nr/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Bob transfers to Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        // Bob tries to redeem but fails (not owner anymore)
        vm.prank(bob);
        vm.expectRevert("Not token owner");
        nft.burnToRedeem(tokenId);

        // Charlie can redeem
        vm.prank(charlie);
        nft.burnToRedeem(tokenId);
    }

    function test_CanRedeemFunction() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("RedeemCheck", "RC", "ipfs://rc/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Mint NFT with stake
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Check can redeem
        assertTrue(nft.canRedeem(tokenId));
        assertEq(nft.getRedeemableAmount(tokenId), 1000 ether);

        // After burning, cannot redeem anymore
        vm.prank(bob);
        nft.burnToRedeem(tokenId);

        assertFalse(nft.canRedeem(tokenId));
        assertEq(nft.getRedeemableAmount(tokenId), 0);
    }

    function test_TransferPreservesRedeemability() public {
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("TransferRedeem", "TR", "ipfs://tr/", true, true, address(memeToken), 500 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        vm.startPrank(bob);
        memeToken.approve(nftAddr, 500 ether);
        uint256 tokenId = nft.stakeToMint();
        vm.stopPrank();

        // Bob can redeem
        assertTrue(nft.canRedeem(tokenId));

        // Transfer to Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        // Still redeemable (by Charlie now)
        assertTrue(nft.canRedeem(tokenId));
        assertEq(nft.getRedeemableAmount(tokenId), 500 ether);
    }

    // ========== Game Mechanic Tests ==========

    function test_MemeGameMechanic() public {
        // Simulate pump.fun style game
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("PumpNFT", "PUMP", "ipfs://pump/", true, true, address(memeToken), 1000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        // Early adopter Bob gets NFT #0
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 bobTokenId = nft.stakeToMint();
        assertEq(bobTokenId, 0); // First NFT!
        vm.stopPrank();

        // Charlie gets NFT #1
        vm.startPrank(charlie);
        memeToken.approve(nftAddr, 1000 ether);
        uint256 charlieTokenId = nft.stakeToMint();
        assertEq(charlieTokenId, 1);
        vm.stopPrank();

        // Total staked = 2000 MEME locked
        assertEq(memeToken.balanceOf(nftAddr), 2000 ether);

        // Bob decides to cash out
        vm.prank(bob);
        nft.burnToRedeem(bobTokenId);

        // Total staked = 1000 MEME locked
        assertEq(memeToken.balanceOf(nftAddr), 1000 ether);
        assertEq(nft.totalSupply(), 1);
    }

    function test_TokenPriceImpact() public {
        // Demonstrate price support mechanism
        vm.prank(alice);
        address nftAddr =
            factory.createERC721("Support NFT", "SUP", "ipfs://sup/", true, true, address(memeToken), 10000 ether);

        SimpleERC721 nft = SimpleERC721(nftAddr);

        uint256 initialCirculation = memeToken.balanceOf(bob);

        // Bob stakes 10,000 MEME
        vm.startPrank(bob);
        memeToken.approve(nftAddr, 10000 ether);
        nft.stakeToMint();
        vm.stopPrank();

        uint256 afterMintCirculation = memeToken.balanceOf(bob);

        // Circulation decreased by 10,000 MEME
        assertEq(initialCirculation - afterMintCirculation, 10000 ether);

        // This reduces sell pressure on MEME token!
    }
}
