// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ChainedExecutor} from "../src/safe/ChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";

/// @notice 模拟 DEX A - 价格偏低 (1 ETH = 1800 USDC)
contract MockDexA {
    uint256 public constant RATE = 1800; // USDC per ETH

    // ETH -> USDC: 1 ETH (1e18 wei) -> 1800 USDC (1800e6 wei)
    function swapETHForUSDC() external payable returns (uint256 usdcOut) {
        usdcOut = msg.value * RATE / 1e12; // 1e18 * 1800 / 1e12 = 1800e6
    }

    function getAmountOut(uint256 ethIn) external pure returns (uint256) {
        return ethIn * RATE / 1e12;
    }
}

/// @notice 模拟 DEX B - 价格偏高 (1 ETH = 2000 USDC)
/// @dev 正确套利方向：在 B 低价买 ETH，在 A 高价卖
contract MockDexB {
    uint256 public constant RATE = 2000; // USDC per ETH

    mapping(address => uint256) public usdcBalance;

    function depositUSDC(address user, uint256 amount) external {
        usdcBalance[user] = amount;
    }

    // USDC -> ETH: 1800 USDC (1800e6) -> 0.9 ETH (0.9e18 wei)
    function swapUSDCForETH(uint256 usdcIn) external returns (uint256 ethOut) {
        require(usdcBalance[msg.sender] >= usdcIn, "Insufficient USDC");
        usdcBalance[msg.sender] -= usdcIn;
        ethOut = usdcIn * 1e12 / RATE; // 1800e6 * 1e12 / 2000 = 0.9e18
        payable(msg.sender).transfer(ethOut);
    }

    function getAmountOut(uint256 usdcIn) external pure returns (uint256) {
        return usdcIn * 1e12 / RATE;
    }

    receive() external payable {}
}

/// @notice 模拟 DEX C - 低价 ETH (可用 USDC 买 ETH)
contract MockDexC {
    uint256 public constant RATE = 1800; // 1 ETH = 1800 USDC (便宜)

    mapping(address => uint256) public usdcBalance;

    function depositUSDC(address user, uint256 amount) external {
        usdcBalance[user] = amount;
    }

    // USDC -> ETH: 2000 USDC -> 1.111 ETH
    function swapUSDCForETH(uint256 usdcIn) external returns (uint256 ethOut) {
        require(usdcBalance[msg.sender] >= usdcIn, "Insufficient USDC");
        usdcBalance[msg.sender] -= usdcIn;
        ethOut = usdcIn * 1e12 / RATE; // 便宜买 ETH
        payable(msg.sender).transfer(ethOut);
    }

    function getAmountOut(uint256 usdcIn) external pure returns (uint256) {
        return usdcIn * 1e12 / RATE;
    }

    receive() external payable {}
}

/// @notice 模拟 DEX D - 高价 ETH (可卖 ETH 换 USDC)
contract MockDexD {
    uint256 public constant RATE = 2000; // 1 ETH = 2000 USDC (贵)

    // ETH -> USDC
    function swapETHForUSDC() external payable returns (uint256 usdcOut) {
        usdcOut = msg.value * RATE / 1e12;
    }

    function getAmountOut(uint256 ethIn) external pure returns (uint256) {
        return ethIn * RATE / 1e12;
    }
}

/// @title ArbitrageDemo
/// @notice 演示 ChainedExecutor 的套利场景
contract ArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("   ChainedExecutor Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Scenario: Profitable ETH arbitrage");
        console.log("DEX C: Buy 1 ETH for 1800 USDC (cheap)");
        console.log("DEX D: Sell 1 ETH for 2000 USDC (expensive)");

        // 部署 Mock DEX
        MockDexC dexC = new MockDexC(); // 便宜买 ETH
        MockDexD dexD = new MockDexD(); // 贵卖 ETH

        // 给 DEX C 充值 ETH (用于卖给用户)
        vm.deal(address(dexC), 100 ether);

        // 部署 ChainedExecutor
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        address owner = address(0xBEEF);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        console.log("");
        console.log("Executor:", address(executor));

        // 给 Executor 初始 USDC (通过 deposit 模拟)
        uint256 initialUSDC = 1800e6; // 1800 USDC
        dexC.depositUSDC(address(executor), initialUSDC);

        console.log("");
        console.log("=== Initial State ===");
        console.log("Executor USDC: 1800 (6 decimals)");
        console.log("Executor ETH: 0");

        // 计算预期收益
        uint256 expectedETH = dexC.getAmountOut(initialUSDC);
        uint256 expectedUSDCBack = dexD.getAmountOut(expectedETH);

        console.log("");
        console.log("=== Expected Arbitrage Flow ===");
        console.log("Step 1: 1800 USDC -> 1 ETH (DEX C)");
        console.log("Step 2: 1 ETH -> 2000 USDC (DEX D)");
        console.log("Expected profit: 200 USDC (11.1%)");

        // 构建链式调用
        console.log("");
        console.log("=== Executing Arbitrage ===");

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // Call 0: DEX C - USDC -> ETH (便宜买入 ETH)
        calls[0] = IChainedExecutor.Call({
            target: address(dexC),
            value: 0,
            callData: abi.encodeWithSelector(MockDexC.swapUSDCForETH.selector, initialUSDC),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: DEX D - ETH -> USDC (高价卖出 ETH)
        // 注入 Call 0 的返回值 (ETH 数量) 到 value 字段
        // 注意: 这里需要发送 ETH，所以要注入到 value
        // 但 Injection 只能修改 callData，不能修改 value
        // 所以需要换一种方式: 先获取 ETH，然后用固定值调用
        IChainedExecutor.Injection[] memory inj1 = new IChainedExecutor.Injection[](1);
        inj1[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4 // 注入到 calldata 参数位置
        });

        // 由于 swapETHForUSDC 需要 msg.value，我们需要另一种方式
        // 使用 execute 单次调用来发送 ETH
        calls[1] = IChainedExecutor.Call({
            target: address(dexD),
            value: expectedETH, // 使用预期值（实际场景应该用注入）
            callData: abi.encodeWithSelector(MockDexD.swapETHForUSDC.selector),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 执行链式调用
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        console.log("");
        console.log("=== Results ===");
        uint256 ethFromC = abi.decode(results[0], (uint256));
        uint256 usdcFromD = abi.decode(results[1], (uint256));
        console.log("ETH from DEX C (wei):", ethFromC);
        console.log("USDC from DEX D (wei):", usdcFromD);

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Initial USDC:", initialUSDC);
        console.log("Final USDC:", usdcFromD);
        uint256 profit = usdcFromD - initialUSDC;
        console.log("Profit USDC:", profit);

        console.log("");
        console.log("========================================");
        console.log("  Arbitrage successful! +200 USDC");
        console.log("========================================");
    }
}
