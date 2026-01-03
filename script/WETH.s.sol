// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {WETH} from "../src/core/WETH.sol";

contract WETHScript is Script {
    // CREATE2 Deterministic deployment proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Get contract bytecode
        bytes memory bytecode = type(WETH).creationCode;

        // Salt for deterministic address (can be changed)
        bytes32 salt = bytes32(uint256(0));

        // Deploy via CREATE2 proxy
        WETH weth = WETH(payable(deployViaCreate2Proxy(bytecode, salt)));

        console.log("=== WETH Deployment ===");
        console.log("WETH deployed at:", address(weth));
        console.log("Name:", weth.name());
        console.log("Symbol:", weth.symbol());
        console.log("=======================");

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

    /// @notice Get the deterministic deployment address without deploying
    function getDeploymentAddress() external pure returns (address) {
        bytes memory bytecode = type(WETH).creationCode;
        bytes32 salt = bytes32(uint256(0));
        return computeCreate2Address(bytecode, salt);
    }

    /// @notice Get the deterministic deployment address with custom salt
    function getDeploymentAddress(bytes32 salt) external pure returns (address) {
        bytes memory bytecode = type(WETH).creationCode;
        return computeCreate2Address(bytecode, salt);
    }

    /// @notice Print the deterministic deployment address (for CLI use)
    function printAddress() external pure {
        bytes memory bytecode = type(WETH).creationCode;
        bytes32 salt = bytes32(uint256(0));
        address predicted = computeCreate2Address(bytecode, salt);
        console.log("WETH deterministic address:", predicted);
        console.log("Salt:", uint256(salt));
        console.log("Bytecode hash:", uint256(keccak256(bytecode)));
    }
}
