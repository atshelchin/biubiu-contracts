// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IChainExecutorModule
/// @notice Safe Module interface: Chained execution with dynamic parameter injection
/// @author BiuBiu
interface IChainExecutorModule {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Parameter injection rule
    struct Injection {
        uint16 sourceCallIndex; // Which previous call's return value to use
        uint16 sourceReturnOffset; // Offset in the return data
        uint16 sourceReturnLength; // Length of data to copy
        uint16 targetCalldataOffset; // Where to inject in calldata
    }

    /// @notice Single call definition with injection support
    struct Call {
        address target;
        uint256 value;
        bytes data;
        Injection[] injections;
    }

    /// @notice Flash loan execution parameters
    struct FlashLoanParams {
        address adapter; // Flash loan adapter address
        bytes adapterData; // Adapter-specific data (token, amount, etc.)
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Executed(address indexed safe, uint256 callCount, bytes32 indexed executionId);

    event FlashLoanExecuted(
        address indexed safe, address indexed adapter, uint256 callCount, bytes32 indexed executionId
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Expired();
    error InvalidSignature();
    error AlreadyExecuted();
    error CallFailed(uint256 index, bytes reason);
    error ExecutionFailed();
    error InvalidCallback();
    error FlashLoanInProgress();
    error NoFlashLoanInProgress();

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if an execution hash has been used
    /// @param executionHash Hash of the execution parameters
    function usedExecutions(bytes32 executionHash) external view returns (bool);

    /// @notice Compute the execution hash
    /// @param safe Safe wallet address
    /// @param calls Calls to execute
    /// @param deadline Expiration timestamp
    function getExecutionHash(address safe, Call[] calldata calls, uint64 deadline) external view returns (bytes32);

    /// @notice Compute the flash loan execution hash
    /// @param safe Safe wallet address
    /// @param flashLoanParams Flash loan parameters
    /// @param calls Calls to execute
    /// @param deadline Expiration timestamp
    function getFlashLoanExecutionHash(
        address safe,
        FlashLoanParams calldata flashLoanParams,
        Call[] calldata calls,
        uint64 deadline
    ) external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                            EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Direct call mode - anyone can call, requires owner signature
    /// @param safe Safe wallet address
    /// @param calls Calls to execute
    /// @param deadline Expiration timestamp (0 = never expires)
    /// @param signature Owner signature
    function execute(address safe, Call[] calldata calls, uint64 deadline, bytes calldata signature) external payable;

    /// @notice ERC-4337 mode - called via Safe (msg.sender = Safe)
    /// @param calls Calls to execute
    function executeFromSafe(Call[] calldata calls) external payable;

    /// @notice Execute with flash loan - anyone can call, requires owner signature
    /// @param safe Safe wallet address
    /// @param flashLoanParams Flash loan parameters (adapter + data)
    /// @param calls Calls to execute after receiving flash loan
    /// @param deadline Expiration timestamp (0 = never expires)
    /// @param signature Owner signature of (safe, chainId, adapter, calls, deadline)
    function executeWithFlashLoan(
        address safe,
        FlashLoanParams calldata flashLoanParams,
        Call[] calldata calls,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Callback from flash loan adapter
    /// @dev Only callable by the expected adapter during flash loan execution
    /// @param token Token received from flash loan
    /// @param amount Amount received
    /// @param fee Fee to repay
    /// @param data Encoded calls to execute
    function onFlashLoanCallback(address token, uint256 amount, uint256 fee, bytes calldata data) external;
}
