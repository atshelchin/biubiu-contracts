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

/// @notice 模拟 DEX - ETH/USDC 交易对
/// @dev 1 ETH = 2000 USDC
contract MockDexETHUSDC {
    MockToken public usdc;
    uint256 public constant RATE = 2000; // 1 ETH = 2000 USDC

    constructor(MockToken _usdc) {
        usdc = _usdc;
    }

    /// @notice ETH -> USDC
    function swapETHForUSDC() external payable returns (uint256 usdcOut) {
        usdcOut = msg.value * RATE / 1e12; // 1e18 * 2000 / 1e12 = 2000e6
        usdc.transfer(msg.sender, usdcOut);
    }

    /// @notice USDC -> ETH (需要先转入 USDC)
    function swapUSDCForETH(uint256 usdcIn) external returns (uint256 ethOut) {
        require(usdc.balanceOf(address(this)) >= usdcIn, "USDC not received");
        ethOut = usdcIn * 1e12 / RATE;
        payable(msg.sender).transfer(ethOut);
    }

    receive() external payable {}
}

/// @notice 模拟 DEX - USDC/DAI 交易对
/// @dev 1 USDC = 1.02 DAI (USDC 溢价)
contract MockDexUSDCDAI {
    MockToken public usdc;
    MockToken public dai;
    uint256 public constant RATE = 102; // 1 USDC = 1.02 DAI (放大100倍)

    constructor(MockToken _usdc, MockToken _dai) {
        usdc = _usdc;
        dai = _dai;
    }

    /// @notice USDC -> DAI (需要先转入 USDC)
    function swapUSDCForDAI(uint256 usdcIn) external returns (uint256 daiOut) {
        require(usdc.balanceOf(address(this)) >= usdcIn, "USDC not received");
        // 1 USDC (1e6) = 1.02 DAI (1.02e18)
        daiOut = usdcIn * RATE * 1e12 / 100;
        dai.transfer(msg.sender, daiOut);
    }

    /// @notice DAI -> USDC (需要先转入 DAI)
    function swapDAIForUSDC(uint256 daiIn) external returns (uint256 usdcOut) {
        require(dai.balanceOf(address(this)) >= daiIn, "DAI not received");
        usdcOut = daiIn * 100 / RATE / 1e12;
        usdc.transfer(msg.sender, usdcOut);
    }
}

/// @notice 模拟 DEX - DAI/ETH 交易对
/// @dev 1 ETH = 1950 DAI (DAI 便宜买 ETH)
contract MockDexDAIETH {
    MockToken public dai;
    uint256 public constant RATE = 1950; // 1 ETH = 1950 DAI

    constructor(MockToken _dai) {
        dai = _dai;
    }

    /// @notice DAI -> ETH (需要先转入 DAI)
    function swapDAIForETH(uint256 daiIn) external returns (uint256 ethOut) {
        require(dai.balanceOf(address(this)) >= daiIn, "DAI not received");
        ethOut = daiIn * 1e18 / RATE / 1e18; // daiIn / 1950
        payable(msg.sender).transfer(ethOut);
    }

    /// @notice ETH -> DAI
    function swapETHForDAI() external payable returns (uint256 daiOut) {
        daiOut = msg.value * RATE / 1e18 * 1e18; // ethIn * 1950
        dai.transfer(msg.sender, daiOut);
    }

    receive() external payable {}
}

/// @title TriangularArbitrageDemo
/// @notice 演示三角套利: ETH -> USDC -> DAI -> ETH
/// @dev 套利路径:
///      1. 卖 1 ETH 得 2000 USDC (DEX1: ETH/USDC)
///      2. 卖 2000 USDC 得 2040 DAI (DEX2: USDC/DAI, 1 USDC = 1.02 DAI)
///      3. 卖 2040 DAI 得 1.046 ETH (DEX3: DAI/ETH, 1 ETH = 1950 DAI)
///      净利润: 0.046 ETH (~4.6%)
contract TriangularArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  Triangular Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Strategy: ETH -> USDC -> DAI -> ETH");
        console.log("DEX1: 1 ETH = 2000 USDC");
        console.log("DEX2: 1 USDC = 1.02 DAI");
        console.log("DEX3: 1 ETH = 1950 DAI");

        // 部署代币
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockToken dai = new MockToken("Dai Stablecoin", "DAI", 18);

        // 部署 DEX
        MockDexETHUSDC dex1 = new MockDexETHUSDC(usdc);
        MockDexUSDCDAI dex2 = new MockDexUSDCDAI(usdc, dai);
        MockDexDAIETH dex3 = new MockDexDAIETH(dai);

        // 给 DEX 充值流动性
        usdc.mint(address(dex1), 1_000_000e6); // DEX1 需要 USDC 卖给用户
        dai.mint(address(dex2), 1_000_000e18); // DEX2 需要 DAI 卖给用户
        vm.deal(address(dex3), 1000 ether); // DEX3 需要 ETH 卖给用户

        // 部署 ChainedExecutor
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        address owner = address(0xBEEF);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        // 给 Executor 初始 ETH
        uint256 initialETH = 1 ether;
        vm.deal(address(executor), initialETH);

        console.log("");
        console.log("Executor:", address(executor));
        console.log("Initial ETH:", initialETH);

        // 计算预期收益
        // Step 1: 1 ETH -> 2000 USDC
        uint256 expectedUSDC = initialETH * 2000 / 1e12; // 2000e6
        // Step 2: 2000 USDC -> 2040 DAI
        uint256 expectedDAI = expectedUSDC * 102 * 1e12 / 100; // 2040e18
        // Step 3: 2040 DAI -> 1.046 ETH
        uint256 expectedFinalETH = expectedDAI / 1950; // ~1.046e18

        console.log("");
        console.log("=== Expected Flow ===");
        console.log("Step 1: 1 ETH -> USDC:", expectedUSDC);
        console.log("Step 2: USDC -> DAI:", expectedDAI);
        console.log("Step 3: DAI -> ETH:", expectedFinalETH);

        uint256 expectedProfit = expectedFinalETH - initialETH;
        console.log("Expected profit (wei):", expectedProfit);

        // 构建三角套利调用链
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](5);

        // Call 0: DEX1 - ETH -> USDC
        calls[0] = IChainedExecutor.Call({
            target: address(dex1),
            value: initialETH,
            callData: abi.encodeWithSelector(MockDexETHUSDC.swapETHForUSDC.selector),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: 转 USDC 到 DEX2
        calls[1] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockToken.transfer.selector, address(dex2), expectedUSDC),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: DEX2 - USDC -> DAI
        calls[2] = IChainedExecutor.Call({
            target: address(dex2),
            value: 0,
            callData: abi.encodeWithSelector(MockDexUSDCDAI.swapUSDCForDAI.selector, expectedUSDC),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 3: 转 DAI 到 DEX3
        calls[3] = IChainedExecutor.Call({
            target: address(dai),
            value: 0,
            callData: abi.encodeWithSelector(MockToken.transfer.selector, address(dex3), expectedDAI),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 4: DEX3 - DAI -> ETH
        calls[4] = IChainedExecutor.Call({
            target: address(dex3),
            value: 0,
            callData: abi.encodeWithSelector(MockDexDAIETH.swapDAIForETH.selector, expectedDAI),
            injections: new IChainedExecutor.Injection[](0)
        });

        console.log("");
        console.log("=== Executing Triangular Arbitrage ===");

        // 执行
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 解析结果
        uint256 usdcReceived = abi.decode(results[0], (uint256));
        uint256 daiReceived = abi.decode(results[2], (uint256));
        uint256 ethReceived = abi.decode(results[4], (uint256));

        console.log("");
        console.log("=== Results ===");
        console.log("USDC from DEX1:", usdcReceived);
        console.log("DAI from DEX2:", daiReceived);
        console.log("ETH from DEX3:", ethReceived);

        uint256 finalETH = address(executor).balance;
        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Initial ETH:", initialETH);
        console.log("Final ETH:", finalETH);

        if (finalETH > initialETH) {
            uint256 profit = finalETH - initialETH;
            console.log("Profit (wei):", profit);
            uint256 profitPercent = profit * 10000 / initialETH;
            console.log("Profit (bps):", profitPercent);
        } else {
            console.log("No profit (check rates)");
        }

        console.log("");
        console.log("========================================");
        console.log("  Triangular Arbitrage Complete!");
        console.log("========================================");
    }
}
