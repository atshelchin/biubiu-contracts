// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTFactory, SocialNFT} from "../src/tools/NFTFactory.sol";
import {NFTMetadata} from "../src/tools/NFTMetadata.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";

contract NFTFactoryTest is Test {
    NFTFactory public factory;
    NFTMetadata public metadata;
    BiuBiuPremium public premium;

    // NFTMetadata contract address
    address public metadataAddr;

    address public vault = 0x46AFD0cA864D4E5235DA38a71687163Dc83828cE;
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
        premium = new BiuBiuPremium();
        metadata = new NFTMetadata();
        metadataAddr = address(metadata);
        factory = new NFTFactory(metadataAddr);
    }

    // ========== Collection Creation Tests ==========

    function test_CreateCollectionBasic() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "A cool collection", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.name(), "My Collection");
        assertEq(nft.symbol(), "MC");
        assertEq(nft.collectionDescription(), "A cool collection");
        assertEq(nft.externalURL(), "https://example.com");
        assertEq(nft.owner(), alice);
        assertEq(nft.totalSupply(), 0);
    }

    function test_CreateCollectionEmitsEvent() public {
        vm.startPrank(alice);

        vm.expectEmit(false, true, false, false);
        emit NFTCreated(address(0), alice, "Test", "TST", "Test desc", 0);

        factory.createERC721Free("Test", "TST", "Test desc", "https://example.com", false);

        vm.stopPrank();
    }

    function test_CreateCollectionEmptyNameReverts() public {
        vm.prank(alice);
        vm.expectRevert(NFTFactory.NameEmpty.selector);
        factory.createERC721Free("", "MC", "Description", "https://example.com", false);
    }

    function test_CreateCollectionEmptySymbolReverts() public {
        vm.prank(alice);
        vm.expectRevert(NFTFactory.SymbolEmpty.selector);
        factory.createERC721Free("My Collection", "", "Description", "https://example.com", false);
    }

    function test_CREATE2SameParamsDifferentCreators() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        vm.prank(bob);
        address nft2 = factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        // Different creators = different addresses
        assertFalse(nft1 == nft2);
    }

    function test_SameCreatorSameParamsReverts() public {
        vm.startPrank(alice);
        factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        vm.expectRevert();
        factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);
        vm.stopPrank();
    }

    // ========== Minting Tests ==========

    function test_MintBasic() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token #1", "First token");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.totalSupply(), 1);
    }

    function test_MintWithBaseURI() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token #1", "First token");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
    }

    function test_MintByNonOwnerWithPayment() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        // Bob mints with payment (default: open mint mode)
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        uint256 tokenId = nft.mint{value: 0.01 ether}(bob, "Token", "Desc");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.balanceOf(bob), 1);
    }

    function test_MintByNonOwnerInsufficientPaymentReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        // Bob tries to mint without enough payment
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(SocialNFT.InsufficientPayment.selector);
        nft.mint{value: 0.005 ether}(bob, "Token", "Desc");
    }

    function test_MintOnlyOwnerModeEnabled() public {
        // Create collection with onlyOwnerCanMint = true
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", true);

        SocialNFT nft = SocialNFT(nftAddress);

        // Verify onlyOwnerCanMint is set at creation
        assertTrue(nft.onlyOwnerCanMint());

        // Bob tries to mint - should fail even with payment
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(SocialNFT.OnlyOwnerCanMintEnabled.selector);
        nft.mint{value: 0.01 ether}(bob, "Token", "Desc");

        // Alice (owner) can still mint for free
        vm.prank(alice);
        uint256 tokenId = nft.mint(alice, "Token", "Desc");
        assertEq(tokenId, 0);
    }

    function test_MintFeeDistribution() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);
        address vault = nft.VAULT();

        // Record initial balances
        uint256 aliceBalanceBefore = alice.balance;
        uint256 vaultBalanceBefore = vault.balance;

        // Bob mints with payment
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        nft.mint{value: 0.01 ether}(bob, "Token", "Desc");

        // Check fee distribution: 80% to owner (alice), 20% to VAULT
        assertEq(alice.balance - aliceBalanceBefore, 0.008 ether); // 80%
        assertEq(vault.balance - vaultBalanceBefore, 0.002 ether); // 20%
    }

    function test_OwnerMintsFree() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        // Owner mints without payment
        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token", "Desc");

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), bob);
    }

    function test_OnlyOwnerCanMintImmutable() public {
        // Create collection with onlyOwnerCanMint = false (open mode)
        vm.prank(alice);
        address nftAddress1 =
            factory.createERC721Free("Open Collection", "OC", "Open mint", "https://example.com", false);
        SocialNFT nft1 = SocialNFT(nftAddress1);
        assertFalse(nft1.onlyOwnerCanMint());

        // Create collection with onlyOwnerCanMint = true (restricted mode)
        vm.prank(alice);
        address nftAddress2 =
            factory.createERC721Free("Restricted Collection", "RC", "Owner only", "https://example.com", true);
        SocialNFT nft2 = SocialNFT(nftAddress2);
        assertTrue(nft2.onlyOwnerCanMint());

        // Mode is immutable - set at creation time
    }

    function test_MintToZeroAddressReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        vm.expectRevert(SocialNFT.InvalidRecipient.selector);
        nft.mint(address(0), "Token", "Desc");
    }

    function test_MintGeneratesTraits() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token", "Desc");

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
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.startPrank(alice);
        nft.mint(bob, "Token 1", "First");
        nft.mint(charlie, "Token 2", "Second");
        nft.mint(bob, "Token 3", "Third");
        vm.stopPrank();

        assertEq(nft.totalSupply(), 3);
        assertEq(nft.balanceOf(bob), 2);
        assertEq(nft.balanceOf(charlie), 1);
        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.ownerOf(1), charlie);
        assertEq(nft.ownerOf(2), bob);
    }

    // ========== Drift (Transfer Message) System Tests ==========

    function test_TransferDoesNotCreateDrift() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        // Alice mints to Bob
        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob transfers to Charlie (standard transfer, no drift record)
        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        // Check drift history - should be empty since transferFrom no longer creates drift
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 0);
    }

    function test_LeaveMessage() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob (current owner) leaves a message
        vm.prank(bob);
        nft.leaveMessage(0, "Hello from Bob!");

        // Check message was recorded
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 1);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, "Hello from Bob!");
    }

    function test_LeaveMessageOnlyTokenOwner() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Charlie (not the current owner) tries to leave message
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.NotTokenOwner.selector);
        nft.leaveMessage(0, "Can I leave a message?");
    }

    function test_LeaveMessageAlreadyLeftReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob leaves first message
        vm.prank(bob);
        nft.leaveMessage(0, "First message");

        // Bob tries to leave another message
        vm.prank(bob);
        vm.expectRevert(SocialNFT.AlreadyLeftMessage.selector);
        nft.leaveMessage(0, "Second message");
    }

    function test_MultipleDriftsWithMessages() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob leaves message and transfers to Charlie using driftWithMessage
        vm.prank(bob);
        nft.driftWithMessage(charlie, 0, "Message from Bob");

        // Charlie leaves message and transfers to Alice
        vm.prank(charlie);
        nft.driftWithMessage(alice, 0, "Message from Charlie");

        // Alice leaves message and transfers to Bob
        vm.prank(alice);
        nft.driftWithMessage(bob, 0, "Message from Alice");

        // Check drift history
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 3);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, "Message from Bob");
        assertEq(history[1].from, charlie);
        assertEq(history[1].message, "Message from Charlie");
        assertEq(history[2].from, alice);
        assertEq(history[2].message, "Message from Alice");

        assertEq(nft.getDriftCount(0), 3);
    }

    // ========== driftWithMessage Tests ==========

    function test_DriftWithMessage() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob drifts to Charlie with message (atomic operation)
        vm.prank(bob);
        nft.driftWithMessage(charlie, 0, "Hello Charlie!");

        // Check ownership transferred
        assertEq(nft.ownerOf(0), charlie);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.balanceOf(charlie), 1);

        // Check drift history recorded
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 1);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, "Hello Charlie!");
    }

    function test_DriftWithMessageEmitsEvents() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        vm.expectEmit(true, true, false, true);
        emit MessageLeft(0, bob, "Hello!");

        vm.expectEmit(true, true, true, false);
        emit Drifted(0, bob, charlie);

        vm.prank(bob);
        nft.driftWithMessage(charlie, 0, "Hello!");
    }

    function test_DriftWithMessageNotOwnerReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Charlie (not owner) tries to drift
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.NotTokenOwner.selector);
        nft.driftWithMessage(alice, 0, "Trying to steal!");
    }

    function test_DriftWithMessageToZeroAddressReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        vm.prank(bob);
        vm.expectRevert(SocialNFT.InvalidRecipient.selector);
        nft.driftWithMessage(address(0), 0, "To nobody");
    }

    function test_DriftWithMessageAlreadyLeftReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob leaves message first
        vm.prank(bob);
        nft.leaveMessage(0, "My message");

        // Bob tries to drift with message again
        vm.prank(bob);
        vm.expectRevert(SocialNFT.AlreadyLeftMessage.selector);
        nft.driftWithMessage(charlie, 0, "Another message");
    }

    function test_DriftWithMessageThenLeaveMessageReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob drifts with message to Charlie
        vm.prank(bob);
        nft.driftWithMessage(charlie, 0, "From Bob");

        // Charlie tries to leave another message (should work - different user)
        vm.prank(charlie);
        nft.leaveMessage(0, "From Charlie");

        // Charlie tries to leave yet another message (should fail)
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.AlreadyLeftMessage.selector);
        nft.leaveMessage(0, "Another from Charlie");
    }

    function test_LeaveMessageThenDriftWithMessageReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob leaves message first
        vm.prank(bob);
        nft.leaveMessage(0, "My message");

        // Bob tries to driftWithMessage (should fail - already left message)
        vm.prank(bob);
        vm.expectRevert(SocialNFT.AlreadyLeftMessage.selector);
        nft.driftWithMessage(charlie, 0, "Trying again");
    }

    function test_DriftWithMessageThenTransferThenDriftAgain() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Bob drifts to Charlie with message
        vm.prank(bob);
        nft.driftWithMessage(charlie, 0, "From Bob");

        // Charlie transfers to Alice (standard transfer, no message)
        vm.prank(charlie);
        nft.transferFrom(charlie, alice, 0);

        // Alice can still drift with message
        vm.prank(alice);
        nft.driftWithMessage(bob, 0, "From Alice");

        // Check history
        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(0);
        assertEq(history.length, 2);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, "From Bob");
        assertEq(history[1].from, alice);
        assertEq(history[1].message, "From Alice");
    }

    // ========== ERC721 Standard Tests ==========

    function test_TransferFrom() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        vm.prank(bob);
        nft.transferFrom(bob, charlie, 0);

        assertEq(nft.ownerOf(0), charlie);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.balanceOf(charlie), 1);
    }

    function test_Approve() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

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
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token1", "Desc");
        vm.prank(alice);
        nft.mint(bob, "Token2", "Desc");

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
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Charlie tries to transfer without approval
        vm.prank(charlie);
        vm.expectRevert(SocialNFT.NotAuthorized.selector);
        nft.transferFrom(bob, charlie, 0);
    }

    function test_SupportsInterface() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

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
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        // Mint an NFT
        vm.prank(alice);
        nft.mint(bob, "Cool NFT", "A very cool NFT");

        // TokenURI now returns on-chain generated metadata (base64 JSON)
        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));

        // Mint another NFT and verify it also returns on-chain metadata
        vm.prank(alice);
        nft.mint(bob, "NFT #1", "First NFT");

        uri = nft.tokenURI(1);
        assertTrue(bytes(uri).length > 0);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (strBytes.length < prefixBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    function test_TokenURINotExistReverts() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.expectRevert(SocialNFT.TokenNotExist.selector);
        nft.tokenURI(999);
    }

    // ========== Factory Tracking Tests ==========

    function test_TrackAllNFTs() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "Desc1", "https://example.com", false);

        vm.prank(bob);
        address nft2 = factory.createERC721Free("Collection2", "C2", "Desc2", "https://example.com", false);

        assertEq(factory.allNFTsLength(), 2);

        address[] memory allNFTs = factory.getAllNFTs();
        assertEq(allNFTs.length, 2);
        assertEq(allNFTs[0], nft1);
        assertEq(allNFTs[1], nft2);
    }

    function test_TrackUserNFTs() public {
        vm.startPrank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "Desc1", "https://example.com", false);
        address nft2 = factory.createERC721Free("Collection2", "C2", "Desc2", "https://example.com", false);
        vm.stopPrank();

        vm.prank(bob);
        address nft3 = factory.createERC721Free("Collection3", "C3", "Desc3", "https://example.com", false);

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
        address nft1 = factory.createERC721Free("Collection1", "C1", "D1", "https://example.com", false);
        address nft2 = factory.createERC721Free("Collection2", "C2", "D2", "https://example.com", false);
        address nft3 = factory.createERC721Free("Collection3", "C3", "D3", "https://example.com", false);
        address nft4 = factory.createERC721Free("Collection4", "C4", "D4", "https://example.com", false);
        address nft5 = factory.createERC721Free("Collection5", "C5", "D5", "https://example.com", false);
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
        factory.createERC721Free("Collection1", "C1", "D1", "https://example.com", false);

        (address[] memory nfts, uint256 total) = factory.getUserNFTsPaginated(alice, 10, 5);
        assertEq(total, 1);
        assertEq(nfts.length, 0);
    }

    function test_GetAllNFTsPaginated() public {
        vm.prank(alice);
        address nft1 = factory.createERC721Free("Collection1", "C1", "D1", "https://example.com", false);

        vm.prank(bob);
        address nft2 = factory.createERC721Free("Collection2", "C2", "D2", "https://example.com", false);

        vm.prank(alice);
        address nft3 = factory.createERC721Free("Collection3", "C3", "D3", "https://example.com", false);

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
        factory.createERC721Free("Collection1", "C1", "D1", "https://example.com", false);

        assertEq(factory.totalFreeUsage(), 1);

        vm.prank(bob);
        factory.createERC721Free("Collection2", "C2", "D2", "https://example.com", false);

        assertEq(factory.totalFreeUsage(), 2);
    }

    // ========== Rarity Constants Tests ==========

    function test_RarityConstants() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.RARITY_COMMON(), 0);
        assertEq(nft.RARITY_RARE(), 1);
        assertEq(nft.RARITY_LEGENDARY(), 2);
        assertEq(nft.RARITY_EPIC(), 3);
    }

    // ========== Edge Cases ==========

    function test_TransferClearsApproval() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

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
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

        // Safe transfer (without data)
        vm.prank(bob);
        nft.safeTransferFrom(bob, charlie, 0);

        assertEq(nft.ownerOf(0), charlie);
    }

    function test_SafeTransferFromWithData() public {
        vm.prank(alice);
        address nftAddress =
            factory.createERC721Free("My Collection", "MC", "Description", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        nft.mint(bob, "Token", "Desc");

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
        address nftAddress = factory.createERC721Free(_name, _symbol, _description, "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        assertEq(nft.name(), _name);
        assertEq(nft.symbol(), _symbol);
        assertEq(nft.collectionDescription(), _description);
        assertEq(nft.owner(), alice);
    }

    function testFuzz_MintAndTransfer(string memory _tokenName, string memory _tokenDesc) public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("Collection", "COL", "Desc", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, _tokenName, _tokenDesc);

        assertEq(nft.ownerOf(tokenId), bob);

        vm.prank(bob);
        nft.transferFrom(bob, charlie, tokenId);

        assertEq(nft.ownerOf(tokenId), charlie);
        // Standard transfer no longer creates drift record
        assertEq(nft.getDriftCount(tokenId), 0);
    }

    function testFuzz_DriftWithMessage(string memory _message) public {
        vm.prank(alice);
        address nftAddress = factory.createERC721Free("Collection", "COL", "Desc", "https://example.com", false);

        SocialNFT nft = SocialNFT(nftAddress);

        vm.prank(alice);
        uint256 tokenId = nft.mint(bob, "Token", "Desc");

        vm.prank(bob);
        nft.driftWithMessage(charlie, tokenId, _message);

        assertEq(nft.ownerOf(tokenId), charlie);
        assertEq(nft.getDriftCount(tokenId), 1);

        SocialNFT.DriftMessage[] memory history = nft.getDriftHistory(tokenId);
        assertEq(history[0].from, bob);
        assertEq(history[0].message, _message);
    }
}
