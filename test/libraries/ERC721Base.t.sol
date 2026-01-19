// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC721Base} from "../../src/libraries/ERC721Base.sol";
import {IERC721} from "../../src/interfaces/IERC721.sol";
import {IERC721Receiver} from "../../src/interfaces/IERC721Receiver.sol";

/**
 * @title MockERC721
 * @notice Concrete implementation of ERC721Base for testing
 */
contract MockERC721 is ERC721Base {
    uint256 private _nextTokenId = 1;

    // Track hook calls for testing
    address public lastBeforeFrom;
    address public lastBeforeTo;
    uint256 public lastBeforeTokenId;
    address public lastAfterFrom;
    address public lastAfterTo;
    uint256 public lastAfterTokenId;

    function name() public pure override returns (string memory) {
        return "Mock NFT";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        return string(abi.encodePacked("https://example.com/", _toString(tokenId)));
    }

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    function safeMint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        lastBeforeFrom = from;
        lastBeforeTo = to;
        lastBeforeTokenId = tokenId;
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal override {
        lastAfterFrom = from;
        lastAfterTo = to;
        lastAfterTokenId = tokenId;
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
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

/**
 * @title MockERC721Receiver
 * @notice Valid ERC721 receiver for testing
 */
contract MockERC721Receiver is IERC721Receiver {
    bytes4 public constant MAGIC_VALUE = IERC721Receiver.onERC721Received.selector;

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return MAGIC_VALUE;
    }
}

/**
 * @title RejectingReceiver
 * @notice ERC721 receiver that always rejects
 */
contract RejectingReceiver is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return bytes4(0);
    }
}

/**
 * @title RevertingReceiver
 * @notice ERC721 receiver that reverts
 */
contract RevertingReceiver is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert("Rejected");
    }
}

contract ERC721BaseTest is Test {
    MockERC721 public nft;
    MockERC721Receiver public receiver;
    RejectingReceiver public rejectingReceiver;
    RevertingReceiver public revertingReceiver;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public operator = address(0x3);

    function setUp() public {
        nft = new MockERC721();
        receiver = new MockERC721Receiver();
        rejectingReceiver = new RejectingReceiver();
        revertingReceiver = new RevertingReceiver();

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    // ============ Metadata Tests ============

    function test_name() public view {
        assertEq(nft.name(), "Mock NFT");
    }

    function test_symbol() public view {
        assertEq(nft.symbol(), "MOCK");
    }

    function test_tokenURI() public {
        vm.prank(user1);
        uint256 tokenId = nft.mint(user1);
        assertEq(nft.tokenURI(tokenId), "https://example.com/1");
    }

    function test_tokenURI_nonExistent() public {
        vm.expectRevert(ERC721Base.TokenNotExists.selector);
        nft.tokenURI(999);
    }

    // ============ ERC165 Tests ============

    function test_supportsInterface_ERC721() public view {
        assertTrue(nft.supportsInterface(0x80ac58cd));
    }

    function test_supportsInterface_ERC721Metadata() public view {
        assertTrue(nft.supportsInterface(0x5b5e139f));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(nft.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(nft.supportsInterface(0x12345678));
    }

    // ============ Mint Tests ============

    function test_mint() public {
        uint256 tokenId = nft.mint(user1);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.totalSupply(), 1);
    }

    function test_mint_multiple() public {
        nft.mint(user1);
        nft.mint(user1);
        nft.mint(user2);

        assertEq(nft.balanceOf(user1), 2);
        assertEq(nft.balanceOf(user2), 1);
        assertEq(nft.totalSupply(), 3);
    }

    function test_mint_toZeroAddress_reverts() public {
        vm.expectRevert(ERC721Base.InvalidAddress.selector);
        nft.mint(address(0));
    }

    function test_mint_emitsTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), user1, 1);
        nft.mint(user1);
    }

    // ============ SafeMint Tests ============

    function test_safeMint_toEOA() public {
        uint256 tokenId = nft.safeMint(user1);
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function test_safeMint_toReceiver() public {
        uint256 tokenId = nft.safeMint(address(receiver));
        assertEq(nft.ownerOf(tokenId), address(receiver));
    }

    function test_safeMint_toRejectingReceiver_reverts() public {
        vm.expectRevert(ERC721Base.TransferToNonReceiver.selector);
        nft.safeMint(address(rejectingReceiver));
    }

    function test_safeMint_toRevertingReceiver_reverts() public {
        vm.expectRevert(ERC721Base.TransferToNonReceiver.selector);
        nft.safeMint(address(revertingReceiver));
    }

    // ============ Burn Tests ============

    function test_burn() public {
        uint256 tokenId = nft.mint(user1);
        nft.burn(tokenId);

        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.totalSupply(), 0);

        vm.expectRevert(ERC721Base.TokenNotExists.selector);
        nft.ownerOf(tokenId);
    }

    function test_burn_emitsTransfer() public {
        uint256 tokenId = nft.mint(user1);

        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(0), tokenId);
        nft.burn(tokenId);
    }

    function test_burn_clearsApproval() public {
        uint256 tokenId = nft.mint(user1);
        vm.prank(user1);
        nft.approve(user2, tokenId);

        nft.burn(tokenId);

        // Minting a new token and checking it has no approval
        uint256 newTokenId = nft.mint(user1);
        assertEq(nft.getApproved(newTokenId), address(0));
    }

    // ============ Transfer Tests ============

    function test_transferFrom() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
    }

    function test_transferFrom_byApproved() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.approve(operator, tokenId);

        vm.prank(operator);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_transferFrom_byOperator() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        vm.prank(operator);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_transferFrom_notApproved_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user2);
        vm.expectRevert(ERC721Base.NotApproved.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_transferFrom_wrongFrom_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721Base.NotTokenOwner.selector);
        nft.transferFrom(user2, user1, tokenId);
    }

    function test_transferFrom_toZeroAddress_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721Base.InvalidAddress.selector);
        nft.transferFrom(user1, address(0), tokenId);
    }

    function test_transferFrom_clearsApproval() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.approve(operator, tokenId);
        assertEq(nft.getApproved(tokenId), operator);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.getApproved(tokenId), address(0));
    }

    function test_transferFrom_emitsTransfer() public {
        uint256 tokenId = nft.mint(user1);

        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, tokenId);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
    }

    // ============ SafeTransferFrom Tests ============

    function test_safeTransferFrom_toEOA() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_safeTransferFrom_toReceiver() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, address(receiver), tokenId);

        assertEq(nft.ownerOf(tokenId), address(receiver));
    }

    function test_safeTransferFrom_toRejectingReceiver_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721Base.TransferToNonReceiver.selector);
        nft.safeTransferFrom(user1, address(rejectingReceiver), tokenId);
    }

    function test_safeTransferFrom_withData() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.safeTransferFrom(user1, address(receiver), tokenId, "test data");

        assertEq(nft.ownerOf(tokenId), address(receiver));
    }

    // ============ Approval Tests ============

    function test_approve() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.approve(operator, tokenId);

        assertEq(nft.getApproved(tokenId), operator);
    }

    function test_approve_byOperator() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        vm.prank(operator);
        nft.approve(user2, tokenId);

        assertEq(nft.getApproved(tokenId), user2);
    }

    function test_approve_toOwner_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721Base.InvalidAddress.selector);
        nft.approve(user1, tokenId);
    }

    function test_approve_notOwner_reverts() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user2);
        vm.expectRevert(ERC721Base.NotApproved.selector);
        nft.approve(operator, tokenId);
    }

    function test_approve_nonExistent_reverts() public {
        vm.prank(user1);
        vm.expectRevert(ERC721Base.TokenNotExists.selector);
        nft.approve(operator, 999);
    }

    function test_approve_emitsApproval() public {
        uint256 tokenId = nft.mint(user1);

        vm.expectEmit(true, true, true, true);
        emit IERC721.Approval(user1, operator, tokenId);

        vm.prank(user1);
        nft.approve(operator, tokenId);
    }

    function test_getApproved_nonExistent_reverts() public {
        vm.expectRevert(ERC721Base.TokenNotExists.selector);
        nft.getApproved(999);
    }

    // ============ Operator Approval Tests ============

    function test_setApprovalForAll() public {
        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        assertTrue(nft.isApprovedForAll(user1, operator));
    }

    function test_setApprovalForAll_revoke() public {
        vm.prank(user1);
        nft.setApprovalForAll(operator, true);

        vm.prank(user1);
        nft.setApprovalForAll(operator, false);

        assertFalse(nft.isApprovedForAll(user1, operator));
    }

    function test_setApprovalForAll_toSelf_reverts() public {
        vm.prank(user1);
        vm.expectRevert(ERC721Base.InvalidAddress.selector);
        nft.setApprovalForAll(user1, true);
    }

    function test_setApprovalForAll_emitsApprovalForAll() public {
        vm.expectEmit(true, true, false, true);
        emit IERC721.ApprovalForAll(user1, operator, true);

        vm.prank(user1);
        nft.setApprovalForAll(operator, true);
    }

    // ============ Balance Tests ============

    function test_balanceOf_zeroAddress_reverts() public {
        vm.expectRevert(ERC721Base.InvalidAddress.selector);
        nft.balanceOf(address(0));
    }

    function test_balanceOf_noTokens() public view {
        assertEq(nft.balanceOf(user1), 0);
    }

    // ============ OwnerOf Tests ============

    function test_ownerOf_nonExistent_reverts() public {
        vm.expectRevert(ERC721Base.TokenNotExists.selector);
        nft.ownerOf(999);
    }

    // ============ Hook Tests ============

    function test_beforeTokenTransfer_onMint() public {
        nft.mint(user1);

        assertEq(nft.lastBeforeFrom(), address(0));
        assertEq(nft.lastBeforeTo(), user1);
        assertEq(nft.lastBeforeTokenId(), 1);
    }

    function test_afterTokenTransfer_onMint() public {
        nft.mint(user1);

        assertEq(nft.lastAfterFrom(), address(0));
        assertEq(nft.lastAfterTo(), user1);
        assertEq(nft.lastAfterTokenId(), 1);
    }

    function test_beforeTokenTransfer_onTransfer() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.lastBeforeFrom(), user1);
        assertEq(nft.lastBeforeTo(), user2);
        assertEq(nft.lastBeforeTokenId(), tokenId);
    }

    function test_afterTokenTransfer_onTransfer() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.lastAfterFrom(), user1);
        assertEq(nft.lastAfterTo(), user2);
        assertEq(nft.lastAfterTokenId(), tokenId);
    }

    function test_beforeTokenTransfer_onBurn() public {
        uint256 tokenId = nft.mint(user1);
        nft.burn(tokenId);

        assertEq(nft.lastBeforeFrom(), user1);
        assertEq(nft.lastBeforeTo(), address(0));
        assertEq(nft.lastBeforeTokenId(), tokenId);
    }

    function test_afterTokenTransfer_onBurn() public {
        uint256 tokenId = nft.mint(user1);
        nft.burn(tokenId);

        assertEq(nft.lastAfterFrom(), user1);
        assertEq(nft.lastAfterTo(), address(0));
        assertEq(nft.lastAfterTokenId(), tokenId);
    }

    // ============ Fuzz Tests ============

    function testFuzz_mint(address to) public {
        vm.assume(to != address(0));

        uint256 tokenId = nft.mint(to);

        assertEq(nft.ownerOf(tokenId), to);
        assertEq(nft.balanceOf(to), 1);
    }

    function testFuzz_transferFrom(address from, address to) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);

        uint256 tokenId = nft.mint(from);

        vm.prank(from);
        nft.transferFrom(from, to, tokenId);

        assertEq(nft.ownerOf(tokenId), to);
    }
}
