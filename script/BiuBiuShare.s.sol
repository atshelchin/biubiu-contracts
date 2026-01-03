// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BiuBiuVault} from "../src/core/BiuBiuVault.sol";
import {BiuBiuShare} from "../src/core/BiuBiuShare.sol";

/// @title BiuBiuShareScript
/// @notice Script to compute BiuBiuShare address (deployed by BiuBiuVault via CREATE)
contract BiuBiuShareScript is Script {
    // CREATE2 Deterministic deployment proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Compute BiuBiuShare address from BiuBiuVault address
    /// @dev BiuBiuShare is deployed by BiuBiuVault constructor via CREATE with nonce=1
    function getShareAddress() public pure returns (address) {
        address vaultAddress = getVaultAddress();
        return computeCreateAddress(vaultAddress, 1);
    }

    /// @notice Get BiuBiuVault deterministic address
    function getVaultAddress() public pure returns (address) {
        bytes memory bytecode = type(BiuBiuVault).creationCode;
        bytes32 salt = bytes32(uint256(0));
        return computeCreate2Address(bytecode, salt);
    }

    /// @notice Compute CREATE address (used by contracts deploying other contracts)
    /// @param deployer The address deploying the contract
    /// @param nonce The nonce of the deployer (1 for first deployment in constructor)
    function computeCreateAddress(address deployer, uint256 nonce) internal pure override returns (address) {
        // For nonce = 1: RLP([deployer, 0x01])
        // RLP encoding: 0xd6 = 0xc0 + 22 (total length), 0x94 = 0x80 + 20 (address length)
        bytes memory data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(uint8(nonce)));
        return address(uint160(uint256(keccak256(data))));
    }

    function computeCreate2Address(bytes memory bytecode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Print the BiuBiuShare address (for CLI use)
    function printAddress() external pure {
        address vaultAddr = getVaultAddress();
        address shareAddr = getShareAddress();

        console.log("=== BiuBiuShare Address ===");
        console.log("BiuBiuVault address:", vaultAddr);
        console.log("BiuBiuShare address:", shareAddr);
        console.log("(Deployed by BiuBiuVault via CREATE with nonce=1)");
        console.log("===========================");
    }

    function run() external pure {
        address vaultAddr = getVaultAddress();
        address shareAddr = getShareAddress();

        console.log("=== BiuBiuShare Address ===");
        console.log("BiuBiuVault address:", vaultAddr);
        console.log("BiuBiuShare address:", shareAddr);
        console.log("===========================");
    }
}
