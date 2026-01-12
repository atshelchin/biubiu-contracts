// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ChainedExecutor} from "../src/safe/ChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";

/// @notice 模拟 USDC 代币
contract MockUSDC {
    mapping(address => uint256) public balanceOf;

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

/// @notice 模拟闪电贷提供者 (类似 AAVE)
contract MockFlashLender {
    MockUSDC public usdc;
    uint256 public constant FEE_BPS = 9; // 0.09% 手续费

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    /// @notice 闪电贷入口
    /// @param amount 借款金额
    /// @param data 回调数据 (传给借款人)
    function flashLoan(address borrower, uint256 amount, bytes calldata data) external {
        uint256 balanceBefore = usdc.balanceOf(address(this));

        // 转账给借款人
        usdc.transfer(borrower, amount);

        // 调用借款人回调
        (bool success,) = borrower.call(data);
        require(success, "Callback failed");

        // 计算手续费
        uint256 fee = amount * FEE_BPS / 10000;
        uint256 amountOwed = amount + fee;

        // 验证还款
        uint256 balanceAfter = usdc.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");
    }
}

/// @notice 模拟 DEX A - ETH 便宜 (用 USDC 买 ETH)
contract MockDexA {
    MockUSDC public usdc;
    uint256 public constant RATE = 1800; // 1 ETH = 1800 USDC

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    /// @notice USDC -> ETH (假设 USDC 已经转入)
    function swapUSDCForETH(uint256 usdcIn) external returns (uint256 ethOut) {
        // 检查 DEX 收到的 USDC (简化: 假设已转入)
        require(usdc.balanceOf(address(this)) >= usdcIn, "USDC not received");

        // 计算 ETH 输出
        ethOut = usdcIn * 1e12 / RATE;
        payable(msg.sender).transfer(ethOut);
    }

    function getAmountOut(uint256 usdcIn) external pure returns (uint256) {
        return usdcIn * 1e12 / RATE;
    }

    receive() external payable {}
}

/// @notice 模拟 DEX B - ETH 贵 (卖 ETH 换 USDC)
contract MockDexB {
    MockUSDC public usdc;
    uint256 public constant RATE = 2000; // 1 ETH = 2000 USDC

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    /// @notice ETH -> USDC
    function swapETHForUSDC() external payable returns (uint256 usdcOut) {
        usdcOut = msg.value * RATE / 1e12;
        usdc.transfer(msg.sender, usdcOut);
    }

    function getAmountOut(uint256 ethIn) external pure returns (uint256) {
        return ethIn * RATE / 1e12;
    }
}

/// @title FlashLoanArbitrageDemo
/// @notice 演示使用闪电贷 + ChainedExecutor 进行无本金套利
/// @dev 流程:
///      1. 从 FlashLender 借 1800 USDC
///      2. 在 DEX A 用 1800 USDC 买 1 ETH (便宜)
///      3. 在 DEX B 卖 1 ETH 得 2000 USDC (贵)
///      4. 还款 1800 + 1.62 (0.09% 手续费) = 1801.62 USDC
///      5. 净利润: 2000 - 1801.62 = 198.38 USDC
contract FlashLoanArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  Flash Loan Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Strategy: Zero-capital arbitrage");
        console.log("1. Borrow 1800 USDC (flash loan)");
        console.log("2. Buy 1 ETH @ 1800 USDC (DEX A)");
        console.log("3. Sell 1 ETH @ 2000 USDC (DEX B)");
        console.log("4. Repay 1801.62 USDC (0.09% fee)");
        console.log("5. Profit: ~198 USDC");

        // 部署 Mock 合约
        MockUSDC usdc = new MockUSDC();
        MockFlashLender lender = new MockFlashLender(usdc);
        MockDexA dexA = new MockDexA(usdc);
        MockDexB dexB = new MockDexB(usdc);

        // 给 Lender 充值 USDC (可借出资金)
        usdc.mint(address(lender), 100_000e6);

        // 给 DEX A 充值 ETH (可卖给套利者)
        vm.deal(address(dexA), 100 ether);

        // 给 DEX B 充值 USDC (可买套利者的 ETH)
        usdc.mint(address(dexB), 100_000e6);

        // 部署 ChainedExecutor
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        uint256 ownerPk = 0xBEEF;
        address owner = vm.addr(ownerPk);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        console.log("");
        console.log("Executor:", address(executor));
        console.log("Owner:", owner);

        // 给 Executor USDC 授权给 DEX A (简化演示)
        // 实际场景需要在链式调用中包含 approve

        console.log("");
        console.log("=== Initial State ===");
        console.log("Executor USDC:", usdc.balanceOf(address(executor)));
        console.log("Executor ETH:", address(executor).balance);
        console.log("Lender USDC:", usdc.balanceOf(address(lender)));

        // 计算套利参数
        uint256 borrowAmount = 1800e6; // 借 1800 USDC
        uint256 fee = borrowAmount * 9 / 10000; // 0.09% = 1.62 USDC
        uint256 repayAmount = borrowAmount + fee;
        uint256 expectedETH = dexA.getAmountOut(borrowAmount);
        uint256 expectedUSDC = dexB.getAmountOut(expectedETH);

        console.log("");
        console.log("=== Arbitrage Parameters ===");
        console.log("Borrow:", borrowAmount);
        console.log("Fee (0.09%):", fee);
        console.log("Repay:", repayAmount);
        console.log("Expected ETH:", expectedETH);
        console.log("Expected USDC back:", expectedUSDC);
        console.log("Expected profit:", expectedUSDC - repayAmount);

        // 构建套利调用链
        // 这些调用会在闪电贷回调中执行
        IChainedExecutor.Call[] memory arbCalls = new IChainedExecutor.Call[](3);

        // Call 0: DEX A - USDC -> ETH
        // 注意: 需要先把 USDC 给 DEX A (通过 transfer)
        arbCalls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockUSDC.transfer.selector, address(dexA), borrowAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: DEX A swap - 已经有 USDC，直接换 ETH
        arbCalls[1] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeWithSelector(MockDexA.swapUSDCForETH.selector, borrowAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: DEX B - ETH -> USDC
        arbCalls[2] = IChainedExecutor.Call({
            target: address(dexB),
            value: expectedETH,
            callData: abi.encodeWithSelector(MockDexB.swapETHForUSDC.selector),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 构建闪电贷回调数据
        // 回调会执行 executeSigned，需要 owner 签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        // 构造完整的回调调用链 (包含套利 + 还款)
        IChainedExecutor.Call[] memory fullCalls = new IChainedExecutor.Call[](4);
        fullCalls[0] = arbCalls[0];
        fullCalls[1] = arbCalls[1];
        fullCalls[2] = arbCalls[2];

        // Call 3: 还款给 Lender
        fullCalls[3] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockUSDC.transfer.selector, address(lender), repayAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 签名
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, fullCalls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 构建闪电贷回调数据
        bytes memory callbackData = abi.encodeWithSelector(
            ChainedExecutor.executeSigned.selector, fullCalls, currentNonce, deadline, signature
        );

        console.log("");
        console.log("=== Executing Flash Loan Arbitrage ===");

        // 执行闪电贷
        lender.flashLoan(address(executor), borrowAmount, callbackData);

        console.log("");
        console.log("=== Results ===");
        uint256 finalBalance = usdc.balanceOf(address(executor));
        console.log("Executor final USDC:", finalBalance);
        console.log("Lender final USDC:", usdc.balanceOf(address(lender)));

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Started with: 0 USDC");
        console.log("Ended with:", finalBalance);
        console.log("Net profit:", finalBalance);

        console.log("");
        console.log("========================================");
        console.log("  Zero-capital arbitrage successful!");
        console.log("========================================");
    }
}
