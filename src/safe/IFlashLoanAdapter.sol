// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IFlashLoanAdapter
/// @notice Interface for flash loan protocol adapters
/// @dev Adapters bridge different flash loan protocols to ChainExecutorModule
/// @author BiuBiu
interface IFlashLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error FlashLoanFailed();
    error InvalidCallback();
    error RepaymentFailed();

    /*//////////////////////////////////////////////////////////////
                            ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a flash loan
    /// @dev The adapter will:
    ///      1. Request flash loan from the protocol
    ///      2. Receive callback from protocol
    ///      3. Transfer borrowed tokens to `safe`
    ///      4. Call module.onFlashLoanCallback(token, amount, fee, callbackData)
    ///      5. Pull tokens from `safe` to repay (via module)
    ///      6. Repay the protocol
    /// @param module The ChainExecutorModule address to callback
    /// @param safe The Safe wallet that will receive/repay tokens
    /// @param adapterData Protocol-specific parameters (encoded)
    /// @param callbackData Data to pass to module's onFlashLoanCallback
    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external;
}
