// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlashLoanAdapter} from "../IFlashLoanAdapter.sol";
import {IChainExecutorModule} from "../IChainExecutorModule.sol";

/// @title UniswapV2Adapter
/// @notice Flash loan adapter for Uniswap V2 (and forks like Sushiswap)
/// @dev Uses Uniswap V2 pair's swap function (flash swap)
/// @author BiuBiu
contract UniswapV2Adapter is IFlashLoanAdapter {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    struct FlashLoanContext {
        address module;
        address safe;
        address pair;
        address tokenBorrow;
        uint256 amountBorrow;
        bytes callbackData;
        bool active;
    }

    FlashLoanContext private _context;

    /*//////////////////////////////////////////////////////////////
                            ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiate a flash swap from Uniswap V2
    /// @param module The ChainExecutorModule address
    /// @param safe The Safe wallet address
    /// @param adapterData Encoded (address pair, address tokenBorrow, uint256 amount)
    /// @param callbackData Data to pass to module's onFlashLoanCallback
    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external
    {
        // Decode adapter data
        (address pair, address tokenBorrow, uint256 amount) = abi.decode(adapterData, (address, address, uint256));

        // Store context for callback
        _context = FlashLoanContext({
            module: module,
            safe: safe,
            pair: pair,
            tokenBorrow: tokenBorrow,
            amountBorrow: amount,
            callbackData: callbackData,
            active: true
        });

        // Determine which token to borrow (token0 or token1)
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint256 amount0Out;
        uint256 amount1Out;

        if (tokenBorrow == token0) {
            amount0Out = amount;
            amount1Out = 0;
        } else if (tokenBorrow == token1) {
            amount0Out = 0;
            amount1Out = amount;
        } else {
            revert InvalidCallback();
        }

        // Initiate flash swap
        // Uniswap V2 will callback uniswapV2Call
        // The data parameter being non-empty triggers the callback
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(tokenBorrow, amount));

        // Clear context
        delete _context;
    }

    /// @notice Uniswap V2 / Sushiswap flash swap callback
    /// @dev Called by Uniswap V2 Pair during swap when data is non-empty
    function uniswapV2Call(
        address sender,
        uint256,
        /* amount0 */
        uint256,
        /* amount1 */
        bytes calldata /* data */
    )
        external
    {
        _handleCallback(sender);
    }

    /// @notice PancakeSwap callback
    function pancakeCall(
        address sender,
        uint256,
        /* amount0 */
        uint256,
        /* amount1 */
        bytes calldata /* data */
    )
        external
    {
        _handleCallback(sender);
    }

    function _handleCallback(address sender) internal {
        // 1. Verify callback
        FlashLoanContext memory ctx = _context;
        if (!ctx.active) {
            revert InvalidCallback();
        }
        if (msg.sender != ctx.pair) {
            revert InvalidCallback();
        }
        if (sender != address(this)) {
            revert InvalidCallback();
        }

        // 2. Calculate fee (0.3% for Uniswap V2)
        // repayAmount = amount * 1000 / 997 + 1 (round up)
        uint256 fee = (ctx.amountBorrow * 3) / 997 + 1;

        // 3. Transfer borrowed tokens to Safe
        IERC20(ctx.tokenBorrow).transfer(ctx.safe, ctx.amountBorrow);

        // 4. Callback to module
        IChainExecutorModule(ctx.module).onFlashLoanCallback(ctx.tokenBorrow, ctx.amountBorrow, fee, ctx.callbackData);

        // 5. After callback, repay to pair
        // Module should have transferred repayment back to this adapter
        uint256 repayAmount = ctx.amountBorrow + fee;
        IERC20(ctx.tokenBorrow).transfer(ctx.pair, repayAmount);
    }
}

/*//////////////////////////////////////////////////////////////
                        EXTERNAL INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
