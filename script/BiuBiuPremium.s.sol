// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BiuBiuPremium} from "../src/BiuBiuPremium.sol";

contract BiuBiuPremiumScript is Script {
    // CREATE2 Deterministic deployment proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Get contract bytecode
        bytes memory bytecode = type(BiuBiuPremium).creationCode;

        // Salt for deterministic address (can be changed)
        bytes32 salt = bytes32(uint256(0));

        // Deploy via CREATE2 proxy
        BiuBiuPremium premium = BiuBiuPremium(payable(deployViaCreate2Proxy(bytecode, salt)));

        console.log("BiuBiuPremium deployed at:", address(premium));
        console.log("Owner address:", premium.OWNER());
        console.log("Daily price:", premium.DAILY_PRICE());
        console.log("Monthly price:", premium.MONTHLY_PRICE());
        console.log("Yearly price:", premium.YEARLY_PRICE());

        vm.stopBroadcast();
    }

    function deployViaCreate2Proxy(bytes memory bytecode, bytes32 salt) internal returns (address) {
        // Compute deterministic address
        address predictedAddress = computeCreate2Address(bytecode, salt);

        // Check if already deployed
        if (predictedAddress.code.length > 0) {
            console.log("Contract already deployed at:", predictedAddress);
            return predictedAddress;
        }

        // Deploy via CREATE2 proxy
        // The proxy expects: salt (32 bytes) + bytecode
        bytes memory payload = abi.encodePacked(salt, bytecode);

        (bool success, bytes memory returnData) = CREATE2_PROXY.call(payload);
        require(success, "CREATE2 deployment failed");

        // CREATE2 proxy returns the deployed address as bytes20
        // forge-lint: disable-next-line(unsafe-typecast)
        address deployedAddress = address(uint160(bytes20(returnData)));
        require(deployedAddress == predictedAddress, "Deployed address mismatch");

        return deployedAddress;
    }

    function computeCreate2Address(bytes memory bytecode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
