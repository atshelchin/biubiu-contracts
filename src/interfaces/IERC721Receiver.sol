// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC721Receiver
 * @notice Interface for contracts that want to support safeTransfers from ERC721 tokens
 * @dev Implementing contracts must return the function selector to confirm the token transfer
 */
interface IERC721Receiver {
    /**
     * @notice Handle the receipt of an NFT
     * @param operator The address which called safeTransferFrom
     * @param from The address which previously owned the token
     * @param tokenId The NFT identifier which is being transferred
     * @param data Additional data with no specified format
     * @return bytes4 `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
