// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {TokenFactory} from "../src/TokenFactory.sol";
import {NFTFactory} from "../src/NFTFactory.sol";
import {NFTMetadata} from "../src/NFTMetadata.sol";
import {WETH} from "../src/WETH.sol";
import {TokenDistribution} from "../src/TokenDistribution.sol";
import {TokenSweep} from "../src/TokenSweep.sol";
import {BiuBiuPremium} from "../src/BiuBiuPremium.sol";

/// @title ComputeAllAddresses
/// @notice Computes deterministic CREATE2 addresses for all contracts in src/
/// @dev Uses the standard CREATE2 deterministic deployment proxy
contract ComputeAllAddressesScript is Script {
    // CREATE2 Deterministic deployment proxy (available on most chains)
    // https://github.com/Arachnid/deterministic-deployment-proxy
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    struct ContractInfo {
        string name;
        address predictedAddress;
        bytes32 bytecodeHash;
        uint256 bytecodeLength;
    }

    function run() external view {
        bytes32 salt = bytes32(uint256(0));

        console.log("=====================================");
        console.log("CREATE2 Deterministic Address Calculator");
        console.log("=====================================");
        console.log("");
        console.log("CREATE2 Proxy:", CREATE2_PROXY);
        console.log("Salt:", vm.toString(salt));
        console.log("");
        console.log("-------------------------------------");

        // WETH
        _printContractInfo("WETH", type(WETH).creationCode, salt);

        // TokenDistribution
        _printContractInfo("TokenDistribution", type(TokenDistribution).creationCode, salt);

        // TokenFactory
        _printContractInfo("TokenFactory", type(TokenFactory).creationCode, salt);

        // NFTFactory
        _printContractInfo("NFTFactory", type(NFTFactory).creationCode, salt);

        // NFTMetadata
        _printContractInfo("NFTMetadata", type(NFTMetadata).creationCode, salt);

        // TokenSweep
        _printContractInfo("TokenSweep", type(TokenSweep).creationCode, salt);

        // BiuBiuPremium
        _printContractInfo("BiuBiuPremium", type(BiuBiuPremium).creationCode, salt);

        console.log("-------------------------------------");
        console.log("");
        console.log("Usage: Update hardcoded addresses in contracts");
        console.log("  - TokenDistribution.sol: WETH address");
        console.log("  - TokenSweep.sol: PREMIUM_CONTRACT address");
        console.log("");
        console.log("=====================================");
    }

    function _printContractInfo(string memory name, bytes memory bytecode, bytes32 salt) internal pure {
        bytes32 bytecodeHash = keccak256(bytecode);
        address predicted = _computeCreate2Address(bytecode, salt);

        console.log("");
        console.log(name);
        console.log("  Address:", predicted);
        console.log("  Bytecode Hash:", vm.toString(bytecodeHash));
        console.log("  Bytecode Size:", bytecode.length, "bytes");
    }

    function _computeCreate2Address(bytes memory bytecode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Get the predicted address for a specific contract
    /// @param contractName The name of the contract
    /// @return The predicted CREATE2 address
    function getAddress(string memory contractName) external pure returns (address) {
        bytes32 salt = bytes32(uint256(0));

        if (keccak256(bytes(contractName)) == keccak256(bytes("WETH"))) {
            return _computeCreate2Address(type(WETH).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("TokenDistribution"))) {
            return _computeCreate2Address(type(TokenDistribution).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("TokenFactory"))) {
            return _computeCreate2Address(type(TokenFactory).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("NFTFactory"))) {
            return _computeCreate2Address(type(NFTFactory).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("NFTMetadata"))) {
            return _computeCreate2Address(type(NFTMetadata).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("TokenSweep"))) {
            return _computeCreate2Address(type(TokenSweep).creationCode, salt);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("BiuBiuPremium"))) {
            return _computeCreate2Address(type(BiuBiuPremium).creationCode, salt);
        }
        revert("Unknown contract name");
    }

    /// @notice Get all contract addresses as a struct array
    function getAllAddresses() external pure returns (ContractInfo[] memory) {
        bytes32 salt = bytes32(uint256(0));
        ContractInfo[] memory contracts = new ContractInfo[](7);

        bytes memory wethBytecode = type(WETH).creationCode;
        contracts[0] = ContractInfo({
            name: "WETH",
            predictedAddress: _computeCreate2Address(wethBytecode, salt),
            bytecodeHash: keccak256(wethBytecode),
            bytecodeLength: wethBytecode.length
        });

        bytes memory tdBytecode = type(TokenDistribution).creationCode;
        contracts[1] = ContractInfo({
            name: "TokenDistribution",
            predictedAddress: _computeCreate2Address(tdBytecode, salt),
            bytecodeHash: keccak256(tdBytecode),
            bytecodeLength: tdBytecode.length
        });

        bytes memory tfBytecode = type(TokenFactory).creationCode;
        contracts[2] = ContractInfo({
            name: "TokenFactory",
            predictedAddress: _computeCreate2Address(tfBytecode, salt),
            bytecodeHash: keccak256(tfBytecode),
            bytecodeLength: tfBytecode.length
        });

        bytes memory nfBytecode = type(NFTFactory).creationCode;
        contracts[3] = ContractInfo({
            name: "NFTFactory",
            predictedAddress: _computeCreate2Address(nfBytecode, salt),
            bytecodeHash: keccak256(nfBytecode),
            bytecodeLength: nfBytecode.length
        });

        bytes memory nmBytecode = type(NFTMetadata).creationCode;
        contracts[4] = ContractInfo({
            name: "NFTMetadata",
            predictedAddress: _computeCreate2Address(nmBytecode, salt),
            bytecodeHash: keccak256(nmBytecode),
            bytecodeLength: nmBytecode.length
        });

        bytes memory tsBytecode = type(TokenSweep).creationCode;
        contracts[5] = ContractInfo({
            name: "TokenSweep",
            predictedAddress: _computeCreate2Address(tsBytecode, salt),
            bytecodeHash: keccak256(tsBytecode),
            bytecodeLength: tsBytecode.length
        });

        bytes memory bbpBytecode = type(BiuBiuPremium).creationCode;
        contracts[6] = ContractInfo({
            name: "BiuBiuPremium",
            predictedAddress: _computeCreate2Address(bbpBytecode, salt),
            bytecodeHash: keccak256(bbpBytecode),
            bytecodeLength: bbpBytecode.length
        });

        return contracts;
    }
}
