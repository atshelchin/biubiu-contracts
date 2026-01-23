// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMerkleModule
/// @notice Safe Module interface: Merkle-based pre-authorization, each leaf can only be executed once
/// @author BiuBiu
interface IMerkleModule {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Single call definition
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Executed(
        address indexed safe, bytes32 indexed merkleRoot, bytes32 indexed leaf, address target, uint256 value
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Expired();
    error InvalidSignature();
    error InvalidProof();
    error LeafAlreadyUsed();
    error ExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a leaf has been used
    /// @param leafKey keccak256(safe, chainId, merkleRoot, leaf)
    function usedLeaves(bytes32 leafKey) external view returns (bool);

    /// @notice Compute the leaf key
    /// @param safe Safe wallet address
    /// @param merkleRoot Merkle root
    /// @param leaf Leaf node
    function getLeafKey(address safe, bytes32 merkleRoot, bytes32 leaf) external view returns (bytes32);

    /// @notice Compute the leaf node
    /// @param call Call data
    function getLeaf(Call calldata call) external pure returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                            EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Direct call mode - anyone can call, requires owner signature
    /// @param safe Safe wallet address
    /// @param merkleRoot Authorized Merkle root
    /// @param deadline Expiration timestamp (0 = never expires)
    /// @param proof Merkle proof
    /// @param call Call to execute
    /// @param signature Owner signature of (safe, chainId, merkleRoot, deadline)
    function execute(
        address safe,
        bytes32 merkleRoot,
        uint64 deadline,
        bytes32[] calldata proof,
        Call calldata call,
        bytes calldata signature
    ) external;

    /// @notice ERC-4337 mode - called via Safe (msg.sender = Safe)
    /// @param merkleRoot Authorized Merkle root
    /// @param deadline Expiration timestamp (0 = never expires)
    /// @param proof Merkle proof
    /// @param call Call to execute
    /// @param signature Owner signature of (safe, chainId, merkleRoot, deadline)
    function executeFromSafe(
        bytes32 merkleRoot,
        uint64 deadline,
        bytes32[] calldata proof,
        Call calldata call,
        bytes calldata signature
    ) external;
}
