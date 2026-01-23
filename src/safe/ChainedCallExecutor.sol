// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IChainExecutorModule} from "./IChainExecutorModule.sol";

/// @title ChainedCallExecutor
/// @notice Stateless executor for chained calls with parameter injection
/// @dev Designed to be called via delegatecall from Safe wallet
/// @author BiuBiu
contract ChainedCallExecutor {
    /// @notice Execute chained calls with injection support
    /// @dev Must be called via delegatecall from Safe
    /// @param calls Array of calls to execute
    /// @return executionId Unique identifier for this execution
    function executeChainedCalls(IChainExecutorModule.Call[] memory calls) external returns (bytes32 executionId) {
        uint256 len = calls.length;
        bytes[] memory results = new bytes[](len);

        for (uint256 i; i < len; ++i) {
            IChainExecutorModule.Call memory c = calls[i];

            // Apply injections if any
            bytes memory finalCallData =
                c.injections.length > 0 ? _applyInjections(c.data, c.injections, results) : c.data;

            // Execute call (we're in Safe's context via delegatecall)
            (bool success, bytes memory returnData) = c.target.call{value: c.value}(finalCallData);
            if (!success) {
                // Revert with call index and error data
                assembly {
                    // Store call index at position 0
                    mstore(0x00, i)
                    // Revert with returnData
                    revert(add(returnData, 32), mload(returnData))
                }
            }

            // Store return data for subsequent injections
            results[i] = returnData;
        }

        executionId = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, address(this)));
    }

    /// @notice Apply parameter injections
    function _applyInjections(
        bytes memory originalCallData,
        IChainExecutorModule.Injection[] memory injections,
        bytes[] memory previousResults
    ) internal pure returns (bytes memory result) {
        result = originalCallData;

        for (uint256 i; i < injections.length; ++i) {
            IChainExecutorModule.Injection memory inj = injections[i];

            if (inj.sourceCallIndex >= previousResults.length) continue;
            bytes memory src = previousResults[inj.sourceCallIndex];
            if (src.length == 0) continue;
            if (inj.sourceReturnOffset + inj.sourceReturnLength > src.length) continue;
            if (inj.targetCalldataOffset + inj.sourceReturnLength > result.length) continue;

            for (uint256 j; j < inj.sourceReturnLength; ++j) {
                result[inj.targetCalldataOffset + j] = src[inj.sourceReturnOffset + j];
            }
        }
    }
}
