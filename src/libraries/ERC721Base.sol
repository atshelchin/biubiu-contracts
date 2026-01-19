// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "../interfaces/IERC721.sol";
import {IERC721Receiver} from "../interfaces/IERC721Receiver.sol";

/**
 * @title ERC721Base
 * @notice Abstract ERC721 implementation with customizable hooks
 * @dev Provides standard ERC721 functionality with virtual functions for customization
 */
abstract contract ERC721Base is IERC721 {
    // ============ Custom Errors ============

    error InvalidAddress();
    error TokenNotExists();
    error NotApproved();
    error NotTokenOwner();
    error TransferToNonReceiver();

    // ============ State Variables ============

    uint256 internal _totalSupply;
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    // ============ Abstract Functions ============

    function name() public view virtual returns (string memory);
    function symbol() public view virtual returns (string memory);
    function tokenURI(uint256 tokenId) public view virtual returns (string memory);

    // ============ ERC721 Standard ============

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == 0x80ac58cd // ERC721
                || interfaceId == 0x5b5e139f // ERC721Metadata
                || interfaceId == 0x01ffc9a7; // ERC165
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) revert InvalidAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenNotExists();
        return owner;
    }

    function getApproved(uint256 tokenId) public view virtual returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenNotExists();
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function approve(address to, uint256 tokenId) public virtual {
        address owner = ownerOf(tokenId);
        if (to == owner) revert InvalidAddress();
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) {
            revert NotApproved();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        if (operator == msg.sender) revert InvalidAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApproved();
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert TransferToNonReceiver();
        }
    }

    // ============ Internal Functions ============

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        if (ownerOf(tokenId) != from) revert NotTokenOwner();
        if (to == address(0)) revert InvalidAddress();

        _beforeTokenTransfer(from, to, tokenId);

        delete _tokenApprovals[tokenId];

        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal virtual {
        if (to == address(0)) revert InvalidAddress();

        _beforeTokenTransfer(address(0), to, tokenId);

        unchecked {
            _balances[to] += 1;
            _totalSupply += 1;
        }
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    function _safeMint(address to, uint256 tokenId) internal virtual {
        _mint(to, tokenId);
        if (!_checkOnERC721Received(address(0), to, tokenId, "")) {
            revert TransferToNonReceiver();
        }
    }

    function _burn(uint256 tokenId) internal virtual {
        address owner = ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        delete _tokenApprovals[tokenId];

        unchecked {
            _balances[owner] -= 1;
            _totalSupply -= 1;
        }
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        internal
        virtual
        returns (bool)
    {
        if (to.code.length == 0) return true;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    // ============ Hooks ============

    /**
     * @dev Hook called before any token transfer (including minting and burning)
     * @param from Address tokens are transferred from (address(0) for minting)
     * @param to Address tokens are transferred to (address(0) for burning)
     * @param tokenId Token ID being transferred
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    /**
     * @dev Hook called after any token transfer (including minting and burning)
     * @param from Address tokens were transferred from (address(0) for minting)
     * @param to Address tokens were transferred to (address(0) for burning)
     * @param tokenId Token ID that was transferred
     */
    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}
}
