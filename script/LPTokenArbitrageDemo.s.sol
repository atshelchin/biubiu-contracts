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

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
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

/// @notice 模拟 Uniswap V2 风格的 LP Token
contract MockLPToken is MockERC20 {
    constructor() MockERC20("Uniswap V2 ETH-USDC LP", "UNI-V2", 18) {}
}

/// @notice 模拟 Uniswap V2 风格的流动性池
/// @dev 支持添加/移除流动性
contract MockLPPool {
    MockERC20 public token0; // WETH
    MockERC20 public token1; // USDC
    MockLPToken public lpToken;

    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public totalLPSupply;

    constructor(MockERC20 _token0, MockERC20 _token1, MockLPToken _lpToken) {
        token0 = _token0;
        token1 = _token1;
        lpToken = _lpToken;
    }

    /// @notice 初始化流动性
    function initLiquidity(uint256 amount0, uint256 amount1) external {
        reserve0 = amount0;
        reserve1 = amount1;
        // 初始 LP = sqrt(amount0 * amount1)
        totalLPSupply = sqrt(amount0 * amount1);
        lpToken.mint(msg.sender, totalLPSupply);
    }

    /// @notice 移除流动性
    /// @param lpAmount 要销毁的 LP Token 数量
    /// @return amount0 返回的 token0 数量
    /// @return amount1 返回的 token1 数量
    function removeLiquidity(uint256 lpAmount) external returns (uint256 amount0, uint256 amount1) {
        require(lpToken.balanceOf(msg.sender) >= lpAmount, "Insufficient LP");

        // 按比例计算返还金额
        amount0 = lpAmount * reserve0 / totalLPSupply;
        amount1 = lpAmount * reserve1 / totalLPSupply;

        // 销毁 LP Token
        lpToken.burn(msg.sender, lpAmount);
        totalLPSupply -= lpAmount;

        // 更新储备
        reserve0 -= amount0;
        reserve1 -= amount1;

        // 转出代币
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    /// @notice 获取 LP Token 的底层资产价值
    /// @param lpAmount LP Token 数量
    /// @return value0 对应的 token0 价值
    /// @return value1 对应的 token1 价值
    function getUnderlyingValue(uint256 lpAmount) external view returns (uint256 value0, uint256 value1) {
        value0 = lpAmount * reserve0 / totalLPSupply;
        value1 = lpAmount * reserve1 / totalLPSupply;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

/// @notice 模拟二级市场 - LP Token 交易
/// @dev LP Token 在这里被低估交易
contract MockLPSecondaryMarket {
    MockLPToken public lpToken;
    MockERC20 public usdc;

    uint256 public lpPriceInUSDC; // LP Token 的市场价格 (per LP in USDC)

    constructor(MockLPToken _lpToken, MockERC20 _usdc, uint256 _price) {
        lpToken = _lpToken;
        usdc = _usdc;
        lpPriceInUSDC = _price;
    }

    /// @notice 用 USDC 购买 LP Token
    /// @param usdcAmount 花费的 USDC
    /// @return lpAmount 获得的 LP Token
    function buyLP(uint256 usdcAmount) external returns (uint256 lpAmount) {
        usdc.transferFrom(msg.sender, address(this), usdcAmount);
        lpAmount = usdcAmount * 1e18 / lpPriceInUSDC;
        lpToken.transfer(msg.sender, lpAmount);
    }

    /// @notice 获取能买到的 LP 数量
    function getLPAmountOut(uint256 usdcIn) external view returns (uint256) {
        return usdcIn * 1e18 / lpPriceInUSDC;
    }
}

/// @notice 模拟 DEX - WETH/USDC 交易
contract MockDEX {
    MockERC20 public weth;
    MockERC20 public usdc;
    uint256 public ethPriceInUSDC; // 1 ETH = X USDC

    constructor(MockERC20 _weth, MockERC20 _usdc, uint256 _price) {
        weth = _weth;
        usdc = _usdc;
        ethPriceInUSDC = _price;
    }

    /// @notice WETH -> USDC
    /// @param wethAmount 卖出的 WETH 数量
    /// @return usdcAmount 获得的 USDC 数量
    function swapWETHForUSDC(uint256 wethAmount) external returns (uint256 usdcAmount) {
        weth.transferFrom(msg.sender, address(this), wethAmount);
        usdcAmount = wethAmount * ethPriceInUSDC / 1e18;
        usdc.transfer(msg.sender, usdcAmount);
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

/// @title LPTokenArbitrageDemo
/// @notice 演示 LP Token 套利 (利用二级市场价差)
/// @dev 场景:
///      - LP Token 实际价值: 每个 LP 代表 0.5 ETH + 1000 USDC = 2000 USDC
///      - 二级市场价格: 1900 USDC (被低估 5%)
///
///      套利流程:
///      1. 闪电贷借 USDC
///      2. 在二级市场买入被低估的 LP Token
///      3. 移除流动性 → 获得 WETH + USDC (动态数量)
///      4. 卖 WETH 换 USDC (使用 Injection 注入动态数量!)
///      5. 还闪电贷
///      6. 净赚价差
///
///      ChainedExecutor 关键特性:
///      - Injection: 将 removeLiquidity 返回的 (amount0, amount1) 注入后续调用
///      - executeSigned: 支持闪电贷回调
contract LPTokenArbitrageDemo is Script {
    function run() external {
        console.log("========================================");
        console.log("  LP Token Arbitrage Demo");
        console.log("========================================");
        console.log("");
        console.log("Strategy: Buy underpriced LP -> Remove -> Sell");
        console.log("");
        console.log("Key Feature: Injection for dynamic amounts!");
        console.log("- removeLiquidity returns (amount0, amount1)");
        console.log("- Injection injects amount0 into swap call");

        // ========== 部署代币 ==========
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockLPToken lpToken = new MockLPToken();

        // ========== 部署协议 ==========
        MockLPPool lpPool = new MockLPPool(weth, usdc, lpToken);
        MockDEX dex = new MockDEX(weth, usdc, 2000e6); // 1 ETH = 2000 USDC
        MockFlashLender flashLender = new MockFlashLender(usdc);

        // 给 LP Pool 初始化流动性: 1000 ETH + 2,000,000 USDC
        weth.mint(address(lpPool), 1000 ether);
        usdc.mint(address(lpPool), 2_000_000e6);

        // 初始化为某个流动性提供者
        address lpProvider = address(0xCAFE);
        vm.prank(lpProvider);
        lpPool.initLiquidity(1000 ether, 2_000_000e6);

        uint256 totalLP = lpPool.totalLPSupply();
        console.log("");
        console.log("=== LP Pool State ===");
        console.log("Reserve WETH:", lpPool.reserve0());
        console.log("Reserve USDC:", lpPool.reserve1());
        console.log("Total LP Supply:", totalLP);

        // 计算每个 LP 的实际价值
        // LP Token 代表池子的一定比例
        // 假设 totalLP = sqrt(1000e18 * 2_000_000e6) ≈ 44.7e12
        // 每个 LP 代表 1000/44.7e12 ETH + 2_000_000/44.7e12 USDC
        uint256 lpAmount = totalLP / 10; // 用 10% 的 LP 做测试
        (uint256 ethPerLP, uint256 usdcPerLP) = lpPool.getUnderlyingValue(lpAmount);

        // 计算公允价值 (ETH 按 2000 USDC 计价)
        uint256 lpFairValueInUSDC = ethPerLP * 2000e6 / 1e18 + usdcPerLP;
        console.log("");
        console.log("For", lpAmount, "LP tokens:");
        console.log("  Underlying WETH:", ethPerLP);
        console.log("  Underlying USDC:", usdcPerLP);
        console.log("  Fair Value (USDC):", lpFairValueInUSDC);

        // ========== 二级市场 LP Token 被低估 ==========
        // 市场价为公允价值的 95% (5% 折扣)
        uint256 discountBps = 500; // 5%
        uint256 marketPricePerLP = lpFairValueInUSDC * (10000 - discountBps) / 10000 * 1e18 / lpAmount;
        MockLPSecondaryMarket market = new MockLPSecondaryMarket(lpToken, usdc, marketPricePerLP);

        // 转一些 LP 到二级市场供出售
        uint256 lpForSale = totalLP / 2; // 50% LP for sale
        vm.prank(lpProvider);
        lpToken.transfer(address(market), lpForSale);

        console.log("");
        console.log("=== Secondary Market ===");
        console.log("LP for sale:", lpForSale);
        console.log("Market price per LP (USDC wei):", marketPricePerLP);
        console.log("Fair value (for 10% LP):", lpFairValueInUSDC, "USDC");
        console.log("Discount: 5%");

        // 给其他协议充值
        usdc.mint(address(flashLender), 10_000_000e6);
        usdc.mint(address(dex), 10_000_000e6);
        weth.mint(address(dex), 5000 ether);

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

        // ========== 计算套利参数 ==========
        // 我们使用 10% 的可售 LP 进行套利演示
        uint256 lpToBuy = lpForSale / 5; // 买 10% 的可售 LP

        // 计算需要多少 USDC 去买这些 LP
        uint256 usdcToBorrow = lpToBuy * marketPricePerLP / 1e18;
        uint256 flashLoanFee = usdcToBorrow * 9 / 10000;

        // 移除流动性能获得的资产
        (uint256 expectedWETH, uint256 expectedUSDC) = lpPool.getUnderlyingValue(lpToBuy);

        // 卖 WETH 能获得的 USDC
        uint256 usdcFromWETH = expectedWETH * 2000e6 / 1e18;

        // 总 USDC 回收
        uint256 totalUSDCRecovered = expectedUSDC + usdcFromWETH;

        console.log("");
        console.log("=== Arbitrage Parameters ===");
        console.log("Borrow USDC:", usdcToBorrow);
        console.log("Flash loan fee:", flashLoanFee);
        console.log("LP to buy:", lpToBuy);
        console.log("Expected WETH from LP:", expectedWETH);
        console.log("Expected USDC from LP:", expectedUSDC);
        console.log("USDC from selling WETH:", usdcFromWETH);
        console.log("Total USDC recovered:", totalUSDCRecovered);
        console.log("Expected profit:", totalUSDCRecovered - usdcToBorrow - flashLoanFee);

        // ========== 构建套利调用链 (使用 Injection!) ==========
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](7);

        // Call 0: 授权二级市场使用 USDC
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.approve.selector, address(market), usdcToBorrow),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: 在二级市场买入 LP Token - 返回 lpAmount
        calls[1] = IChainedExecutor.Call({
            target: address(market),
            value: 0,
            callData: abi.encodeWithSelector(MockLPSecondaryMarket.buyLP.selector, usdcToBorrow),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 2: 移除流动性 - 使用 Injection 注入 Call 1 返回的 lpAmount!
        // 这是 Injection 的第一个演示点：处理购买返回的动态数量
        IChainedExecutor.Injection[] memory injectionsForRemoveLP = new IChainedExecutor.Injection[](1);
        injectionsForRemoveLP[0] = IChainedExecutor.Injection({
            sourceCallIndex: 1, // 从 Call 1 (buyLP) 取返回值
            sourceReturnOffset: 0, // lpAmount
            sourceReturnLength: 32, // uint256 长度
            targetCalldataOffset: 4 // removeLiquidity(uint256) 的第一个参数
        });

        calls[2] = IChainedExecutor.Call({
            target: address(lpPool),
            value: 0,
            callData: abi.encodeWithSelector(MockLPPool.removeLiquidity.selector, uint256(0)), // 占位，会被注入
            injections: injectionsForRemoveLP
        });

        // Call 3: 授权 DEX 使用 WETH
        // 这里用 Injection 将 Call 2 的返回值 amount0 (WETH) 注入到 approve 金额!
        IChainedExecutor.Injection[] memory injectionsForApprove = new IChainedExecutor.Injection[](1);
        injectionsForApprove[0] = IChainedExecutor.Injection({
            sourceCallIndex: 2, // 从 Call 2 (removeLiquidity) 取返回值
            sourceReturnOffset: 0, // 返回值第一个 uint256 (amount0 = WETH)
            sourceReturnLength: 32, // uint256 长度
            targetCalldataOffset: 36 // approve(address,uint256) 中 amount 参数的位置
        });

        calls[3] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.approve.selector, address(dex), uint256(0)), // 占位，会被注入
            injections: injectionsForApprove
        });

        // Call 4: 在 DEX 卖 WETH 换 USDC
        // 使用 Injection 将 Call 2 的 amount0 (WETH) 注入到 swap 金额!
        IChainedExecutor.Injection[] memory injectionsForSwap = new IChainedExecutor.Injection[](1);
        injectionsForSwap[0] = IChainedExecutor.Injection({
            sourceCallIndex: 2, // 从 Call 2 取返回值
            sourceReturnOffset: 0, // amount0 (WETH)
            sourceReturnLength: 32, // uint256 长度
            targetCalldataOffset: 4 // swapWETHForUSDC(uint256) 的第一个参数
        });

        calls[4] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeWithSelector(MockDEX.swapWETHForUSDC.selector, uint256(0)), // 占位，会被注入
            injections: injectionsForSwap
        });

        // Call 5: 还闪电贷
        uint256 repayAmount = usdcToBorrow + flashLoanFee;
        calls[5] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(MockERC20.transfer.selector, address(flashLender), repayAmount),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 6: 查询最终余额 (用于验证)
        calls[6] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSignature("balanceOf(address)", address(executor)),
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
        bytes memory callbackData =
            abi.encodeWithSelector(ChainedExecutor.executeSigned.selector, calls, currentNonce, deadline, signature);

        // ========== 执行套利 ==========
        console.log("");
        console.log("=== Executing LP Token Arbitrage ===");
        console.log("Key: Using Injection to handle dynamic amounts!");

        flashLender.flashLoan(address(executor), usdcToBorrow, callbackData);

        // ========== 结果分析 ==========
        uint256 finalUSDC = usdc.balanceOf(address(executor));
        uint256 finalWETH = weth.balanceOf(address(executor));
        uint256 finalLP = lpToken.balanceOf(address(executor));

        console.log("");
        console.log("=== Results ===");
        console.log("Final USDC:", finalUSDC);
        console.log("Final WETH:", finalWETH);
        console.log("Final LP:", finalLP);

        console.log("");
        console.log("=== Profit Analysis ===");
        console.log("Started with: 0 USDC (zero capital)");
        console.log("Ended with:", finalUSDC, "USDC");
        console.log("Net profit:", finalUSDC, "USDC");

        // 利润率
        if (finalUSDC > 0) {
            uint256 profitBps = finalUSDC * 10000 / usdcToBorrow;
            console.log("ROI (on borrowed):", profitBps, "bps");
        }

        console.log("");
        console.log("=== Injection Demonstration ===");
        console.log("1. buyLP() returned dynamic lpAmount");
        console.log("2. Injection injected lpAmount into removeLiquidity()");
        console.log("3. removeLiquidity() returned dynamic (WETH, USDC)");
        console.log("4. Injection injected WETH into approve() and swap()");
        console.log("5. Three injections - fully dynamic chain!");

        console.log("");
        console.log("=== Why This Works ===");
        console.log("1. LP Token underpriced in secondary market");
        console.log("2. Actual underlying value > market price");
        console.log("3. Flash loan enables zero-capital arbitrage");
        console.log("4. Injection handles unknown return values");

        console.log("");
        console.log("========================================");
        console.log("  LP Token Arbitrage Complete!");
        console.log("========================================");
    }
}
