// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {NFTFactory} from "../src/NFTFactory.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract VerifyDeploymentScript is Script {
    // CREATE2 Deterministic deployment proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external view {
        // Your deployed address
        address deployedNFTFactory = 0x74d4074303778793d8aaa384A0382242486f781B;

        console.log("=== Deployment Verification ===");
        console.log("");
        console.log("Your deployed NFTFactory:", deployedNFTFactory);
        console.log("");

        // Try different salts to find a match
        bytes memory nftFactoryBytecode = type(NFTFactory).creationCode;

        console.log("Testing different scenarios:");
        console.log("");

        // Scenario 1: CREATE2 proxy with salt 0
        bytes32 salt0 = bytes32(uint256(0));
        address predicted0 = computeCreate2Address(nftFactoryBytecode, salt0);
        console.log("1. CREATE2 Proxy + salt(0):");
        console.log("   Predicted:", predicted0);
        console.log("   Match:", predicted0 == deployedNFTFactory ? "YES" : "NO");
        console.log("");

        // Scenario 2: Try to reverse engineer the salt
        console.log("2. Checking if deployed via CREATE2 proxy:");
        bool foundMatch = false;
        for (uint256 i = 0; i < 100; i++) {
            bytes32 testSalt = bytes32(i);
            address testAddr = computeCreate2Address(nftFactoryBytecode, testSalt);
            if (testAddr == deployedNFTFactory) {
                console.log("   FOUND! Salt:", vm.toString(testSalt));
                console.log("   Salt (uint):", i);
                foundMatch = true;
                break;
            }
        }
        if (!foundMatch) {
            console.log("   Not found in salt range 0-99");
            console.log("   Likely deployed via regular CREATE (not CREATE2)");
        }
        console.log("");

        console.log("3. If deployed via regular CREATE:");
        console.log("   Address depends on: keccak256(RLP(deployer, nonce))");
        console.log("   This means different address on each chain");
        console.log("   To get deterministic address, must use CREATE2");
        console.log("");

        console.log("================================");
    }

    function computeCreate2Address(bytes memory bytecode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
