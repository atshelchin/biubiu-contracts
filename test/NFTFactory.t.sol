// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTFactory, SocialNFT} from "../src/NFTFactory.sol";

contract NFTFactoryTest is Test {
    NFTFactory public factory;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    event NFTCreated(
        address indexed nftAddress,
        address indexed creator,
        string name,
        string symbol,
        string description,
        uint8 usageType
    );
    event Minted(uint256 indexed tokenId, address indexed to, uint8 rarity, uint256 luckyNumber);
    event Drifted(uint256 indexed tokenId, address indexed from, address indexed to);
    event MessageLeft(uint256 indexed tokenId, address indexed by, string message);

    function setUp() public {
        factory = new NFTFactory();
    }

    // ========== Collection Creation Tests ==========

    function test_CreateCollectionBasic() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "A cool collection", "ipfs://base/");

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.name(), "My Collection");
        assertEq(nft.symbol(), "MC");
        assertEq(nft.collectionDescription(), "A cool collection");
        assertEq(nft.baseImageURI(), "ipfs://base/");
        assertEq(nft.owner(), alice);
        assertEq(nft.totalSupply(), 0);
    }

    function test_CreateCollectionEmitsEvent() public {
        vm.startPrank(alice);

        vm.expectEmit(false, true, false, false);
        emit NFTCreated(address(0), alice, "Test", "TST", "Test desc", 0);

        factory.createERC721Free("Test", "TST", "Test desc", "");

        vm.stopPrank();
    }

    function test_CreateCollectionEmptyNameReverts() public {
        vm.prank(alice);
        vm.expectRevert(NFTFactory.NameEmpty.selector);
        factory.createERC721Free("", "MC", "Description", "");
    }

    function test_CreateCollectionEmptySymbolReverts() public {
        vm.prank(alice);
        vm.expectRevert(NFTFactory.SymbolEmpty.selector);
        factory.createERC721Free("My Collection", "", "Description", "");
    }

    function test_CREATE2SameParamsDifferentCreators() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("My Collection", "MC", "Description", "");

        vm.prank(bob);
        address nft2 = factory.createERC721Free("My Collection", "MC", "Description", "");

        // Different creators = different addresses
        assertFalse(nft1 == nft2);
    }

    function test_SameCreatorSameParamsReverts() public {
        vm.startPrank(alice);
        factory.createERC721Free("My Collection", "MC", "Description", "");

        vm.expectRevert();
        factory.createERC721Free("My Collection", "MC", "Description", "");
        vm.stopPrank();
    }

    // ========== Minting Tests ==========

    function test_MintBasic() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "ipfs://base/");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token #1", "First token", "ipfs://image1");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.totalSupply(), 1);
    }

    function test_MintWithBaseURI() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "ipfs://base/");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mintWithBaseURI(bob, "Token #1", "First token");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
    }

    function test_MintOnlyOwner() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        // Bob tries to mint - should fail
        vm.prank(bob);
        vm.expectRevert(SocialNFT.NotOwner.selector);
        nft.mint(bob, "Token", "Desc", "image");
    }

    function test_MintToZeroAddressReverts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        vm.expectRevert(SocialNFT.InvalidRecipient.selector);
        nft.mint(address(0), "Token", "Desc", "image");
    }

    function test_MintGeneratesTraits() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token", "Desc", "image");

        (uint8 rarity, uint8 background, uint8 pattern, uint8 glow, uint256 luckyNumber) = nft.getTokenTraits(tokenId);

        // Verify traits are within expected ranges
        assertTrue(rarity <= 4); // 0-4 for rarity levels
        assertTrue(background < 10);
        assertTrue(pattern < 10);
        assertTrue(glow < 10);
        assertTrue(luckyNumber < 10000);
    }

    function test_MintMultipleTokens() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.startPrank(alice);
        nft.mint(bob, "Token 1", "First", "image1");
        nft.mint(charlie, "Token 2", "Second", "image2");
        nft.mint(bob, "Token 3", "Third", "image3");
        vm.stopPrank();

        assertEq(nft.totalSupply(), 3);
        assertEq(nft.balanceOf(bob), 2);
        assertEq(nft.balanceOf(charlie), 1);
        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.ownerOf(1), charlie);
        assertEq(nft.ownerOf(2), bob);
    }

    // ========== Drift (Transfer Message) System Tests ==========

    function test_TransferCreatesDrift() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        // Alice mints to Bob
        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Bob transfers to Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        // Check drift history
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 1);
        assertEq(history[0].from, bob);
        assertEq(bytes(history[0].message).length, 0); // No message yet
    }

    function test_LeaveMessage() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Bob transfers to Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        // Charlie leaves a message
        vm.prank(charlie);
        nft.leaveMessage(0, "Thanks for the NFT!");

        // Check message was recorded
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 1);
        assertEq(history[0].message, "Thanks for the NFT!");
    }

    function test_LeaveMessageOnlyTokenOwner() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        // Bob (not the current owner) tries to leave message
        vm.prank(bob);
        vm.expectRevert(SocialNFT.NotTokenOwner.selector);
        nft.leaveMessage(0, "Can I leave a message?");
    }

    function test_LeaveMessageNoDriftHistoryReverts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Bob tries to leave message but no transfer happened yet
        vm.prank(bob);
        vm.expectRevert(SocialNFT.NoDriftHistory.selector);
        nft.leaveMessage(0, "Hello");
    }

    function test_LeaveMessageAlreadyLeftReverts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        // Charlie leaves first message
        vm.prank(charlie);
        nft.leaveMessage(0, "First message");

        // Charlie tries to leave another message
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.AlreadyLeftMessage.selector);
        nft.leaveMessage(0, "Second message");
    }

    function test_MultipleDrifts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // First drift: Bob -> Charlie
        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        vm.prank(charlie);
        nft.leaveMessage(0, "Message from Charlie");

        // Second drift: Charlie -> Alice
        vm.prank(charlie);
        nft.transferFrom(charlie, alice, 0);

        vm.prank(alice);
        nft.leaveMessage(0, "Message from Alice");

        // Third drift: Alice -> Bob
        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);

        // Check drift history
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 3);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, "Message from Charlie");
        assertEq(history[1].from, charlie);
        assertEq(history[1].message, "Message from Alice");
        assertEq(history[2].from, alice);
        assertEq(bytes(history[2].message).length, 0); // Bob hasn't left a message yet

        assertEq(nft.getDriftCount(0), 3);
    }

    // ========== ERC721 Standard Tests ==========

    function test_TransferFrom() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        assertEq(nft.ownerOf(0), charlie);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.balanceOf(charlie), 1);
    }

    function test_Approve() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        vm.prank(bob);
        nft.approve(charlie, 0);

        assertEq(nft.getApproved(0), charlie);

        // Charlie can now transfer
        vm.prank(charlie);
        nft.transferFrom(bob, alice, 0);

        assertEq(nft.ownerOf(0), alice);
    }

    function test_SetApprovalForAll() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token1", "Desc", "image1");
        vm.prank(alice);
        nft.mint(bob, "Token2", "Desc", "image2");

        vm.prank(bob);
        nft.setApprovalForAll(charlie, true);

        assertTrue(nft.isApprovedForAll(bob, charlie));

        // Charlie can transfer any of Bob's tokens
        vm.startPrank(charlie);
        nft.transferFrom(bob, alice, 0);
        nft.transferFrom(bob, alice, 1);
        vm.stopPrank();

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(1), alice);
    }

    function test_TransferFromNotAuthorizedReverts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Charlie tries to transfer without approval
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.NotAuthorized.selector);
        nft.transferFrom(bob, charlie, 0);
    }

    function test_SupportsInterface() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        // ERC721
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(nft.supportsInterface(0x5b5e139f));
        // ERC165
        assertTrue(nft.supportsInterface(0x01ffc9a7));
        // Random interface
        assertFalse(nft.supportsInterface(0x12345678));
    }

    // ========== TokenURI Tests ==========

    function test_TokenURI() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "ipfs://base/");

        SocialNFT nft = SocialNFT(nftAddress);

        // Test with custom image
        vm.prank(alice);
        nft.mint(bob, "Cool NFT", "A very cool NFT", "ipfs://image.png");

        string memory uri = nft.tokenURI(0);
        assertEq(uri, "ipfs://image.png");

        // Test with baseURI fallback
        vm.prank(alice);
        nft.mintWithBaseURI(bob, "NFT #1", "First NFT");

        uri = nft.tokenURI(1);
        assertEq(uri, "ipfs://base/1");
    }

    function test_TokenURINotExistReverts() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.expectRevert(SocialNFT.TokenNotExist.selector);
        nft.tokenURI(999);
    }

    // ========== Factory Tracking Tests ==========

    function test_TrackAllNFTs() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "Desc1", "");

        vm.prank(bob);
        address nft2 = factory.createERC721Free("Collection2", "C2", "Desc2", "");

        assertEq(factory.allNFTsLength(), 2);

        address[] memory allNFTs = factory.getAllNFTs();
        assertEq(allNFTs.length, 2);
        assertEq(allNFTs[0], nft1);
        assertEq(allNFTs[1], nft2);
    }

    function test_TrackUserNFTs() public {
        vm.startPrank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "Desc1", "");
        address nft2 = factory.createERC721Free("Collection2", "C2", "Desc2", "");
        vm.stopPrank();

        vm.prank(bob);
        address nft3 = factory.createERC721Free("Collection3", "C3", "Desc3", "");

        assertEq(factory.userNFTsLength(alice), 2);
        assertEq(factory.userNFTsLength(bob), 1);

        address[] memory aliceNFTs = factory.getUserNFTs(alice);
        assertEq(aliceNFTs.length, 2);
        assertEq(aliceNFTs[0], nft1);
        assertEq(aliceNFTs[1], nft2);

        address[] memory bobNFTs = factory.getUserNFTs(bob);
        assertEq(bobNFTs.length, 1);
        assertEq(bobNFTs[0], nft3);
    }

    // ========== Pagination Tests ==========

    function test_GetUserNFTsPaginated() public {
        vm.startPrank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "D1", "");
        address nft2 = factory.createERC721Free("Collection2", "C2", "D2", "");
        address nft3 = factory.createERC721Free("Collection3", "C3", "D3", "");
        address nft4 = factory.createERC721Free("Collection4", "C4", "D4", "");
        address nft5 = factory.createERC721Free("Collection5", "C5", "D5", "");
        vm.stopPrank();

        // Get first 2 (offset=0, limit=2)
        (address[] memory nfts, uint256 total) = factory.getUserNFTsPaginated(alice, 0, 2);
        assertEq(total, 5);
        assertEq(nfts.length, 2);
        assertEq(nfts[0], nft1);
        assertEq(nfts[1], nft2);

        // Get next 2 (offset=2, limit=2)
        (nfts, total) = factory.getUserNFTsPaginated(alice, 2, 2);
        assertEq(total, 5);
        assertEq(nfts.length, 2);
        assertEq(nfts[0], nft3);
        assertEq(nfts[1], nft4);

        // Get last (offset=4, limit=2)
        (nfts, total) = factory.getUserNFTsPaginated(alice, 4, 2);
        assertEq(total, 5);
        assertEq(nfts.length, 1);
        assertEq(nfts[0], nft5);
    }

    function test_GetUserNFTsPaginatedOffsetTooLarge() public {
        vm.prank(alice);
        factory.createERC721Free("Collection1", "C1", "D1", "");

        (address[] memory nfts, uint256 total) = factory.getUserNFTsPaginated(alice, 10, 5);
        assertEq(total, 1);
        assertEq(nfts.length, 0);
    }

    function test_GetAllNFTsPaginated() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "D1", "");

        vm.prank(bob);
        address nft2 = factory.createERC721Free("Collection2", "C2", "D2", "");

        vm.prank(alice);
        address nft3 = factory.createERC721Free("Collection3", "C3", "D3", "");

        // Get first 2
        (address[] memory nfts, uint256 total) = factory.getAllNFTsPaginated(0, 2);
        assertEq(total, 3);
        assertEq(nfts.length, 2);
        assertEq(nfts[0], nft1);
        assertEq(nfts[1], nft2);

        // Get last
        (nfts, total) = factory.getAllNFTsPaginated(2, 10);
        assertEq(total, 3);
        assertEq(nfts.length, 1);
        assertEq(nfts[0], nft3);
    }

    // ========== Usage Tracking Tests ==========

    function test_FreeUsageTracking() public {
        assertEq(factory.totalFreeUsage(), 0);

        vm.prank(alice);
        factory.createERC721Free("Collection1", "C1", "D1", "");

        assertEq(factory.totalFreeUsage(), 1);

        vm.prank(bob);
        factory.createERC721Free("Collection2", "C2", "D2", "");

        assertEq(factory.totalFreeUsage(), 2);
    }

    // ========== Rarity Constants Tests ==========

    function test_RarityConstants() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.RARITY_COMMON(), 0);
        assertEq(nft.RARITY_UNCOMMON(), 1);
        assertEq(nft.RARITY_RARE(), 2);
        assertEq(nft.RARITY_LEGENDARY(), 3);
        assertEq(nft.RARITY_MYTHIC(), 4);
    }

    // ========== Edge Cases ==========

    function test_TransferClearsApproval() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Bob approves Charlie
        vm.prank(bob);
        nft.approve(charlie, 0);
        assertEq(nft.getApproved(0), charlie);

        // Bob transfers to Alice
        vm.prank(bob);
        nft.transferFrom(bob, alice, 0);

        // Approval should be cleared
        assertEq(nft.getApproved(0), address(0));
    }

    function test_SafeTransferFrom() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Safe transfer (without data)
        vm.prank(bob);
        nft.safeTransferFrom(bob, charlie, 0);

        assertEq(nft.ownerOf(0), charlie);
    }

    function test_SafeTransferFromWithData() public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc", "image");

        // Safe transfer (with data)
        vm.prank(bob);
        nft.safeTransferFrom(bob, charlie, 0, "some data");

        assertEq(nft.ownerOf(0), charlie);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_CreateCollection(string memory _name, string memory _symbol, string memory _description) public {
        vm.assume(bytes(_name).length > 0 && bytes(_name).length < 100);
        vm.assume(bytes(_symbol).length > 0 && bytes(_symbol).length < 20);

        vm.prank(alice);
        address nftAddress = factory.createERC721Free(_name, _symbol, _description, "");

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.name(), _name);
        assertEq(nft.symbol(), _symbol);
        assertEq(nft.collectionDescription(), _description);
        assertEq(nft.owner(), alice);
    }

    function testFuzz_MintAndTransfer(string memory _tokenName, string memory _tokenDesc) public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("Collection", "COL", "Desc", "");

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, _tokenName, _tokenDesc, "image");

        assertEq(nft.ownerOf(tokenId), bob);

        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        assertEq(nft.ownerOf(tokenId), charlie);
        assertEq(nft.getDriftCount(tokenId), 1);
    }
}
