// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {TokenFactory} from "../src/TokenFactory.sol";
import {NFTFactory} from "../src/NFTFactory.sol";

contract ComputeAddressesScript is Script {
    // CREATE2 Deterministic deployment proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external view {
        // Salt for deterministic address (using 0)
        bytes32 salt = bytes32(uint256(0));

        // Get TokenFactory bytecode
        bytes memory tokenFactoryBytecode = type(TokenFactory).creationCode;
        bytes32 tokenFactoryHash = keccak256(tokenFactoryBytecode);
        address tokenFactoryAddress = computeCreate2Address(tokenFactoryBytecode, salt);

        // Get NFTFactory bytecode
        bytes memory nftFactoryBytecode = type(NFTFactory).creationCode;
        bytes32 nftFactoryHash = keccak256(nftFactoryBytecode);
        address nftFactoryAddress = computeCreate2Address(nftFactoryBytecode, salt);

        console.log("=== CREATE2 Deterministic Addresses ===");
        console.log("");
        console.log("CREATE2 Proxy:", CREATE2_PROXY);
        console.log("Salt:", vm.toString(salt));
        console.log("");
        console.log("--- TokenFactory ---");
        console.log("Bytecode hash:", vm.toString(tokenFactoryHash));
        console.log("Bytecode length:", tokenFactoryBytecode.length);
        console.log("Predicted address:", tokenFactoryAddress);
        console.log("");
        console.log("--- NFTFactory ---");
        console.log("Bytecode hash:", vm.toString(nftFactoryHash));
        console.log("Bytecode length:", nftFactoryBytecode.length);
        console.log("Predicted address:", nftFactoryAddress);
        console.log("");
        console.log("========================================");
    }

    function computeCreate2Address(bytes memory bytecode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
