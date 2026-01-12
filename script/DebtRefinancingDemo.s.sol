// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ChainedExecutor} from "../src/safe/ChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";

/// @notice 模拟 ERC20 代币
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice 模拟借贷协议 A - 保守参数
/// @dev 抵押率 75%, 即 $1000 ETH 最多借 $750 USDC
contract MockLendingProtocolA {
    MockERC20 public weth;
    MockERC20 public usdc;

    uint256 public ethPrice = 2000e6; // 1 ETH = 2000 USDC
    uint256 public constant COLLATERAL_FACTOR = 75; // 75% 抵押率

    struct Position {
        uint256 collateral; // WETH 抵押
        uint256 debt;       // USDC 债务
    }

    mapping(address => Position) public positions;

    constructor(MockERC20 _weth, MockERC20 _usdc) {
        weth = _weth;
        usdc = _usdc;
    }

    /// @notice 存入 WETH 抵押品
    function deposit(uint256 amount) external {
        weth.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].collateral += amount;
    }

    /// @notice 借款 USDC
    function borrow(uint256 amount) external returns (uint256) {
        Position storage pos = positions[msg.sender];
        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        uint256 maxBorrow = collateralValue * COLLATERAL_FACTOR / 100;
        require(pos.debt + amount <= maxBorrow, "Exceeds borrow limit");

        pos.debt += amount;
        usdc.transfer(msg.sender, amount);
        return amount;
    }

    /// @notice 还款 USDC
    /// @return collateralReleased 释放的抵押品数量
    function repay(uint256 amount) external returns (uint256 collateralReleased) {
        Position storage pos = positions[msg.sender];
        require(pos.debt >= amount, "Repay exceeds debt");

        usdc.transferFrom(msg.sender, address(this), amount);
        pos.debt -= amount;

        // 如果全部还清，释放所有抵押品
        if (pos.debt == 0) {
            collateralReleased = pos.collateral;
            pos.collateral = 0;
            weth.transfer(msg.sender, collateralReleased);
        }
    }

    /// @notice 获取最大可借额度
    function getMaxBorrow(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        return collateralValue * COLLATERAL_FACTOR / 100;
    }

    /// @notice 获取仓位信息
    function getPosition(address user) external view returns (uint256 collateral, uint256 debt) {
        Position storage pos = positions[user];
        return (pos.collateral, pos.debt);
    }
}

/// @notice 模拟借贷协议 B - 激进参数
/// @dev 抵押率 85%, 即 $1000 ETH 最多借 $850 USDC
contract MockLendingProtocolB {
    MockERC20 public weth;
    MockERC20 public usdc;

    uint256 public ethPrice = 2000e6; // 1 ETH = 2000 USDC
    uint256 public constant COLLATERAL_FACTOR = 85; // 85% 抵押率 (更高!)

    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    mapping(address => Position) public positions;

    constructor(MockERC20 _weth, MockERC20 _usdc) {
        weth = _weth;
        usdc = _usdc;
    }

    /// @notice 存入 WETH 抵押品
    function deposit(uint256 amount) external {
        weth.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].collateral += amount;
    }

    /// @notice 借款 USDC
    function borrow(uint256 amount) external returns (uint256) {
        Position storage pos = positions[msg.sender];
        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        uint256 maxBorrow = collateralValue * COLLATERAL_FACTOR / 100;
        require(pos.debt + amount <= maxBorrow, "Exceeds borrow limit");

        pos.debt += amount;
        usdc.transfer(msg.sender, amount);
        return amount;
    }

    /// @notice 还款
    function repay(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        require(pos.debt >= amount, "Repay exceeds debt");

        usdc.transferFrom(msg.sender, address(this), amount);
        pos.debt -= amount;
    }

    /// @notice 获取最大可借额度
    function getMaxBorrow(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        uint256 collateralValue = pos.collateral * ethPrice / 1e18;
        return collateralValue * COLLATERAL_FACTOR / 100;
    }

    /// @notice 获取仓位信息
    function getPosition(address user) external view returns (uint256 collateral, uint256 debt) {
        Position storage pos = positions[user];
        return (pos.collateral, pos.debt);
    }
}

/// @notice 模拟闪电贷
contract MockFlashLender {
    MockERC20 public usdc;
    uint256 public constant FEE_BPS = 9; // 0.09%

    constructor(MockERC20 _usdc) {
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

/// @title DebtRefinancingDemo
/// @notice 演示债务重组套利 (利用协议间抵押率差异)
/// @dev 场景:
///      - 协议 A: 抵押率 75% (保守)
///      - 协议 B: 抵押率 85% (激进)
///
///      用户在协议 A 有仓位: 1 ETH 抵押, 1500 USDC 债务
///      (已用满 75% 额度: 2000 * 0.75 = 1500)
///
///      套利流程:
///      1. 闪电贷借 1500 USDC
///      2. 在协议 A 还清债务 → 取回 1 ETH (Injection: 动态获取释放的 ETH)
///      3. 在协议 B 存入 1 ETH
///      4. 在协议 B 借出 1700 USDC (85% 额度)
///      5. 还闪电贷 1500 + 手续费
///      6. 净赚差额 (~200 USDC)
///
///      用户获益: 仓位迁移到更高效的协议
///      套利者获益: 收取服务费 (从额外借款中扣除)
contract DebtRefinancingDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  Debt Refinancing Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Strategy: Migrate debt to higher LTV protocol");
        console.log("");
        console.log("Protocol A: 75% LTV (conservative)");
        console.log("Protocol B: 85% LTV (aggressive)");
        console.log("");
        console.log("Key: Exploit collateral efficiency difference!");

        // ========== 部署代币 ==========
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // ========== 部署协议 ==========
        MockLendingProtocolA protocolA = new MockLendingProtocolA(weth, usdc);
        MockLendingProtocolB protocolB = new MockLendingProtocolB(weth, usdc);
        MockFlashLender flashLender = new MockFlashLender(usdc);

        // 给协议充值流动性
        usdc.mint(address(protocolA), 10_000_000e6);
        usdc.mint(address(protocolB), 10_000_000e6);
        usdc.mint(address(flashLender), 10_000_000e6);

        // ========== 设置用户仓位 (在协议 A) ==========
        address user = address(0xCAFE);

        // 用户存入 1 ETH，借满 75% = 1500 USDC
        weth.mint(user, 1 ether);
        vm.startPrank(user);
        weth.approve(address(protocolA), 1 ether);
        protocolA.deposit(1 ether);
        protocolA.borrow(1500e6); // 借满额度
        vm.stopPrank();

        console.log("");
        console.log("=== User Position in Protocol A ===");
        (uint256 collateralA, uint256 debtA) = protocolA.getPosition(user);
        console.log("Collateral (WETH):", collateralA);
        console.log("Debt (USDC):", debtA);
        console.log("Max borrow:", protocolA.getMaxBorrow(user));
        console.log("Utilization: 100% (maxed out)");

        // 计算如果在协议 B，能借多少
        uint256 potentialBorrowB = 1 ether * 2000e6 / 1e18 * 85 / 100;
        console.log("");
        console.log("=== Potential in Protocol B ===");
        console.log("Same 1 ETH collateral");
        console.log("Max borrow at 85% LTV:", potentialBorrowB);
        console.log("Extra capacity:", potentialBorrowB - debtA);

        // ========== 部署套利执行器 ==========
        address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        uint256 ownerPk = 0xBEEF;
        address owner = vm.addr(ownerPk);

        ChainedExecutorFactory factory = new ChainedExecutorFactory(entryPoint);
        ChainedExecutor executor = ChainedExecutor(payable(factory.createAccount(owner, 0)));

        console.log("");
        console.log("=== Arbitrageur ===");
        console.log("Executor:", address(executor));
        console.log("Initial USDC:", usdc.balanceOf(address(executor)));

        // ========== 用户授权套利者操作其仓位 ==========
        // 在真实场景中，这可以通过签名授权或代理模式实现
        // 这里简化：直接将用户仓位"转移"给执行器
        // 实际实现可能需要协议支持 transferPosition 或使用 permit

        // 简化演示：我们让执行器成为仓位持有者
        // 重新设置：执行器持有仓位
        vm.startPrank(user);
        // 用户把 USDC 还给协议，取回 ETH，再给执行器
        // 简化：直接给执行器设置仓位
        vm.stopPrank();

        // 重置：让执行器拥有仓位
        weth.mint(address(executor), 1 ether);
        vm.startPrank(address(executor));
        weth.approve(address(protocolA), 1 ether);
        vm.stopPrank();

        // 模拟执行器在协议A有仓位
        vm.prank(address(executor));
        protocolA.deposit(1 ether);
        vm.prank(address(executor));
        protocolA.borrow(1500e6);

        // 把借出的 USDC 暂存（模拟用户已使用）
        vm.prank(address(executor));
        usdc.transfer(user, 1500e6);

        console.log("");
        console.log("=== Executor Position in Protocol A ===");
        (collateralA, debtA) = protocolA.getPosition(address(executor));
        console.log("Collateral (WETH):", collateralA);
        console.log("Debt (USDC):", debtA);

        // ========== 计算套利参数 ==========
        uint256 debtToRepay = debtA;
        uint256 flashLoanFee = debtToRepay * 9 / 10000;

        // 在协议 B 能借出的额度
        uint256 newBorrowAmount = potentialBorrowB;

        // 预期利润 = 新借款 - 旧债务 - 闪电贷手续费
        uint256 expectedProfit = newBorrowAmount - debtToRepay - flashLoanFee;

        console.log("");
        console.log("=== Refinancing Parameters ===");
        console.log("Debt to repay (Protocol A):", debtToRepay);
        console.log("Flash loan fee:", flashLoanFee);
        console.log("New borrow (Protocol B):", newBorrowAmount);
        console.log("Expected profit:", expectedProfit);

        // ========== 构建调用链 (使用 Injection!) ==========
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](6);

        // Call 0: 授权协议 A 使用 USDC (还款)
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.approve.selector, address(protocolA), debtToRepay),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: 在协议 A 还款 → 返回释放的 WETH 数量!
        calls[1] = IChainedExecutor.Call({
            target: address(protocolA),
            value: 0,
            callData: abi.encodeWithSelector(MockLendingProtocolA.repay.selector, debtToRepay),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: 授权协议 B 使用 WETH
        // 使用 Injection 注入 Call 1 返回的 collateralReleased!
        IChainedExecutor.Injection[] memory injectionsForApproveWETH = new IChainedExecutor.Injection[](1);
        injectionsForApproveWETH[0] = IChainedExecutor.Injection({
            sourceCallIndex: 1,       // 从 Call 1 (repay) 取返回值
            sourceReturnOffset: 0,    // collateralReleased
            sourceReturnLength: 32,
            targetCalldataOffset: 36  // approve(address,uint256) 的 amount 位置
        });

        calls[2] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.approve.selector, address(protocolB), uint256(0)), // 占位
            injections: injectionsForApproveWETH
        });

        // Call 3: 在协议 B 存入 WETH
        // 使用 Injection 注入动态的 WETH 数量!
        IChainedExecutor.Injection[] memory injectionsForDeposit = new IChainedExecutor.Injection[](1);
        injectionsForDeposit[0] = IChainedExecutor.Injection({
            sourceCallIndex: 1,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4   // deposit(uint256) 的参数位置
        });

        calls[3] = IChainedExecutor.Call({
            target: address(protocolB),
            value: 0,
            callData: abi.encodeWithSelector(MockLendingProtocolB.deposit.selector, uint256(0)), // 占位
            injections: injectionsForDeposit
        });

        // Call 4: 在协议 B 借款
        calls[4] = IChainedExecutor.Call({
            target: address(protocolB),
            value: 0,
            callData: abi.encodeWithSelector(MockLendingProtocolB.borrow.selector, newBorrowAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 5: 还闪电贷
        uint256 repayAmount = debtToRepay + flashLoanFee;
        calls[5] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.transfer.selector, address(flashLender), repayAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // ========== 构建签名 ==========
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

        // ========== 执行债务重组 ==========
        console.log("");
        console.log("=== Executing Debt Refinancing ===");
        console.log("Key: Injection handles dynamic collateral release!");

        flashLender.flashLoan(address(executor), debtToRepay, callbackData);

        // ========== 结果分析 ==========
        uint256 finalUSDC = usdc.balanceOf(address(executor));
        uint256 finalWETH = weth.balanceOf(address(executor));

        console.log("");
        console.log("=== Results ===");
        console.log("Final USDC:", finalUSDC);
        console.log("Final WETH:", finalWETH);

        console.log("");
        console.log("=== Position After Refinancing ===");

        (uint256 collateralAAfter, uint256 debtAAfter) = protocolA.getPosition(address(executor));
        console.log("Protocol A - Collateral:", collateralAAfter);
        console.log("Protocol A - Debt:", debtAAfter);

        (uint256 collateralBAfter, uint256 debtBAfter) = protocolB.getPosition(address(executor));
        console.log("Protocol B - Collateral:", collateralBAfter);
        console.log("Protocol B - Debt:", debtBAfter);

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Started with: 0 USDC");
        console.log("Ended with:", finalUSDC, "USDC");
        console.log("Net profit:", finalUSDC, "USDC");

        if (finalUSDC > 0) {
            uint256 profitBps = finalUSDC * 10000 / debtToRepay;
            console.log("ROI (on debt):", profitBps, "bps");
        }

        console.log("");
        console.log("=== Injection Demonstration ===");
        console.log("1. repay() returned dynamic collateralReleased");
        console.log("2. Injection injected amount into approve(WETH)");
        console.log("3. Injection injected amount into deposit()");
        console.log("4. Two injections - dynamic collateral handling!");

        console.log("");
        console.log("=== Why This Works ===");
        console.log("1. Protocol B has higher LTV (85% vs 75%)");
        console.log("2. Same collateral can borrow more");
        console.log("3. Flash loan enables atomic migration");
        console.log("4. Profit = extra borrowing capacity");

        console.log("");
        console.log("=== Real World Applications ===");
        console.log("- Aave -> Compound migration");
        console.log("- Cross-chain debt refinancing");
        console.log("- Protocol upgrade migrations");
        console.log("- Interest rate arbitrage (over time)");

        console.log("");
        console.log("========================================");
        console.log("  Debt Refinancing Complete!");
        console.log("========================================");
    }
}
