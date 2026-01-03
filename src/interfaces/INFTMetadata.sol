// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INFTMetadata
 * @notice Interface for NFTMetadata on-chain SVG generation
 * @dev Stable API for SocialNFT and other contracts to interact with NFTMetadata
 */
interface INFTMetadata {
    /**
     * @notice Generate complete metadata JSON with base64 encoded SVG
     * @param cn Collection name
     * @param tn Token name
     * @param desc Token description
     * @param url External URL
     * @param r Rarity (0=Common, 1=Rare, 2=Legendary, 3=Epic)
     * @param bg Background index (0-9)
     * @param p Pattern index (0-9)
     * @param g Glow/Aura level (0-9)
     * @param ln Lucky number (0-9999)
     * @param dc Drift count
     * @return Base64 encoded JSON metadata
     */
    function generateMetadata(
        string memory cn,
        string memory tn,
        string memory desc,
        string memory url,
        uint8 r,
        uint8 bg,
        uint8 p,
        uint8 g,
        uint256 ln,
        uint256 dc
    ) external view returns (string memory);

    /**
     * @notice Generate SVG image only
     * @param cn Collection name
     * @param url External URL
     * @param r Rarity (0=Common, 1=Rare, 2=Legendary, 3=Epic)
     * @param bg Background index (0-9)
     * @param p Pattern index (0-9)
     * @param g Glow/Aura level (0-9)
     * @param ln Lucky number (0-9999)
     * @return SVG string
     */
    function generateSVG(string memory cn, string memory url, uint8 r, uint8 bg, uint8 p, uint8 g, uint256 ln)
        external
        view
        returns (string memory);
}
