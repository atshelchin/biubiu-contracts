// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ChainedExecutor} from "../src/safe/ChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";

/// @notice 模拟 USDC 代币
contract MockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice 模拟借贷协议 (类似 Aave/Compound)
/// @dev 支持 ETH 抵押借 USDC，可被清算
contract MockLendingProtocol {
    MockUSDC public usdc;

    uint256 public ethPrice = 2000e6; // 1 ETH = 2000 USDC (初始价格)
    uint256 public constant COLLATERAL_RATIO = 150; // 150% 抵押率
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120% 触发清算
    uint256 public constant LIQUIDATION_BONUS = 5; // 5% 清算奖励

    struct Position {
        uint256 collateral; // ETH 抵押
        uint256 debt; // USDC 债务
    }

    mapping(address => Position) public positions;

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    /// @notice 存入 ETH 抵押品
    function depositCollateral() external payable {
        positions[msg.sender].collateral += msg.value;
    }

    /// @notice 借款 USDC
    function borrow(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        uint256 maxBorrow = collateralValue * 100 / COLLATERAL_RATIO;
        require(pos.debt + amount <= maxBorrow, "Exceeds borrow limit");

        pos.debt += amount;
        usdc.transfer(msg.sender, amount);
    }

    /// @notice 还款
    function repay(uint256 amount) external {
        require(positions[msg.sender].debt >= amount, "Repay exceeds debt");
        usdc.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].debt -= amount;
    }

    /// @notice 更新 ETH 价格 (模拟预言机)
    function setEthPrice(uint256 newPrice) external {
        ethPrice = newPrice;
    }

    /// @notice 检查仓位是否可被清算
    function isLiquidatable(address user) public view returns (bool) {
        Position storage pos = positions[user];
        if (pos.debt == 0) return false;

        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        uint256 healthFactor = collateralValue * 100 / pos.debt;
        return healthFactor < LIQUIDATION_THRESHOLD;
    }

    /// @notice 获取仓位健康度
    function getHealthFactor(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debt == 0) return type(uint256).max;

        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        return collateralValue * 100 / pos.debt;
    }

    /// @notice 清算不健康仓位
    /// @param user 被清算用户
    /// @param debtToCover 要清算的债务金额
    /// @return collateralReceived 获得的抵押品 (含清算奖励)
    function liquidate(address user, uint256 debtToCover) external returns (uint256 collateralReceived) {
        require(isLiquidatable(user), "Position is healthy");

        Position storage pos = positions[user];
        require(debtToCover <= pos.debt, "Exceeds debt");

        // 转入 USDC 还债
        usdc.transferFrom(msg.sender, address(this), debtToCover);

        // 计算应得抵押品 (债务价值 + 5% 奖励)
        uint256 debtValueInETH = debtToCover * 1e18 / ethPrice;
        collateralReceived = debtValueInETH * (100 + LIQUIDATION_BONUS) / 100;

        // 确保不超过用户抵押品
        if (collateralReceived > pos.collateral) {
            collateralReceived = pos.collateral;
        }

        // 更新仓位
        pos.debt -= debtToCover;
        pos.collateral -= collateralReceived;

        // 转出 ETH 给清算人
        payable(msg.sender).transfer(collateralReceived);
    }

    receive() external payable {}
}

/// @notice 模拟 DEX - ETH/USDC 交易对
contract MockDex {
    MockUSDC public usdc;
    uint256 public rate; // USDC per ETH

    constructor(MockUSDC _usdc, uint256 _rate) {
        usdc = _usdc;
        rate = _rate;
    }

    /// @notice ETH -> USDC
    function swapETHForUSDC() external payable returns (uint256 usdcOut) {
        usdcOut = msg.value * rate / 1e18;
        usdc.transfer(msg.sender, usdcOut);
    }

    receive() external payable {}
}

/// @notice 模拟闪电贷
contract MockFlashLender {
    MockUSDC public usdc;
    uint256 public constant FEE_BPS = 9; // 0.09%

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    function flashLoan(address borrower, uint256 amount, bytes calldata data) external {
        uint256 balanceBefore = usdc.balanceOf(address(this));
        usdc.transfer(borrower, amount);

        (bool success,) = borrower.call(data);
        require(success, "Callback failed");

        uint256 fee = amount * FEE_BPS / 10000;
        uint256 balanceAfter = usdc.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");
    }
}

/// @title LiquidationArbitrageDemo
/// @notice 演示清算套利 (单区块零本金套利)
/// @dev 流程:
///      1. 闪电贷借 USDC
///      2. 清算不健康仓位，获得折扣 ETH (债务 + 5% 奖励)
///      3. 在 DEX 卖出 ETH 换回 USDC
///      4. 还闪电贷
///      5. 净赚清算奖励
contract LiquidationArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  Liquidation Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Strategy: Flash Loan Liquidation");
        console.log("1. Flash loan USDC");
        console.log("2. Liquidate unhealthy position");
        console.log("3. Get ETH at 5% discount");
        console.log("4. Sell ETH on DEX");
        console.log("5. Repay flash loan, keep profit");

        // 部署代币和协议
        MockUSDC usdc = new MockUSDC();
        MockLendingProtocol lending = new MockLendingProtocol(usdc);
        MockDex dex = new MockDex(usdc, 1600e6); // DEX 价格 1600 USDC/ETH
        MockFlashLender flashLender = new MockFlashLender(usdc);

        // 给协议充值流动性
        usdc.mint(address(lending), 10_000_000e6);
        usdc.mint(address(dex), 10_000_000e6);
        usdc.mint(address(flashLender), 10_000_000e6);

        // ========== 设置被清算用户 ==========
        address victim = address(0xDEAD);

        // 受害者存入 1 ETH，借出 1200 USDC (健康度 166%)
        vm.deal(victim, 1 ether);
        vm.startPrank(victim);
        lending.depositCollateral{value: 1 ether}();
        lending.borrow(1200e6); // 借 1200 USDC
        vm.stopPrank();

        console.log("");
        console.log("=== Victim Position (Before Price Drop) ===");
        console.log("Collateral: 1 ETH");
        console.log("Debt: 1200 USDC");
        console.log("ETH Price: 2000 USDC");
        console.log("Health Factor:", lending.getHealthFactor(victim));
        console.log("Liquidatable:", lending.isLiquidatable(victim));

        // ========== 价格下跌，触发清算 ==========
        // ETH 价格从 2000 跌到 1400 USDC
        // 健康度: 1400 / 1200 = 116% < 120%
        lending.setEthPrice(1400e6);

        console.log("");
        console.log("=== After Price Drop (ETH: 2000 -> 1400) ===");
        console.log("Health Factor:", lending.getHealthFactor(victim));
        console.log("Liquidatable:", lending.isLiquidatable(victim));

        // ========== 部署清算机器人 ==========
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        uint256 ownerPk = 0xBEEF;
        address owner = vm.addr(ownerPk);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        console.log("");
        console.log("Liquidator:", address(executor));
        console.log("Initial USDC:", usdc.balanceOf(address(executor)));
        console.log("Initial ETH:", address(executor).balance);

        // ========== 计算套利参数 ==========
        uint256 debtToCover = 1200e6; // 清算全部债务
        uint256 flashLoanFee = debtToCover * 9 / 10000;

        // 清算获得的 ETH: 债务价值 + 5% 奖励
        // 1200 USDC / 1400 USDC/ETH * 1.05 = 0.9 ETH
        uint256 expectedETH = debtToCover * 1e18 / 1400e6 * 105 / 100;

        // 卖出 ETH 获得的 USDC (DEX 价格 1600)
        uint256 expectedUSDCFromDex = expectedETH * 1600e6 / 1e18;

        console.log("");
        console.log("=== Arbitrage Parameters ===");
        console.log("Debt to cover:", debtToCover);
        console.log("Flash loan fee:", flashLoanFee);
        console.log("Expected ETH (w/ 5% bonus):", expectedETH);
        console.log("Expected USDC from DEX:", expectedUSDCFromDex);
        console.log("Expected profit:", expectedUSDCFromDex - debtToCover - flashLoanFee);

        // ========== 构建清算调用链 ==========
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](4);

        // Call 0: 授权借贷协议使用 USDC
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockUSDC.approve.selector, address(lending), debtToCover),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: 清算受害者仓位
        calls[1] = IChainedExecutor.Call({
            target: address(lending),
            value: 0,
            callData: abi.encodeWithSelector(MockLendingProtocol.liquidate.selector, victim, debtToCover),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: 在 DEX 卖出 ETH 换 USDC
        calls[2] = IChainedExecutor.Call({
            target: address(dex),
            value: expectedETH,
            callData: abi.encodeWithSelector(MockDex.swapETHForUSDC.selector),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 3: 还款给闪电贷 (本金 + 手续费)
        uint256 repayAmount = debtToCover + flashLoanFee;
        calls[3] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockUSDC.transfer.selector, address(flashLender), repayAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 构建签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 闪电贷回调数据
        bytes memory callbackData = abi.encodeWithSelector(
            ChainedExecutor.executeSigned.selector, calls, currentNonce, deadline, signature
        );

        // ========== 执行清算套利 ==========
        console.log("");
        console.log("=== Executing Liquidation Arbitrage ===");

        flashLender.flashLoan(address(executor), debtToCover, callbackData);

        // ========== 结果分析 ==========
        console.log("");
        console.log("=== Results ===");
        uint256 finalUSDC = usdc.balanceOf(address(executor));
        uint256 finalETH = address(executor).balance;

        console.log("Final USDC:", finalUSDC);
        console.log("Final ETH:", finalETH);

        console.log("");
        console.log("=== Victim Position After Liquidation ===");
        (uint256 remainingCollateral, uint256 remainingDebt) = lending.positions(victim);
        console.log("Remaining collateral:", remainingCollateral);
        console.log("Remaining debt:", remainingDebt);

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Started with: 0 USDC");
        console.log("Ended with:", finalUSDC, "USDC");
        console.log("Zero-capital profit:", finalUSDC);

        console.log("");
        console.log("========================================");
        console.log("  Liquidation Arbitrage Successful!");
        console.log("========================================");
    }
}
