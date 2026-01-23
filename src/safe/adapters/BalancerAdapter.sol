// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlashLoanAdapter} from "../IFlashLoanAdapter.sol";
import {IChainExecutorModule} from "../IChainExecutorModule.sol";

/// @title BalancerAdapter
/// @notice Flash loan adapter for Balancer protocol
/// @dev Uses Balancer Vault's flashLoan function (no fee!)
/// @author BiuBiu
contract BalancerAdapter is IFlashLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Balancer Vault address
    address public immutable balancerVault;

    struct FlashLoanContext {
        address module;
        address safe;
        bytes callbackData;
        bool active;
    }

    FlashLoanContext private _context;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _balancerVault) {
        balancerVault = _balancerVault;
    }

    /*//////////////////////////////////////////////////////////////
                            ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a flash loan from Balancer
    /// @param module The ChainExecutorModule address
    /// @param safe The Safe wallet address
    /// @param adapterData Encoded (address[] tokens, uint256[] amounts)
    /// @param callbackData Data to pass to module's onFlashLoanCallback
    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external
    {
        // Decode adapter data
        (address[] memory tokens, uint256[] memory amounts) = abi.decode(adapterData, (address[], uint256[]));

        // Store context for callback
        _context = FlashLoanContext({module: module, safe: safe, callbackData: callbackData, active: true});

        // Initiate flash loan
        // Balancer will callback receiveFlashLoan
        IBalancerVault(balancerVault)
            .flashLoan(
                IFlashLoanRecipient(address(this)),
                tokens,
                amounts,
                abi.encode(tokens) // Pass token addresses for callback
            );

        // Clear context
        delete _context;
    }

    /// @notice Balancer flash loan callback
    /// @dev Called by Balancer Vault after transferring the flash loan amount
    /// @param tokens Tokens received
    /// @param amounts Amounts received
    /// @param feeAmounts Fees to repay (usually 0 for Balancer)
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory /* userData */
    ) external {
        // 1. Verify callback
        FlashLoanContext memory ctx = _context;
        if (!ctx.active) {
            revert InvalidCallback();
        }
        if (msg.sender != balancerVault) {
            revert InvalidCallback();
        }

        // 2. Transfer all borrowed tokens to Safe
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).transfer(ctx.safe, amounts[i]);
            }
        }

        // 3. Callback to module (using first token as primary)
        // For multi-token flash loans, the module should handle appropriately
        address primaryToken = tokens[0];
        uint256 primaryAmount = amounts[0];
        uint256 primaryFee = feeAmounts[0];

        IChainExecutorModule(ctx.module).onFlashLoanCallback(primaryToken, primaryAmount, primaryFee, ctx.callbackData);

        // 4. After callback, repay to vault
        // Module should have transferred repayment back to this adapter
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 repayAmount = amounts[i] + feeAmounts[i];
            IERC20(tokens[i]).transfer(balancerVault, repayAmount);
        }
    }
}

/*//////////////////////////////////////////////////////////////
                        EXTERNAL INTERFACES
//////////////////////////////////////////////////////////////*/

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
