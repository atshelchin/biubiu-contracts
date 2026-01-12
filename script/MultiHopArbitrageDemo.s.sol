// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ChainedExecutor} from "../src/safe/ChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";

/// @notice 模拟 ERC20 代币
contract MockToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice 模拟 Uniswap V2 风格的 DEX
/// @dev 使用恒定乘积公式 x * y = k
contract MockUniswapDEX {
    MockToken public token0;
    MockToken public token1;
    uint256 public reserve0;
    uint256 public reserve1;
    string public dexName;

    constructor(MockToken _token0, MockToken _token1, string memory _name) {
        token0 = _token0;
        token1 = _token1;
        dexName = _name;
    }

    function initLiquidity(uint256 amount0, uint256 amount1) external {
        reserve0 = amount0;
        reserve1 = amount1;
    }

    /// @notice Token0 -> Token1
    function swap0For1(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid input");

        // 恒定乘积: amountOut = amountIn * reserve1 / (reserve0 + amountIn)
        amountOut = amountIn * reserve1 / (reserve0 + amountIn);
        // 0.3% 手续费
        amountOut = amountOut * 997 / 1000;

        require(amountOut > 0 && amountOut < reserve1, "Insufficient output");

        // 先转入再更新
        token0.transfer(address(this), amountIn);
        reserve0 += amountIn;
        reserve1 -= amountOut;
        token1.transfer(msg.sender, amountOut);
    }

    /// @notice Token1 -> Token0
    function swap1For0(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid input");

        amountOut = amountIn * reserve0 / (reserve1 + amountIn);
        amountOut = amountOut * 997 / 1000;

        require(amountOut > 0 && amountOut < reserve0, "Insufficient output");

        token1.transfer(address(this), amountIn);
        reserve1 += amountIn;
        reserve0 -= amountOut;
        token0.transfer(msg.sender, amountOut);
    }

    function getAmountOut(uint256 amountIn, bool zeroForOne) external view returns (uint256) {
        if (zeroForOne) {
            uint256 out = amountIn * reserve1 / (reserve0 + amountIn);
            return out * 997 / 1000;
        } else {
            uint256 out = amountIn * reserve0 / (reserve1 + amountIn);
            return out * 997 / 1000;
        }
    }

    function getPrice() external view returns (uint256) {
        return reserve1 * 1e18 / reserve0;
    }
}

/// @title MultiHopArbitrageDemo
/// @notice 演示跨 DEX 多跳套利
/// @dev 场景: 4 个代币, 5 个 DEX, 寻找最优路径
///
///      代币: WETH, USDC, WBTC, DAI
///
///      DEX 布局:
///      - Uniswap: WETH/USDC (1 ETH = 2000 USDC)
///      - Sushiswap: USDC/WBTC (1 WBTC = 45000 USDC)
///      - Curve: USDC/DAI (1 USDC = 1.01 DAI)
///      - Balancer: DAI/WETH (1 ETH = 1980 DAI) ← ETH 便宜!
///      - PancakeSwap: WBTC/WETH (1 WBTC = 22 ETH)
///
///      套利路径: WETH → USDC → DAI → WETH
///      1. Uniswap: 1 WETH → 2000 USDC
///      2. Curve: 2000 USDC → 2020 DAI
///      3. Balancer: 2020 DAI → 1.02 WETH (因为 1 ETH = 1980 DAI)
///      净利润: ~0.02 ETH (2%)
contract MultiHopArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  Multi-Hop Cross-DEX Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Market Setup:");
        console.log("- Uniswap:    1 ETH = 2000 USDC");
        console.log("- Curve:      1 USDC = 1.01 DAI");
        console.log("- Balancer:   1 ETH = 1980 DAI (ETH is cheaper!)");
        console.log("");
        console.log("Arbitrage Path: ETH -> USDC -> DAI -> ETH");
        console.log("Expected: 1 ETH -> 2000 USDC -> 2020 DAI -> 1.02 ETH");

        // ========== 部署代币 ==========
        MockToken weth = new MockToken("Wrapped Ether", "WETH", 18);
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockToken dai = new MockToken("Dai Stablecoin", "DAI", 18);
        MockToken wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);

        // ========== 部署 DEX ==========
        // Uniswap: WETH/USDC
        MockUniswapDEX uniswap = new MockUniswapDEX(weth, usdc, "Uniswap");
        weth.mint(address(uniswap), 1000 ether);
        usdc.mint(address(uniswap), 2_000_000e6);
        uniswap.initLiquidity(1000 ether, 2_000_000e6);

        // Curve: USDC/DAI (1 USDC = 1.01 DAI 的效果通过不同储备实现)
        // 储备 1,000,000 USDC : 1,010,000 DAI
        MockUniswapDEX curve = new MockUniswapDEX(usdc, dai, "Curve");
        usdc.mint(address(curve), 1_000_000e6);
        dai.mint(address(curve), 1_010_000e18);
        curve.initLiquidity(1_000_000e6, 1_010_000e18);

        // Balancer: DAI/WETH (1 ETH = 1980 DAI，ETH 更便宜)
        // 储备 1,980,000 DAI : 1000 ETH
        MockUniswapDEX balancer = new MockUniswapDEX(dai, weth, "Balancer");
        dai.mint(address(balancer), 1_980_000e18);
        weth.mint(address(balancer), 1000 ether);
        balancer.initLiquidity(1_980_000e18, 1000 ether);

        // Sushiswap: USDC/WBTC
        MockUniswapDEX sushiswap = new MockUniswapDEX(usdc, wbtc, "Sushiswap");
        usdc.mint(address(sushiswap), 4_500_000e6);
        wbtc.mint(address(sushiswap), 100e8);
        sushiswap.initLiquidity(4_500_000e6, 100e8);

        // PancakeSwap: WBTC/WETH
        MockUniswapDEX pancakeswap = new MockUniswapDEX(wbtc, weth, "PancakeSwap");
        wbtc.mint(address(pancakeswap), 100e8);
        weth.mint(address(pancakeswap), 2200 ether);
        pancakeswap.initLiquidity(100e8, 2200 ether);

        console.log("");
        console.log("=== DEX Prices ===");
        console.log("Uniswap (WETH/USDC):", uniswap.getPrice(), "USDC per WETH");
        console.log("Curve (USDC/DAI):", curve.getPrice(), "DAI per USDC");
        console.log("Balancer (DAI/WETH):", balancer.getPrice(), "WETH per DAI");

        // ========== 部署 ChainedExecutor ==========
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        address owner = address(0xBEEF);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        // 给 Executor WETH
        uint256 initialWETH = 1 ether;
        weth.mint(address(executor), initialWETH);

        console.log("");
        console.log("=== Initial State ===");
        console.log("Executor WETH:", weth.balanceOf(address(executor)));

        // ========== 计算最优路径 ==========
        console.log("");
        console.log("=== Calculating Optimal Path ===");

        // 路径 1: ETH -> USDC -> DAI -> ETH
        uint256 path1_step1 = uniswap.getAmountOut(initialWETH, true); // WETH -> USDC
        uint256 path1_step2 = curve.getAmountOut(path1_step1, true);   // USDC -> DAI
        uint256 path1_step3 = balancer.getAmountOut(path1_step2, true); // DAI -> WETH

        console.log("Path 1: WETH -> USDC -> DAI -> WETH");
        console.log("  Step 1 (Uniswap): 1 WETH ->", path1_step1);
        console.log("  Step 2 (Curve): USDC ->", path1_step2);
        console.log("  Step 3 (Balancer): DAI ->", path1_step3);

        // 路径 2: ETH -> USDC -> WBTC -> ETH (对比)
        uint256 path2_step1 = uniswap.getAmountOut(initialWETH, true);    // WETH -> USDC
        uint256 path2_step2 = sushiswap.getAmountOut(path2_step1, true);  // USDC -> WBTC
        uint256 path2_step3 = pancakeswap.getAmountOut(path2_step2, true); // WBTC -> WETH

        console.log("");
        console.log("Path 2: WETH -> USDC -> WBTC -> WETH");
        console.log("  Step 1 (Uniswap): 1 WETH ->", path2_step1);
        console.log("  Step 2 (Sushiswap): USDC ->", path2_step2);
        console.log("  Step 3 (PancakeSwap): WBTC ->", path2_step3);

        // 选择更优路径
        bool usePath1 = path1_step3 > path2_step3;
        console.log("");
        console.log("Best path:", usePath1 ? "Path 1 (USDC->DAI)" : "Path 2 (USDC->WBTC)");

        // ========== 执行套利 (使用 Path 1) ==========
        console.log("");
        console.log("=== Executing Path 1 Arbitrage ===");

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](6);

        // Call 0: 转 WETH 到 Uniswap
        calls[0] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeWithSelector(MockToken.transfer.selector, address(uniswap), initialWETH),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: Uniswap swap WETH -> USDC
        calls[1] = IChainedExecutor.Call({
            target: address(uniswap),
            value: 0,
            callData: abi.encodeWithSelector(MockUniswapDEX.swap0For1.selector, initialWETH),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: 转 USDC 到 Curve
        calls[2] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockToken.transfer.selector, address(curve), path1_step1),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 3: Curve swap USDC -> DAI
        calls[3] = IChainedExecutor.Call({
            target: address(curve),
            value: 0,
            callData: abi.encodeWithSelector(MockUniswapDEX.swap0For1.selector, path1_step1),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 4: 转 DAI 到 Balancer
        calls[4] = IChainedExecutor.Call({
            target: address(dai),
            value: 0,
            callData: abi.encodeWithSelector(MockToken.transfer.selector, address(balancer), path1_step2),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 5: Balancer swap DAI -> WETH
        calls[5] = IChainedExecutor.Call({
            target: address(balancer),
            value: 0,
            callData: abi.encodeWithSelector(MockUniswapDEX.swap0For1.selector, path1_step2),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 执行
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 解析结果
        uint256 usdcReceived = abi.decode(results[1], (uint256));
        uint256 daiReceived = abi.decode(results[3], (uint256));
        uint256 wethReceived = abi.decode(results[5], (uint256));

        console.log("");
        console.log("=== Execution Results ===");
        console.log("Step 1: Got USDC:", usdcReceived);
        console.log("Step 2: Got DAI:", daiReceived);
        console.log("Step 3: Got WETH:", wethReceived);

        uint256 finalWETH = weth.balanceOf(address(executor));

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Initial WETH:", initialWETH);
        console.log("Final WETH:", finalWETH);

        if (finalWETH > initialWETH) {
            uint256 profit = finalWETH - initialWETH;
            uint256 profitBps = profit * 10000 / initialWETH;
            console.log("Profit (wei):", profit);
            console.log("Profit (bps):", profitBps);
            console.log("Profit (%):", profitBps / 100, ".", profitBps % 100);
        } else {
            console.log("No profit - check price inefficiency");
        }

        // ========== 展示 Path 2 对比 ==========
        console.log("");
        console.log("=== Path Comparison ===");
        console.log("Path 1 output:", path1_step3, "WETH");
        console.log("Path 2 output:", path2_step3, "WETH");
        console.log("Difference:", path1_step3 > path2_step3 ? path1_step3 - path2_step3 : path2_step3 - path1_step3, "WETH");

        console.log("");
        console.log("=== Key Insights ===");
        console.log("1. Multi-hop finds optimal routes across DEXes");
        console.log("2. Price differences create arbitrage opportunities");
        console.log("3. ChainedExecutor enables atomic multi-step trades");
        console.log("4. MEV bots scan for these opportunities in real-time");

        console.log("");
        console.log("========================================");
        console.log("  Multi-Hop Arbitrage Complete!");
        console.log("========================================");
    }
}
