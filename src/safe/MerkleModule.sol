// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMerkleModule} from "./IMerkleModule.sol";

/// @title MerkleModule
/// @notice Safe Module: Merkle-based pre-authorization, each leaf can only be executed once
/// @dev Supports both direct calls and ERC-4337 mode
/// @author BiuBiu
contract MerkleModule is IMerkleModule {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Used leaf nodes
    /// @dev key = keccak256(safe, chainId, merkleRoot, leaf)
    mapping(bytes32 => bool) public usedLeaves;

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Direct call mode - anyone can call, requires owner signature
    function execute(
        address safe,
        bytes32 merkleRoot,
        uint64 deadline,
        bytes32[] calldata proof,
        Call calldata call,
        bytes calldata signature
    ) external {
        _execute(safe, merkleRoot, deadline, proof, call, signature);
    }

    /// @notice ERC-4337 mode - msg.sender is Safe
    /// @dev UserOp.callData = abi.encodeCall(this.executeFromSafe, (...))
    function executeFromSafe(
        bytes32 merkleRoot,
        uint64 deadline,
        bytes32[] calldata proof,
        Call calldata call,
        bytes calldata signature
    ) external {
        _execute(msg.sender, merkleRoot, deadline, proof, call, signature);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute the leaf key
    function getLeafKey(address safe, bytes32 merkleRoot, bytes32 leaf) external view returns (bytes32) {
        return keccak256(abi.encode(safe, block.chainid, merkleRoot, leaf));
    }

    /// @notice Compute the leaf node
    function getLeaf(Call calldata call) external pure returns (bytes32) {
        return keccak256(abi.encode(call.target, call.value, call.data));
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _execute(
        address safe,
        bytes32 merkleRoot,
        uint64 deadline,
        bytes32[] calldata proof,
        Call calldata call,
        bytes calldata signature
    ) internal {
        // 1. Check expiration
        if (deadline != 0 && block.timestamp > deadline) {
            revert Expired();
        }

        // 2. Verify owner signature (message: safe, chainId, merkleRoot, deadline)
        bytes32 authHash = keccak256(abi.encode(safe, block.chainid, merkleRoot, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", authHash));
        if (!_isValidSignature(safe, ethSignedHash, signature)) {
            revert InvalidSignature();
        }

        // 3. Compute leaf and verify Merkle proof
        bytes32 leaf = keccak256(abi.encode(call.target, call.value, call.data));
        if (!_verifyProof(proof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // 4. Check leaf not already used
        bytes32 leafKey = keccak256(abi.encode(safe, block.chainid, merkleRoot, leaf));
        if (usedLeaves[leafKey]) {
            revert LeafAlreadyUsed();
        }
        usedLeaves[leafKey] = true;

        // 5. Execute transaction via Safe
        bool success = ISafe(safe).execTransactionFromModule(call.target, call.value, call.data, Operation.Call);
        if (!success) {
            revert ExecutionFailed();
        }

        emit Executed(safe, merkleRoot, leaf, call.target, call.value);
    }

    /// @notice Verify signature via Safe's ERC-1271
    function _isValidSignature(address safe, bytes32 hash, bytes calldata signature) internal view returns (bool) {
        // Safe implements ERC-1271, call isValidSignature
        (bool success, bytes memory result) = safe.staticcall(abi.encodeWithSelector(0x1626ba7e, hash, signature)); // isValidSignature(bytes32,bytes)

        if (success && result.length >= 32) {
            return abi.decode(result, (bytes4)) == 0x1626ba7e;
        }

        return false;
    }

    /// @notice Verify Merkle proof
    /// @dev Standard Merkle proof verification algorithm
    function _verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }
}

/*//////////////////////////////////////////////////////////////
                            SAFE INTERFACES
//////////////////////////////////////////////////////////////*/

/// @notice Safe operation type
enum Operation {
    Call,
    DelegateCall
}

/// @notice Safe interface
interface ISafe {
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success);
}
