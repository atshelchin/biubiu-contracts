// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlashLoanAdapter} from "../IFlashLoanAdapter.sol";
import {IChainExecutorModule} from "../IChainExecutorModule.sol";

/// @title AaveV3Adapter
/// @notice Flash loan adapter for Aave V3 protocol
/// @author BiuBiu
contract AaveV3Adapter is IFlashLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Aave V3 Pool address
    address public immutable aavePool;

    /// @notice Flash loan execution context
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

    constructor(address _aavePool) {
        aavePool = _aavePool;
    }

    /*//////////////////////////////////////////////////////////////
                            ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a flash loan from Aave V3
    /// @param module The ChainExecutorModule address
    /// @param safe The Safe wallet address
    /// @param adapterData Encoded (address token, uint256 amount)
    /// @param callbackData Data to pass to module's onFlashLoanCallback
    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external
    {
        // Decode adapter data
        (address token, uint256 amount) = abi.decode(adapterData, (address, uint256));

        // Store context for callback
        _context = FlashLoanContext({module: module, safe: safe, callbackData: callbackData, active: true});

        // Prepare Aave flash loan parameters
        address[] memory assets = new address[](1);
        assets[0] = token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0; // No debt

        // Initiate flash loan
        // Aave will callback executeOperation
        IAavePool(aavePool)
            .flashLoan(
                address(this), // receiver
                assets,
                amounts,
                interestRateModes,
                address(this), // onBehalfOf
                "", // params (we use internal context)
                0 // referralCode
            );

        // Clear context
        delete _context;
    }

    /// @notice Aave V3 flash loan callback
    /// @dev Called by Aave Pool after transferring the flash loan amount
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata /* params */
    ) external returns (bool) {
        // 1. Verify callback is from Aave Pool
        if (msg.sender != aavePool) {
            revert InvalidCallback();
        }
        if (initiator != address(this)) {
            revert InvalidCallback();
        }

        // 2. Get context
        FlashLoanContext memory ctx = _context;
        if (!ctx.active) {
            revert InvalidCallback();
        }

        address token = assets[0];
        uint256 amount = amounts[0];
        uint256 fee = premiums[0];

        // 3. Transfer borrowed tokens to Safe
        IERC20(token).transfer(ctx.safe, amount);

        // 4. Callback to module to execute user's calls
        IChainExecutorModule(ctx.module).onFlashLoanCallback(token, amount, fee, ctx.callbackData);

        // 5. After module callback, tokens should be back in this adapter
        // Module calls _transferTokenViaSafe to send repayment amount here

        // 6. Approve Aave Pool to pull repayment
        uint256 repayAmount = amount + fee;
        IERC20(token).approve(aavePool, repayAmount);

        return true;
    }
}

/*//////////////////////////////////////////////////////////////
                        EXTERNAL INTERFACES
//////////////////////////////////////////////////////////////*/

interface IAavePool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
