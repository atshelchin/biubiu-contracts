// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IChainExecutorModule} from "./IChainExecutorModule.sol";
import {IFlashLoanAdapter} from "./IFlashLoanAdapter.sol";
import {ChainedCallExecutor} from "./ChainedCallExecutor.sol";

/// @title ChainExecutorModule
/// @notice Safe Module: Chained execution with dynamic parameter injection and flash loan support
/// @dev Supports direct calls, ERC-4337 mode, and flash loan execution via adapters
/// @author BiuBiu
contract ChainExecutorModule is IChainExecutorModule {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice ChainedCallExecutor for delegatecall execution with injection support
    address public immutable executor;

    /// @notice Used execution hashes (for replay protection)
    /// @dev key = keccak256(safe, chainId, calls, deadline) or with adapter
    mapping(bytes32 => bool) public usedExecutions;

    /// @notice Flash loan execution context
    struct FlashLoanContext {
        address safe;
        address adapter;
        bytes32 callsHash;
        bool active;
    }

    /// @dev Current flash loan context (used during callback)
    FlashLoanContext private _flashLoanContext;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _executor) {
        executor = _executor;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Direct call mode - anyone can call, requires owner signature
    function execute(address safe, Call[] calldata calls, uint64 deadline, bytes calldata signature) external payable {
        // 1. Check expiration
        if (deadline != 0 && block.timestamp > deadline) {
            revert Expired();
        }

        // 2. Compute execution hash and check not used
        bytes32 executionHash = _computeExecutionHash(safe, calls, deadline);
        if (usedExecutions[executionHash]) {
            revert AlreadyExecuted();
        }

        // 3. Verify owner signature
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", executionHash));
        if (!_isValidSignature(safe, ethSignedHash, signature)) {
            revert InvalidSignature();
        }

        // 4. Mark as used
        usedExecutions[executionHash] = true;

        // 5. Execute calls via Safe
        bytes32 executionId = _executeCallsViaSafe(safe, calls);

        emit Executed(safe, calls.length, executionId);
    }

    /// @notice ERC-4337 mode - msg.sender is Safe
    function executeFromSafe(Call[] calldata calls) external payable {
        address safe = msg.sender;

        // Execute calls via Safe (msg.sender is already the Safe)
        bytes32 executionId = _executeCallsViaSafe(safe, calls);

        emit Executed(safe, calls.length, executionId);
    }

    /// @notice Execute with flash loan
    function executeWithFlashLoan(
        address safe,
        FlashLoanParams calldata flashLoanParams,
        Call[] calldata calls,
        uint64 deadline,
        bytes calldata signature
    ) external {
        // 1. Check expiration
        if (deadline != 0 && block.timestamp > deadline) {
            revert Expired();
        }

        // 2. Check no flash loan in progress (reentrancy protection)
        if (_flashLoanContext.active) {
            revert FlashLoanInProgress();
        }

        // 3. Compute execution hash and check not used
        bytes32 executionHash = _computeFlashLoanExecutionHash(safe, flashLoanParams, calls, deadline);
        if (usedExecutions[executionHash]) {
            revert AlreadyExecuted();
        }

        // 4. Verify owner signature (includes adapter address - user trusts this adapter)
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", executionHash));
        if (!_isValidSignature(safe, ethSignedHash, signature)) {
            revert InvalidSignature();
        }

        // 5. Mark as used
        usedExecutions[executionHash] = true;

        // 6. Store context for callback verification
        _flashLoanContext = FlashLoanContext({
            safe: safe, adapter: flashLoanParams.adapter, callsHash: keccak256(abi.encode(calls)), active: true
        });

        // 7. Initiate flash loan via adapter
        // Adapter will callback onFlashLoanCallback after receiving funds
        IFlashLoanAdapter(flashLoanParams.adapter)
            .initiateFlashLoan(address(this), safe, flashLoanParams.adapterData, abi.encode(calls));

        // 8. Clear context
        delete _flashLoanContext;
    }

    /// @notice Callback from flash loan adapter
    function onFlashLoanCallback(address token, uint256 amount, uint256 fee, bytes calldata data) external {
        // 1. Verify callback is from expected adapter
        FlashLoanContext memory ctx = _flashLoanContext;
        if (!ctx.active) {
            revert NoFlashLoanInProgress();
        }
        if (msg.sender != ctx.adapter) {
            revert InvalidCallback();
        }

        // 2. Decode and verify calls
        Call[] memory calls = abi.decode(data, (Call[]));
        if (keccak256(abi.encode(calls)) != ctx.callsHash) {
            revert InvalidCallback();
        }

        // 3. Execute calls via Safe
        bytes32 executionId = _executeCallsViaSafeMemory(ctx.safe, calls);

        // 4. Transfer tokens back to adapter for repayment
        // The adapter will handle the actual repayment to the protocol
        uint256 repayAmount = amount + fee;
        _transferTokenViaSafe(ctx.safe, token, msg.sender, repayAmount);

        emit FlashLoanExecuted(ctx.safe, ctx.adapter, calls.length, executionId);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute the execution hash
    function getExecutionHash(address safe, Call[] calldata calls, uint64 deadline) external view returns (bytes32) {
        return _computeExecutionHash(safe, calls, deadline);
    }

    /// @notice Compute the flash loan execution hash
    function getFlashLoanExecutionHash(
        address safe,
        FlashLoanParams calldata flashLoanParams,
        Call[] calldata calls,
        uint64 deadline
    ) external view returns (bytes32) {
        return _computeFlashLoanExecutionHash(safe, flashLoanParams, calls, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _computeExecutionHash(address safe, Call[] calldata calls, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(safe, block.chainid, calls, deadline));
    }

    function _computeFlashLoanExecutionHash(
        address safe,
        FlashLoanParams calldata flashLoanParams,
        Call[] calldata calls,
        uint64 deadline
    ) internal view returns (bytes32) {
        // Include adapter address in hash - user signs to trust this specific adapter
        return keccak256(
            abi.encode(safe, block.chainid, flashLoanParams.adapter, flashLoanParams.adapterData, calls, deadline)
        );
    }

    /// @notice Execute calls via Safe using delegatecall to executor
    /// @dev Delegatecall allows executor to run in Safe's context and capture return data
    function _executeCallsViaSafe(address safe, Call[] calldata calls) internal returns (bytes32 executionId) {
        // Convert calldata to memory for encoding
        Call[] memory callsMemory = calls;
        return _executeCallsViaSafeMemory(safe, callsMemory);
    }

    /// @notice Execute calls via Safe (memory version for callback)
    function _executeCallsViaSafeMemory(address safe, Call[] memory calls) internal returns (bytes32 executionId) {
        // Encode the delegatecall to executor
        bytes memory executorCallData = abi.encodeCall(ChainedCallExecutor.executeChainedCalls, (calls));

        // Execute via Safe with DelegateCall to executor
        // This runs executor code in Safe's context, allowing return data capture
        bool success = ISafe(safe).execTransactionFromModule(executor, 0, executorCallData, Operation.DelegateCall);
        if (!success) {
            revert ExecutionFailed();
        }

        executionId = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, safe));
    }

    /// @notice Transfer token via Safe
    function _transferTokenViaSafe(address safe, address token, address to, uint256 amount) internal {
        bytes memory transferData = abi.encodeWithSelector(0xa9059cbb, to, amount); // transfer(address,uint256)
        bool success = ISafe(safe).execTransactionFromModule(token, 0, transferData, Operation.Call);
        if (!success) {
            revert ExecutionFailed();
        }
    }

    /// @notice Verify signature via Safe's ERC-1271
    function _isValidSignature(address safe, bytes32 hash, bytes calldata signature) internal view returns (bool) {
        (bool success, bytes memory result) = safe.staticcall(abi.encodeWithSelector(0x1626ba7e, hash, signature));

        if (success && result.length >= 32) {
            return abi.decode(result, (bytes4)) == 0x1626ba7e;
        }

        return false;
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
