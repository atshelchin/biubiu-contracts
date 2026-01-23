// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlashLoanAdapter} from "../IFlashLoanAdapter.sol";
import {IChainExecutorModule} from "../IChainExecutorModule.sol";

/// @title UniswapV3Adapter
/// @notice Flash loan adapter for Uniswap V3 protocol
/// @dev Uses Uniswap V3 pool's flash function
/// @author BiuBiu
contract UniswapV3Adapter is IFlashLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    struct FlashLoanContext {
        address module;
        address safe;
        address pool;
        bytes callbackData;
        bool active;
    }

    FlashLoanContext private _context;

    /*//////////////////////////////////////////////////////////////
                            ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a flash loan from Uniswap V3
    /// @param module The ChainExecutorModule address
    /// @param safe The Safe wallet address
    /// @param adapterData Encoded (address pool, address token0, address token1, uint256 amount0, uint256 amount1)
    /// @param callbackData Data to pass to module's onFlashLoanCallback
    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external
    {
        // Decode adapter data
        (address pool, address token0, address token1, uint256 amount0, uint256 amount1) =
            abi.decode(adapterData, (address, address, address, uint256, uint256));

        // Store context for callback
        _context = FlashLoanContext({module: module, safe: safe, pool: pool, callbackData: callbackData, active: true});

        // Initiate flash loan
        // Uniswap V3 will callback uniswapV3FlashCallback
        IUniswapV3Pool(pool)
            .flash(
                address(this),
                amount0,
                amount1,
                abi.encode(token0, token1) // Pass token addresses for callback
            );

        // Clear context
        delete _context;
    }

    /// @notice Uniswap V3 flash loan callback
    /// @dev Called by Uniswap V3 Pool after transferring the flash loan amount
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        // 1. Verify callback
        FlashLoanContext memory ctx = _context;
        if (!ctx.active) {
            revert InvalidCallback();
        }
        if (msg.sender != ctx.pool) {
            revert InvalidCallback();
        }

        // 2. Decode token addresses
        (address token0, address token1) = abi.decode(data, (address, address));

        // 3. Get borrowed amounts
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // 4. Determine which token was borrowed (or both)
        address token;
        uint256 amount;
        uint256 fee;

        if (balance0 > 0 && balance1 == 0) {
            token = token0;
            amount = balance0;
            fee = fee0;
        } else if (balance1 > 0 && balance0 == 0) {
            token = token1;
            amount = balance1;
            fee = fee1;
        } else {
            // Both tokens borrowed - for simplicity, handle token0
            // In production, you might want to handle this differently
            token = token0;
            amount = balance0;
            fee = fee0;

            // Transfer token1 to safe as well
            if (balance1 > 0) {
                IERC20(token1).transfer(ctx.safe, balance1);
            }
        }

        // 5. Transfer borrowed tokens to Safe
        if (amount > 0) {
            IERC20(token).transfer(ctx.safe, amount);
        }

        // 6. Callback to module
        IChainExecutorModule(ctx.module).onFlashLoanCallback(token, amount, fee, ctx.callbackData);

        // 7. After callback, repay to pool
        // Module should have transferred repayment back to this adapter
        if (balance0 > 0) {
            IERC20(token0).transfer(ctx.pool, balance0 + fee0);
        }
        if (balance1 > 0) {
            IERC20(token1).transfer(ctx.pool, balance1 + fee1);
        }
    }
}

/*//////////////////////////////////////////////////////////////
                        EXTERNAL INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV3Pool {
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;

    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
