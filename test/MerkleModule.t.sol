// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MerkleModule, ISafe, Operation} from "../src/safe/MerkleModule.sol";
import {IMerkleModule} from "../src/safe/IMerkleModule.sol";

/// @notice Mock Safe contract
contract MockSafe {
    // Enabled modules
    mapping(address => bool) public enabledModules;

    // Record executed transactions
    struct ExecutedTx {
        address to;
        uint256 value;
        bytes data;
    }

    ExecutedTx[] public executedTxs;

    // ERC-1271 signature verification
    mapping(bytes32 => bool) public approvedHashes;

    constructor() {}

    function enableModule(address module) external {
        enabledModules[module] = true;
    }

    function disableModule(address module) external {
        enabledModules[module] = false;
    }

    /// @notice Mock Safe's execTransactionFromModule
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation)
        external
        returns (bool success)
    {
        require(enabledModules[msg.sender], "Module not enabled");

        executedTxs.push(ExecutedTx({to: to, value: value, data: data}));

        // Execute call
        (success,) = to.call{value: value}(data);
    }

    /// @notice Mock Safe's ERC-1271 isValidSignature
    /// @dev Safe uses checkSignatures for multi-sig, simplified here
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        // Simplified: recover signer from signature, check if owner
        // Real Safe checks if threshold is reached
        if (_recoverSigner(hash, signature) == owner) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }

    /// @notice Set owner (for testing)
    address public owner;

    function setOwner(address _owner) external {
        owner = _owner;
    }

    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) v += 27;

        return ecrecover(hash, v, r, s);
    }

    function getExecutedTxCount() external view returns (uint256) {
        return executedTxs.length;
    }

    receive() external payable {}
}

/// @notice Mock Target contract
contract MockTarget {
    uint256 public value;
    address public lastCaller;

    function setValue(uint256 _value) external payable {
        value = _value;
        lastCaller = msg.sender;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    receive() external payable {}
}

contract MerkleModuleTest is Test {
    MerkleModule public module;
    MockSafe public safe;
    MockTarget public target;

    uint256 internal ownerPrivateKey;
    address internal owner;

    function setUp() public {
        // Create owner
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        // Deploy contracts
        module = new MerkleModule();
        safe = new MockSafe();
        target = new MockTarget();

        // Configure Safe
        safe.setOwner(owner);
        safe.enableModule(address(module));

        // Fund Safe with ETH
        vm.deal(address(safe), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Build Merkle Tree and return root and proof
    /// @dev Simplified: only supports single leaf (empty proof)
    function _buildSingleLeafTree(IMerkleModule.Call memory call)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof, bytes32 leaf)
    {
        leaf = keccak256(abi.encode(call.target, call.value, call.data));
        root = leaf; // Single leaf tree, root = leaf
        proof = new bytes32[](0);
    }

    /// @notice Build two-leaf Merkle Tree
    function _buildTwoLeafTree(IMerkleModule.Call memory call1, IMerkleModule.Call memory call2)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2, bytes32 leaf1, bytes32 leaf2)
    {
        leaf1 = keccak256(abi.encode(call1.target, call1.value, call1.data));
        leaf2 = keccak256(abi.encode(call2.target, call2.value, call2.data));

        // Sort and compute root
        if (leaf1 <= leaf2) {
            root = keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            root = keccak256(abi.encodePacked(leaf2, leaf1));
        }

        // Build proofs
        proof1 = new bytes32[](1);
        proof1[0] = leaf2;

        proof2 = new bytes32[](1);
        proof2[0] = leaf1;
    }

    /// @notice Sign authorization message
    function _signAuth(address _safe, bytes32 merkleRoot, uint64 deadline)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 authHash = keccak256(abi.encode(_safe, block.chainid, merkleRoot, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", authHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        signature = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                              BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_SingleLeaf() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Execute
        module.execute(address(safe), root, deadline, proof, call, signature);

        // Verify
        assertEq(target.value(), 42);
        assertEq(target.lastCaller(), address(safe));
        assertEq(safe.getExecutedTxCount(), 1);
    }

    function test_Execute_WithValue() public {
        // Build call with ETH
        IMerkleModule.Call memory call = IMerkleModule.Call({
            target: address(target), value: 1 ether, data: abi.encodeCall(MockTarget.setValue, (100))
        });

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Execute
        module.execute(address(safe), root, deadline, proof, call, signature);

        // Verify
        assertEq(target.value(), 100);
        assertEq(address(target).balance, 1 ether);
    }

    function test_Execute_TwoLeaves() public {
        // Build two calls
        IMerkleModule.Call memory call1 =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (111))});

        IMerkleModule.Call memory call2 =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (222))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2,,) = _buildTwoLeafTree(call1, call2);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Execute first call
        module.execute(address(safe), root, deadline, proof1, call1, signature);
        assertEq(target.value(), 111);

        // Execute second call
        module.execute(address(safe), root, deadline, proof2, call2, signature);
        assertEq(target.value(), 222);

        // Both executions succeeded
        assertEq(safe.getExecutedTxCount(), 2);
    }

    function test_ExecuteFromSafe() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (999))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Simulate call from Safe (4337 mode)
        vm.prank(address(safe));
        module.executeFromSafe(root, deadline, proof, call, signature);

        // Verify
        assertEq(target.value(), 999);
    }

    /*//////////////////////////////////////////////////////////////
                              DEADLINE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_NoDeadline() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization (deadline = 0 means never expires)
        uint64 deadline = 0;
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Can execute even after a long time
        vm.warp(block.timestamp + 365 days);
        module.execute(address(safe), root, deadline, proof, call, signature);

        assertEq(target.value(), 42);
    }

    function test_Revert_Expired() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Time expired
        vm.warp(block.timestamp + 2 hours);

        // Should revert
        vm.expectRevert(IMerkleModule.Expired.selector);
        module.execute(address(safe), root, deadline, proof, call, signature);
    }

    /*//////////////////////////////////////////////////////////////
                           REPLAY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_LeafAlreadyUsed() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        // Sign authorization
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // First execution succeeds
        module.execute(address(safe), root, deadline, proof, call, signature);

        // Second execution should fail
        vm.expectRevert(IMerkleModule.LeafAlreadyUsed.selector);
        module.execute(address(safe), root, deadline, proof, call, signature);
    }

    function test_SameLeaf_DifferentRoot_CanExecute() public {
        // Same call can be executed under different merkleRoots

        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // First tree (single leaf)
        (bytes32 root1, bytes32[] memory proof1,) = _buildSingleLeafTree(call);

        // Second tree (combined with another call)
        IMerkleModule.Call memory dummyCall =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (999))});
        (bytes32 root2, bytes32[] memory proof2,,,) = _buildTwoLeafTree(call, dummyCall);

        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Sign two different roots
        bytes memory sig1 = _signAuth(address(safe), root1, deadline);
        bytes memory sig2 = _signAuth(address(safe), root2, deadline);

        // Both executions should succeed (different merkleRoots)
        module.execute(address(safe), root1, deadline, proof1, call, sig1);
        module.execute(address(safe), root2, deadline, proof2, call, sig2);

        assertEq(safe.getExecutedTxCount(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                           SIGNATURE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_InvalidSignature() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Build Merkle tree
        (bytes32 root, bytes32[] memory proof,) = _buildSingleLeafTree(call);

        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Sign with wrong private key
        uint256 wrongKey = 0xBAD;
        bytes32 authHash = keccak256(abi.encode(address(safe), block.chainid, root, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", authHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        // Should revert
        vm.expectRevert(IMerkleModule.InvalidSignature.selector);
        module.execute(address(safe), root, deadline, proof, call, wrongSignature);
    }

    function test_Revert_InvalidProof() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        // Use a completely different root
        bytes32 fakeRoot = keccak256("fake root");
        bytes32[] memory emptyProof = new bytes32[](0);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), fakeRoot, deadline);

        // Should revert (call not in fakeRoot's tree)
        vm.expectRevert(IMerkleModule.InvalidProof.selector);
        module.execute(address(safe), fakeRoot, deadline, emptyProof, call, signature);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetLeaf() public view {
        IMerkleModule.Call memory call = IMerkleModule.Call({
            target: address(target), value: 1 ether, data: abi.encodeCall(MockTarget.setValue, (42))
        });

        bytes32 leaf = module.getLeaf(call);
        bytes32 expectedLeaf = keccak256(abi.encode(call.target, call.value, call.data));

        assertEq(leaf, expectedLeaf);
    }

    function test_GetLeafKey() public view {
        bytes32 merkleRoot = keccak256("test root");
        bytes32 leaf = keccak256("test leaf");

        bytes32 leafKey = module.getLeafKey(address(safe), merkleRoot, leaf);
        bytes32 expectedKey = keccak256(abi.encode(address(safe), block.chainid, merkleRoot, leaf));

        assertEq(leafKey, expectedKey);
    }

    function test_UsedLeaves() public {
        // Build call
        IMerkleModule.Call memory call =
            IMerkleModule.Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.setValue, (42))});

        (bytes32 root, bytes32[] memory proof, bytes32 leaf) = _buildSingleLeafTree(call);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signAuth(address(safe), root, deadline);

        // Before execution: not used
        bytes32 leafKey = module.getLeafKey(address(safe), root, leaf);
        assertFalse(module.usedLeaves(leafKey));

        // Execute
        module.execute(address(safe), root, deadline, proof, call, signature);

        // After execution: used
        assertTrue(module.usedLeaves(leafKey));
    }
}
