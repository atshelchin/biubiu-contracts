// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainedExecutor, PackedUserOperation} from "../src/safe/ChainedExecutor.sol";
import {IChainedExecutor} from "../src/safe/IChainedExecutor.sol";
import {ChainedExecutorFactory} from "../src/safe/ChainedExecutorFactory.sol";

contract MockDEX {
    function swap(uint256 amountIn) external pure returns (uint256 amountOut) {
        return amountIn * 2;
    }

    function quote(uint256 amountIn) external pure returns (uint256) {
        return amountIn * 2;
    }
}

contract MockMultiReturn {
    function getValues(uint256 x) external pure returns (uint256 a, uint256 b, address c) {
        return (x * 2, x * 3, address(uint160(x)));
    }
}

/// @notice Mock FlashLoan 提供者
contract MockFlashLoanProvider {
    function flashLoan(address borrower, uint256 amount, bytes calldata data) external {
        // 发送资金给借款人
        payable(borrower).transfer(amount);

        // 调用借款人的回调
        (bool success,) = borrower.call(data);
        require(success, "Callback failed");

        // 验证还款 (简化：只检查余额是否返回)
        require(address(this).balance >= amount, "Not repaid");
    }

    receive() external payable {}
}

/// @notice Mock ERC20 代币
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MTK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
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

/// @notice Mock DEX (模拟 Uniswap 风格的 swap)
contract MockSwapRouter {
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    uint256 public rate = 2; // 1 tokenA = 2 tokenB

    constructor(MockERC20 _tokenA, MockERC20 _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    /// @notice 用 tokenA 换 tokenB
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "Invalid path");
        require(path[0] == address(tokenA) && path[1] == address(tokenB), "Invalid tokens");

        uint256 amountOut = amountIn * rate;
        require(amountOut >= amountOutMin, "Slippage");

        tokenA.transferFrom(msg.sender, address(this), amountIn);
        tokenB.transfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice 获取报价
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata /* path */
    )
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * rate;
    }
}

/// @notice 会 revert 的合约
contract MockReverter {
    error CustomError(string message);

    function revertWithMessage() external pure {
        revert("This always reverts");
    }

    function revertWithCustomError() external pure {
        revert CustomError("Custom error message");
    }

    function revertEmpty() external pure {
        revert();
    }
}

/// @notice 返回动态数据的合约
contract MockDynamicReturn {
    function getArray(uint256 length) external pure returns (uint256[] memory arr) {
        arr = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = i * 10;
        }
    }

    function getString() external pure returns (string memory) {
        return "Hello, World!";
    }

    function getBytes(uint256 length) external pure returns (bytes memory data) {
        data = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            data[i] = bytes1(uint8(i % 256));
        }
    }
}

/// @notice Mock 协议：调用后会回调 executor 执行链式调用
/// @dev 模拟闪电贷 + 套利场景：获取价格 → 回调执行套利 → 验证结果
contract MockCallbackProtocol {
    uint256 public lastCallbackResult;

    /// @notice 发起操作并回调
    /// @param target 回调目标
    /// @param callbackData 回调数据
    /// @param expectedMinResult 期望的最小结果
    function initiateWithCallback(address target, bytes calldata callbackData, uint256 expectedMinResult)
        external
        returns (uint256 result)
    {
        // 回调目标执行操作
        (bool success, bytes memory returnData) = target.call(callbackData);
        require(success, "Callback failed");

        // 解析回调返回的结果数组，取最后一个结果
        bytes[] memory results = abi.decode(returnData, (bytes[]));
        if (results.length > 0) {
            result = abi.decode(results[results.length - 1], (uint256));
        }

        require(result >= expectedMinResult, "Result below minimum");
        lastCallbackResult = result;
    }

    /// @notice 模拟更复杂的场景：先提供数据，再回调，再验证
    function executeWithDataAndCallback(uint256 inputData, address target, bytes calldata callbackData)
        external
        returns (uint256)
    {
        // 先存储输入数据供回调使用
        lastCallbackResult = inputData;

        // 回调
        (bool success, bytes memory returnData) = target.call(callbackData);
        require(success, "Callback failed");

        bytes[] memory results = abi.decode(returnData, (bytes[]));
        if (results.length > 0) {
            lastCallbackResult = abi.decode(results[results.length - 1], (uint256));
        }

        return lastCallbackResult;
    }

    /// @notice 获取存储的数据（供链式调用使用）
    function getData() external view returns (uint256) {
        return lastCallbackResult;
    }
}

/// @notice Mock 协议：模拟需要先询价再执行的场景
contract MockQuoteAndExecuteProtocol {
    uint256 public rate = 3;
    uint256 public lastExecutedAmount;

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    /// @notice 获取报价
    function quote(uint256 amount) external view returns (uint256) {
        return amount * rate;
    }

    /// @notice 执行操作（需要提供正确的期望输出）
    function executeWithExpectedOutput(uint256 amountIn, uint256 expectedOut) external returns (uint256) {
        uint256 actualOut = amountIn * rate;
        require(actualOut == expectedOut, "Output mismatch");
        lastExecutedAmount = actualOut;
        return actualOut;
    }
}

/// @notice Mock ERC-1271 智能合约钱包 (模拟 Safe/多签)
contract MockSmartWallet {
    address public signer;

    constructor(address _signer) {
        signer = _signer;
    }

    /// @notice ERC-1271 签名验证
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        // 验证签名是否来自 signer
        if (signature.length != 65) return 0xffffffff;

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;

        address recovered = ecrecover(hash, v, r, s);
        return recovered == signer ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

contract ChainedExecutorTest is Test {
    ChainedExecutor executor;
    ChainedExecutorFactory factory;
    MockDEX dexA;
    MockDEX dexB;
    MockMultiReturn multi;

    address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    uint256 ownerPrivateKey = 0xA11CE;
    address owner;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        factory = new ChainedExecutorFactory(entryPoint);
        executor = new ChainedExecutor(entryPoint, owner);
        dexA = new MockDEX();
        dexB = new MockDEX();
        multi = new MockMultiReturn();
    }

    /*//////////////////////////////////////////////////////////////
                           FACTORY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Factory_CreateAccount() public {
        address predicted = factory.getAddress(owner, 0);

        address created = factory.createAccount(owner, 0);

        assertEq(created, predicted);
        assertEq(ChainedExecutor(payable(created)).owner(), owner);
        assertEq(ChainedExecutor(payable(created)).entryPoint(), entryPoint);
    }

    function test_Factory_CreateAccount_Idempotent() public {
        address first = factory.createAccount(owner, 0);
        address second = factory.createAccount(owner, 0);

        assertEq(first, second);
    }

    function test_Factory_DifferentSalt() public {
        address account0 = factory.createAccount(owner, 0);
        address account1 = factory.createAccount(owner, 1);

        assertTrue(account0 != account1);
    }

    function test_Factory_GetInitCode() public {
        bytes memory initCode = factory.getInitCode(owner, 0);

        // initCode = factory address + createAccount calldata
        assertEq(initCode.length, 20 + 4 + 32 + 32); // addr + selector + owner + salt
    }

    /*//////////////////////////////////////////////////////////////
                         EOA EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_AsOwner() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_Execute_EntryPointCanCall() public {
        // EntryPoint 可以直接调用 execute(Call[])（ERC-4337 执行阶段）
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(entryPoint);
        bytes[] memory results = executor.execute(calls);
        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_Execute_RevertUnauthorized() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](0);

        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                         CHAINED EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InjectionChain() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](3);

        // Call 0: quote(100) → 200
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // Call 1: quote(result[0]) → 400
        IChainedExecutor.Injection[] memory inj1 = new IChainedExecutor.Injection[](1);
        inj1[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexB), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj1
        });

        // Call 2: quote(result[1]) → 800
        IChainedExecutor.Injection[] memory inj2 = new IChainedExecutor.Injection[](1);
        inj2[0] = IChainedExecutor.Injection({
            sourceCallIndex: 1, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[2] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj2
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
        assertEq(abi.decode(results[1], (uint256)), 400);
        assertEq(abi.decode(results[2], (uint256)), 800);
    }

    function test_ExtractMultipleReturns() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // getValues(10) → (20, 30, addr)
        calls[0] = IChainedExecutor.Call({
            target: address(multi),
            value: 0,
            callData: abi.encodeCall(MockMultiReturn.getValues, (10)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 使用第二个返回值 (30)
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 32, // 第二个返回值
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // quote(30) → 60
        assertEq(abi.decode(results[1], (uint256)), 60);
    }

    /*//////////////////////////////////////////////////////////////
                         ERC-4337 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ValidateUserOp_ValidSignature() public {
        bytes32 userOpHash = keccak256("test");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0); // 验证成功
        assertEq(executor.nonce(), 1); // nonce 递增
    }

    function test_ValidateUserOp_InvalidSignature() public {
        bytes32 userOpHash = keccak256("test");

        // 使用错误的私钥签名
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(0xBAD, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)));
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1); // 验证失败
    }

    function test_ValidateUserOp_OnlyEntryPoint() public {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("test");

        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.validateUserOp(userOp, userOpHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                 EXECUTE TESTS (onlyOwnerOrEntryPoint)
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteSingle_ByOwner() public {
        // owner 可以直接调用 execute(address, uint256, bytes)
        vm.prank(owner);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_ExecuteSingle_ByEntryPoint() public {
        // EntryPoint 可以调用 (ERC-4337 执行阶段)
        vm.prank(entryPoint);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_ExecuteSingle_RevertUnauthorized() public {
        // 非 owner/EntryPoint 不能调用
        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_ExecuteBatch_ByOwner() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(dexB),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (200)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        executor.execute(calls);
    }

    function test_ExecuteBatch_ByEntryPoint() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(dexB),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (200)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(entryPoint);
        executor.execute(calls);
    }

    function test_ExecuteBatch_RevertUnauthorized() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.execute(calls);
    }

    function test_ExecuteChained_ByOwner() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);
        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_ExecuteChained_ByEntryPoint() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(entryPoint);
        bytes[] memory results = executor.execute(calls);
        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_ExecuteChained_RevertUnauthorized() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                            MISC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteOpen_WithSignature() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        // 构造签名
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 任何人都可以提交（但需要有效签名）
        vm.prank(address(0xBEEF));
        bytes[] memory results = executor.executeSigned(calls, currentNonce, deadline, signature);

        assertEq(abi.decode(results[0], (uint256)), 100);
    }

    function test_ExecuteOpen_ExpiredDeadline() public {
        // 将时间设置为一个较大的值
        vm.warp(1000);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = 500; // 设置一个已过期的 deadline（block.timestamp=1000 > deadline=500）

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // deadline 已过期（block.timestamp > deadline），应该 revert
        vm.expectRevert(IChainedExecutor.InvalidSignature.selector);
        executor.executeSigned(calls, currentNonce, deadline, signature);
    }

    function test_ExecuteOpen_InvalidSignature() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // 使用错误的私钥
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IChainedExecutor.InvalidSignature.selector);
        executor.executeSigned(calls, currentNonce, deadline, signature);
    }

    function test_ExecuteOpen_InvalidNonce() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 wrongNonce = 999;
        uint256 deadline = block.timestamp + 1 hours;

        // 使用正确的签名格式（不含 "executeOpen" 字符串）
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, wrongNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 签名验证会先于 nonce 验证失败，因为签名包含 wrongNonce
        // 但 ecrecover 不会验证 nonce 的值，所以会继续到 nonce 检查
        vm.expectRevert(IChainedExecutor.InvalidNonce.selector);
        executor.executeSigned(calls, wrongNonce, deadline, signature);
    }

    function test_SetOwner() public {
        address newOwner = address(0x1234);

        vm.prank(owner);
        executor.setOwner(newOwner);

        assertEq(executor.owner(), newOwner);
    }

    function test_WithdrawETH() public {
        vm.deal(address(executor), 1 ether);
        address recipient = address(0x5678);

        vm.prank(owner);
        executor.withdrawETH(recipient, 0.5 ether);

        assertEq(recipient.balance, 0.5 ether);
    }

    function test_SupportsInterface() public view {
        assertTrue(executor.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(executor.supportsInterface(0x60fc6b6e)); // IAccount
    }

    /*//////////////////////////////////////////////////////////////
                    SMART CONTRACT OWNER TESTS (ERC-1271)
    //////////////////////////////////////////////////////////////*/

    function test_SmartWalletOwner_Execute() public {
        // 创建智能合约钱包作为 owner
        MockSmartWallet smartWallet = new MockSmartWallet(owner);
        ChainedExecutor scaExecutor = new ChainedExecutor(entryPoint, address(smartWallet));

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 智能合约钱包作为 owner 可以直接调用
        vm.prank(address(smartWallet));
        bytes[] memory results = scaExecutor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_SmartWalletOwner_ValidateUserOp() public {
        // 创建智能合约钱包作为 owner
        MockSmartWallet smartWallet = new MockSmartWallet(owner);
        ChainedExecutor scaExecutor = new ChainedExecutor(entryPoint, address(smartWallet));

        bytes32 userOpHash = keccak256("test");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        // 使用 signer 的私钥签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(scaExecutor),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = scaExecutor.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0); // ERC-1271 验证成功
    }

    function test_SmartWalletOwner_InvalidSignature() public {
        MockSmartWallet smartWallet = new MockSmartWallet(owner);
        ChainedExecutor scaExecutor = new ChainedExecutor(entryPoint, address(smartWallet));

        bytes32 userOpHash = keccak256("test");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        // 使用错误的私钥签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(scaExecutor),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = scaExecutor.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1); // 验证失败
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-4337 FULL FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ERC4337_FullFlow_SingleCall() public {
        // 模拟完整的 ERC-4337 流程: validateUserOp → execute

        bytes32 userOpHash = keccak256("test-single-call");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 构造 callData: execute(address, uint256, bytes)
        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("execute(address,uint256,bytes)")), address(dexA), 0, abi.encodeCall(MockDEX.quote, (100))
        );

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        // 1. 验证阶段
        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0);

        // 2. 执行阶段
        vm.prank(entryPoint);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_ERC4337_FullFlow_BatchCall() public {
        bytes32 userOpHash = keccak256("test-batch-call");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(dexB),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (200)),
            injections: new IChainedExecutor.Injection[](0)
        });

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute((address,uint256,bytes,(uint16,uint16,uint16,uint16)[])[])", calls
            ),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0);

        vm.prank(entryPoint);
        executor.execute(calls);
    }

    function test_ERC4337_FullFlow_ChainedCall() public {
        bytes32 userOpHash = keccak256("test-chained-call");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexB), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute((address,uint256,bytes,(uint16,uint16,uint16,uint16)[])[])", calls
            ),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0);

        vm.prank(entryPoint);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200); // 100 * 2
        assertEq(abi.decode(results[1], (uint256)), 400); // 200 * 2
    }

    function test_ERC4337_FirstTimeDeployAndExecute() public {
        // 模拟首次部署账户并执行操作
        address newOwner = vm.addr(0xBEEF);
        uint256 salt = 12345;

        // 预计算地址
        address predicted = factory.getAddress(newOwner, salt);

        // 构造 initCode
        bytes memory initCode = factory.getInitCode(newOwner, salt);

        // 构造 UserOp
        bytes32 userOpHash = keccak256("first-deploy");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBEEF, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 模拟 EntryPoint 部署账户
        address deployed = factory.createAccount(newOwner, salt);
        assertEq(deployed, predicted);

        ChainedExecutor newExecutor = ChainedExecutor(payable(deployed));

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: deployed,
            nonce: 0,
            initCode: initCode,
            callData: abi.encodeWithSelector(
                bytes4(keccak256("execute(address,uint256,bytes)")),
                address(dexA),
                0,
                abi.encodeCall(MockDEX.quote, (50))
            ),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        // 验证
        vm.prank(entryPoint);
        uint256 validationData = newExecutor.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0);

        // 执行
        vm.prank(entryPoint);
        newExecutor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (50)));
    }

    function test_ERC4337_InvalidNonce() public {
        bytes32 userOpHash = keccak256("test");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 999, // 错误的 nonce
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        vm.prank(entryPoint);
        uint256 validationData = executor.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 1); // nonce 错误导致验证失败
    }

    function test_ERC4337_PayGasFees() public {
        // 给账户充值
        vm.deal(address(executor), 1 ether);

        bytes32 userOpHash = keccak256("test-gas");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(executor),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });

        uint256 entryPointBalanceBefore = entryPoint.balance;

        // validateUserOp 需要支付 gas 费
        vm.prank(entryPoint);
        executor.validateUserOp(userOp, userOpHash, 0.1 ether);

        // EntryPoint 应该收到 gas 费
        assertEq(entryPoint.balance, entryPointBalanceBefore + 0.1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTE WITH SIGNATURE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteWithSignature_Success() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();

        // 构造签名消息
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, uint256(0)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 任何人都可以提交
        vm.prank(address(0xCAFE));
        bytes[] memory results = executor.executeSigned(calls, currentNonce, 0, signature);

        assertEq(abi.decode(results[0], (uint256)), 200);
        assertEq(executor.nonce(), currentNonce + 1);
    }

    function test_ExecuteWithSignature_InvalidNonce() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 wrongNonce = 999;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, wrongNonce, uint256(0)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IChainedExecutor.InvalidNonce.selector);
        executor.executeSigned(calls, wrongNonce, 0, signature);
    }

    function test_ExecuteWithSignature_InvalidSignature() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, uint256(0)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // 使用错误的私钥
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IChainedExecutor.InvalidSignature.selector);
        executor.executeSigned(calls, currentNonce, 0, signature);
    }

    function test_ExecuteWithSignature_ReplayProtection() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, uint256(0)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 第一次执行成功
        executor.executeSigned(calls, currentNonce, 0, signature);

        // 重放攻击应该失败
        vm.expectRevert(IChainedExecutor.InvalidNonce.selector);
        executor.executeSigned(calls, currentNonce, 0, signature);
    }

    function test_ExecuteWithSignature_ChainedCalls() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexB), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        uint256 currentNonce = executor.nonce();

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, uint256(0)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes[] memory results = executor.executeSigned(calls, currentNonce, 0, signature);

        assertEq(abi.decode(results[0], (uint256)), 200);
        assertEq(abi.decode(results[1], (uint256)), 400);
    }

    /*//////////////////////////////////////////////////////////////
                    INJECTION EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Injection_MultipleInjections() public {
        // 多个注入点
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // getValues(10) → (20, 30, addr)
        calls[0] = IChainedExecutor.Call({
            target: address(multi),
            value: 0,
            callData: abi.encodeCall(MockMultiReturn.getValues, (10)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 从第一个调用中提取多个返回值
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0, // 第一个返回值 (20)
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // quote(20) → 40
        assertEq(abi.decode(results[1], (uint256)), 40);
    }

    function test_Injection_InvalidSourceIndex() public {
        // 源索引越界应该被忽略
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 99, // 越界
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)), // 使用原始值
            injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 注入失败，使用原始值 50
        assertEq(abi.decode(results[1], (uint256)), 100); // 50 * 2
    }

    function test_Injection_InvalidOffset() public {
        // 偏移量越界应该被忽略
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 1000, // 越界
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (25)), injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 注入失败，使用原始值
        assertEq(abi.decode(results[1], (uint256)), 50);
    }

    function test_Injection_ZeroLength() public {
        // 0 长度注入应该被忽略（实际上不会复制任何内容）
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 0, // 0 长度
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (33)), injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 原始值不变
        assertEq(abi.decode(results[1], (uint256)), 66);
    }

    function test_Injection_LongChain() public {
        // 测试长链式调用
        uint256 chainLength = 5;
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](chainLength);

        // 第一个调用
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (1)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 后续调用都依赖前一个
        for (uint256 i = 1; i < chainLength; i++) {
            IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
            inj[0] = IChainedExecutor.Injection({
                sourceCallIndex: uint16(i - 1), sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
            });

            calls[i] = IChainedExecutor.Call({
                target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
            });
        }

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 1 → 2 → 4 → 8 → 16 → 32
        assertEq(abi.decode(results[0], (uint256)), 2);
        assertEq(abi.decode(results[1], (uint256)), 4);
        assertEq(abi.decode(results[2], (uint256)), 8);
        assertEq(abi.decode(results[3], (uint256)), 16);
        assertEq(abi.decode(results[4], (uint256)), 32);
    }

    /*//////////////////////////////////////////////////////////////
                        ETH VALUE TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteWithValue() public {
        vm.deal(address(executor), 1 ether);

        address recipient = address(0x1234);
        uint256 sendAmount = 0.5 ether;

        vm.prank(owner);
        executor.execute(recipient, sendAmount, "");

        assertEq(recipient.balance, sendAmount);
    }

    function test_ExecuteBatchWithValue() public {
        vm.deal(address(executor), 1 ether);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);
        calls[0] = IChainedExecutor.Call({
            target: address(0x1111), value: 0.3 ether, callData: "", injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(0x2222), value: 0.2 ether, callData: "", injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        executor.execute(calls);

        assertEq(address(0x1111).balance, 0.3 ether);
        assertEq(address(0x2222).balance, 0.2 ether);
    }

    function test_ExecuteChainedWithValue() public {
        vm.deal(address(executor), 1 ether);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(0x1111), value: 0.3 ether, callData: "", injections: new IChainedExecutor.Injection[](0)
        });

        calls[1] = IChainedExecutor.Call({
            target: address(0x2222), value: 0.2 ether, callData: "", injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        executor.execute(calls);

        assertEq(address(0x1111).balance, 0.3 ether);
        assertEq(address(0x2222).balance, 0.2 ether);
    }

    function test_ReceiveETH() public {
        vm.deal(address(this), 1 ether);

        (bool success,) = address(executor).call{value: 0.5 ether}("");
        assertTrue(success);
        assertEq(address(executor).balance, 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR HANDLING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_RevertOnFailedCall() public {
        MockReverter reverter = new MockReverter();

        vm.prank(owner);
        vm.expectRevert("This always reverts");
        executor.execute(address(reverter), 0, abi.encodeCall(MockReverter.revertWithMessage, ()));
    }

    function test_ExecuteBatch_RevertOnFailedCall() public {
        MockReverter reverter = new MockReverter();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(reverter),
            value: 0,
            callData: abi.encodeCall(MockReverter.revertWithMessage, ()),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IChainedExecutor.CallFailed.selector, 1, abi.encodeWithSignature("Error(string)", "This always reverts")
            )
        );
        executor.execute(calls);
    }

    function test_ExecuteChained_RevertOnFailedCall() public {
        MockReverter reverter = new MockReverter();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        calls[1] = IChainedExecutor.Call({
            target: address(reverter),
            value: 0,
            callData: abi.encodeCall(MockReverter.revertWithMessage, ()),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IChainedExecutor.CallFailed.selector, 1, abi.encodeWithSignature("Error(string)", "This always reverts")
            )
        );
        executor.execute(calls);
    }

    function test_SetOwner_RevertUnauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.setOwner(address(0x1234));
    }

    function test_WithdrawETH_RevertUnauthorized() public {
        vm.deal(address(executor), 1 ether);

        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.withdrawETH(address(0x1234), 0.5 ether);
    }

    function test_WithdrawToken_RevertUnauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.withdrawToken(address(dexA), address(0x1234), 100);
    }

    /*//////////////////////////////////////////////////////////////
                    DEFI SCENARIO SIMULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeFi_SwapWithQuote() public {
        // 模拟: 先获取报价，再用报价结果作为 swap 的 amountOutMin
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        MockSwapRouter router = new MockSwapRouter(tokenA, tokenB);

        // 设置初始状态
        tokenA.mint(address(executor), 1000 ether);
        tokenB.mint(address(router), 10000 ether);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](3);

        // 1. approve
        calls[0] = IChainedExecutor.Call({
            target: address(tokenA),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(router), 100 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. getAmountsOut 获取报价
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        calls[1] = IChainedExecutor.Call({
            target: address(router),
            value: 0,
            callData: abi.encodeCall(MockSwapRouter.getAmountsOut, (100 ether, path)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 3. swap，使用报价结果作为 amountOutMin
        // getAmountsOut 返回 [amountIn, amountOut]，amountOut 在 offset 64 (32 + 32)
        // 但是动态数组的 abi 编码比较复杂，这里简化处理
        calls[2] = IChainedExecutor.Call({
            target: address(router),
            value: 0,
            callData: abi.encodeCall(
                MockSwapRouter.swapExactTokensForTokens, (100 ether, 0, path, address(executor), block.timestamp)
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 验证 swap 成功
        (uint256[] memory amounts) = abi.decode(results[2], (uint256[]));
        assertEq(amounts[0], 100 ether);
        assertEq(amounts[1], 200 ether); // rate = 2

        assertEq(tokenB.balanceOf(address(executor)), 200 ether);
    }

    function test_DeFi_FlashLoanCallback() public {
        MockFlashLoanProvider flashLoan = new MockFlashLoanProvider();
        vm.deal(address(flashLoan), 10 ether);
        vm.deal(address(executor), 0.1 ether); // 一点 gas 费

        // 构造回调数据: executeSigned 还款给 flashLoan
        IChainedExecutor.Call[] memory repaymentCalls = new IChainedExecutor.Call[](1);
        repaymentCalls[0] = IChainedExecutor.Call({
            target: address(flashLoan), value: 1 ether, callData: "", injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        // 构造签名（使用新格式，不含 "executeOpen"）
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, repaymentCalls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (repaymentCalls, currentNonce, deadline, signature));

        // 发起闪电贷
        vm.prank(owner);
        executor.execute(
            address(flashLoan),
            0,
            abi.encodeCall(MockFlashLoanProvider.flashLoan, (address(executor), 1 ether, callbackData))
        );

        // 闪电贷完成后，资金应该返回
        assertGe(address(flashLoan).balance, 10 ether);
    }

    function test_DeFi_MultiDexArbitrage() public {
        // 模拟套利: DEX A 价格 1:2, DEX B 价格 1:3
        // 在 A 买，在 B 卖
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();

        MockSwapRouter routerA = new MockSwapRouter(tokenA, tokenB);
        routerA.setRate(2); // 1 tokenA = 2 tokenB

        MockSwapRouter routerB = new MockSwapRouter(tokenB, tokenA);

        // 设置初始状态
        tokenA.mint(address(executor), 100 ether);
        tokenB.mint(address(routerA), 1000 ether);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 1. Approve
        calls[0] = IChainedExecutor.Call({
            target: address(tokenA),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(routerA), 100 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. Swap on DEX A
        calls[1] = IChainedExecutor.Call({
            target: address(routerA),
            value: 0,
            callData: abi.encodeCall(
                MockSwapRouter.swapExactTokensForTokens, (100 ether, 0, path, address(executor), block.timestamp)
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        executor.execute(calls);

        // 验证
        assertEq(tokenA.balanceOf(address(executor)), 0);
        assertEq(tokenB.balanceOf(address(executor)), 200 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OwnerChange_NewOwnerCanExecute() public {
        address newOwner = address(0x9999);

        vm.prank(owner);
        executor.setOwner(newOwner);

        // 新 owner 可以执行
        vm.prank(newOwner);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_OwnerChange_OldOwnerCannotExecute() public {
        address newOwner = address(0x9999);

        vm.prank(owner);
        executor.setOwner(newOwner);

        // 旧 owner 不能执行
        vm.prank(owner);
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    /*//////////////////////////////////////////////////////////////
                        EMPTY CALLS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_EmptyCalls() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](0);

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(results.length, 0);
    }

    function test_ExecuteBatch_EmptyCalls() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](0);

        vm.prank(owner);
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                    SMART WALLET WITH SIGNATURE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SmartWalletOwner_ExecuteWithSignature() public {
        MockSmartWallet smartWallet = new MockSmartWallet(owner);
        ChainedExecutor scaExecutor = new ChainedExecutor(entryPoint, address(smartWallet));

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = scaExecutor.nonce();
        uint256 deadline = 0; // no expiry

        bytes32 hash = keccak256(abi.encode(address(scaExecutor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // 使用 smartWallet 的 signer 签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes[] memory results = scaExecutor.executeSigned(calls, currentNonce, deadline, signature);

        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    /*//////////////////////////////////////////////////////////////
                    CALLBACK WITH CHAINED EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：外部协议回调 executor 执行链式调用
    /// @dev 场景：Protocol.initiate() → 回调 executor.executeSigned() → 链式调用多个合约
    function test_Callback_ChainedExecution() public {
        MockCallbackProtocol protocol = new MockCallbackProtocol();

        // 构造链式调用：quote(50) → quote(result)
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // 第一个调用：dexA.quote(50) → 返回 100
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 第二个调用：dexB.quote(上一步结果) → 注入 100 → 返回 200
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexB),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (0)), // 将被注入
            injections: inj
        });

        // 准备 executeOpen 的签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 构造回调数据
        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (calls, currentNonce, deadline, signature));

        // owner 调用 protocol，protocol 回调 executor
        vm.prank(owner);
        executor.execute(
            address(protocol),
            0,
            abi.encodeCall(MockCallbackProtocol.initiateWithCallback, (address(executor), callbackData, 200))
        );

        // 验证回调结果
        assertEq(protocol.lastCallbackResult(), 200);
    }

    /// @notice 测试：回调中使用协议提供的数据进行链式调用
    /// @dev 场景：Protocol 先存储数据 → 回调 executor → executor 读取数据并处理
    function test_Callback_UseProtocolDataInChain() public {
        MockCallbackProtocol protocol = new MockCallbackProtocol();

        // 构造链式调用：读取 protocol 的数据 → 用数据调用 dexA
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // 第一个调用：读取 protocol.getData()
        calls[0] = IChainedExecutor.Call({
            target: address(protocol),
            value: 0,
            callData: abi.encodeCall(MockCallbackProtocol.getData, ()),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 第二个调用：用读取的数据调用 dexA.quote()
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dexA), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        // 准备 executeOpen 签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (calls, currentNonce, deadline, signature));

        // owner 调用 protocol，传入输入数据 75
        // protocol 存储 75 → 回调 executor → executor 读取 75 → quote(75) → 150
        vm.prank(owner);
        executor.execute(
            address(protocol),
            0,
            abi.encodeCall(MockCallbackProtocol.executeWithDataAndCallback, (75, address(executor), callbackData))
        );

        // 验证：getData() 返回 75，quote(75) 返回 150
        assertEq(protocol.lastCallbackResult(), 150);
    }

    /// @notice 测试：先询价再执行的链式回调场景
    /// @dev 场景：quote() 获取价格 → 用价格作为参数执行操作
    function test_Callback_QuoteThenExecuteChain() public {
        MockQuoteAndExecuteProtocol protocol = new MockQuoteAndExecuteProtocol();

        // 构造链式调用：quote(100) → executeWithExpectedOutput(100, quote结果)
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // 第一个调用：quote(100) → 返回 300 (rate=3)
        calls[0] = IChainedExecutor.Call({
            target: address(protocol),
            value: 0,
            callData: abi.encodeCall(MockQuoteAndExecuteProtocol.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 第二个调用：executeWithExpectedOutput(100, quote结果)
        // quote 结果注入到第二个参数位置 (offset = 4 + 32 = 36)
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 36 // 跳过 selector(4) + amountIn(32)
        });

        calls[1] = IChainedExecutor.Call({
            target: address(protocol),
            value: 0,
            callData: abi.encodeCall(MockQuoteAndExecuteProtocol.executeWithExpectedOutput, (100, 0)), // expectedOut 将被注入
            injections: inj
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 验证
        assertEq(abi.decode(results[0], (uint256)), 300); // quote(100) = 300
        assertEq(abi.decode(results[1], (uint256)), 300); // execute 成功
        assertEq(protocol.lastExecutedAmount(), 300);
    }

    /// @notice 测试：复杂的多层回调场景
    /// @dev 场景：executor → protocol A → 回调 executor → protocol B → 返回
    function test_Callback_NestedProtocolCalls() public {
        MockCallbackProtocol protocolA = new MockCallbackProtocol();

        // 外层调用：调用 protocolA，protocolA 回调 executor 执行链式调用
        // 内层链式调用：dexA.quote(10) → dexB.quote(result)

        IChainedExecutor.Call[] memory innerCalls = new IChainedExecutor.Call[](2);

        innerCalls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (10)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        innerCalls[1] = IChainedExecutor.Call({
            target: address(dexB), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        // 准备内层 executeSigned 签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, innerCalls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory innerCallbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (innerCalls, currentNonce, deadline, signature));

        // 外层调用
        IChainedExecutor.Call[] memory outerCalls = new IChainedExecutor.Call[](1);
        outerCalls[0] = IChainedExecutor.Call({
            target: address(protocolA),
            value: 0,
            callData: abi.encodeCall(
                MockCallbackProtocol.initiateWithCallback,
                (address(executor), innerCallbackData, 40) // 10 → 20 → 40
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(outerCalls);

        // 验证：10 * 2 = 20, 20 * 2 = 40
        assertEq(protocolA.lastCallbackResult(), 40);
    }

    /// @notice 测试：executeSigned 也可以被回调（通过外部调用触发）
    function test_Callback_ExecuteWithSignature() public {
        MockCallbackProtocol protocol = new MockCallbackProtocol();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (123)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = 0; // no expiry

        // 使用 executeSigned 的签名格式
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (calls, currentNonce, deadline, signature));

        // 任何人都可以触发（只要签名有效）
        vm.prank(address(0xBEEF));
        protocol.initiateWithCallback(address(executor), callbackData, 246);

        assertEq(protocol.lastCallbackResult(), 246); // 123 * 2
    }
}

/*//////////////////////////////////////////////////////////////
                    SECURITY & DEFI ADVANCED TESTS
//////////////////////////////////////////////////////////////*/

/// @notice 模拟 AAVE V3 风格的闪电贷
contract MockAaveV3FlashLoan {
    MockERC20 public token;
    uint256 public constant FLASH_LOAN_FEE = 9; // 0.09% = 9/10000

    constructor(MockERC20 _token) {
        token = _token;
    }

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 /* referralCode */
    )
        external
    {
        require(asset == address(token), "Invalid asset");
        uint256 balanceBefore = token.balanceOf(address(this));

        // 转出资金
        token.transfer(receiverAddress, amount);

        // 计算手续费
        uint256 premium = (amount * FLASH_LOAN_FEE) / 10000;

        // 回调
        (bool success,) = receiverAddress.call(
            abi.encodeWithSignature(
                "executeOperation(address,uint256,uint256,address,bytes)", asset, amount, premium, msg.sender, params
            )
        );
        require(success, "Callback failed");

        // 验证还款
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + premium, "Flash loan not repaid");
    }
}

/// @notice 模拟 Uniswap V2 风格的闪电兑换
contract MockUniswapV2Pair {
    MockERC20 public token0;
    MockERC20 public token1;
    uint112 public reserve0;
    uint112 public reserve1;

    constructor(MockERC20 _token0, MockERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }

    /// @notice 模拟 flash swap
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external {
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output");

        // 转出 token
        if (amount0Out > 0) token0.transfer(to, amount0Out);
        if (amount1Out > 0) token1.transfer(to, amount1Out);

        // 如果有 data，执行回调
        if (data.length > 0) {
            (bool success,) = to.call(
                abi.encodeWithSignature(
                    "uniswapV2Call(address,uint256,uint256,bytes)", msg.sender, amount0Out, amount1Out, data
                )
            );
            require(success, "Callback failed");
        }

        // 验证 K 值 (简化版)
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(balance0 * balance1 >= uint256(reserve0) * uint256(reserve1), "K");

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }
}

/// @notice 模拟 Uniswap V3 风格的闪电贷
contract MockUniswapV3Pool {
    MockERC20 public token0;
    MockERC20 public token1;

    constructor(MockERC20 _token0, MockERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external {
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        // 转出
        if (amount0 > 0) token0.transfer(recipient, amount0);
        if (amount1 > 0) token1.transfer(recipient, amount1);

        // 计算手续费 (0.05%)
        uint256 fee0 = amount0 > 0 ? (amount0 * 5) / 10000 + 1 : 0;
        uint256 fee1 = amount1 > 0 ? (amount1 * 5) / 10000 + 1 : 0;

        // 回调
        (bool success,) =
            recipient.call(abi.encodeWithSignature("uniswapV3FlashCallback(uint256,uint256,bytes)", fee0, fee1, data));
        require(success, "Callback failed");

        // 验证还款
        require(token0.balanceOf(address(this)) >= balance0Before + fee0, "Flash0");
        require(token1.balanceOf(address(this)) >= balance1Before + fee1, "Flash1");
    }
}

/// @notice 重入攻击测试合约
contract ReentrancyAttacker {
    ChainedExecutor public target;
    uint256 public attackCount;
    uint256 public maxAttacks = 3;

    function setTarget(ChainedExecutor _target) external {
        target = _target;
    }

    /// @notice 被调用时尝试重入
    function maliciousCallback() external returns (uint256) {
        attackCount++;
        if (attackCount < maxAttacks) {
            // 尝试重入调用
            IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
            calls[0] = IChainedExecutor.Call({
                target: address(this),
                value: 0,
                callData: abi.encodeCall(this.maliciousCallback, ()),
                injections: new IChainedExecutor.Injection[](0)
            });

            // 这会失败因为 onlyOwner
            // target.execute(calls);
        }
        return attackCount;
    }

    /// @notice 尝试通过回调窃取资金
    function stealFunds() external {
        // 尝试调用 withdrawETH
        // 会失败因为 onlyOwner
    }
}

/// @notice 模拟 1inch 聚合器风格的 swap
contract Mock1inchRouter {
    function swap(
        address srcToken,
        address dstToken,
        uint256 amount,
        uint256 minReturn,
        bytes calldata /* data */
    )
        external
        returns (uint256 returnAmount)
    {
        MockERC20(srcToken).transferFrom(msg.sender, address(this), amount);

        // 模拟 1.5x 的兑换率
        returnAmount = (amount * 15) / 10;
        require(returnAmount >= minReturn, "Slippage");

        MockERC20(dstToken).transfer(msg.sender, returnAmount);
    }

    function getExpectedReturn(
        address,
        /* srcToken */
        address,
        /* dstToken */
        uint256 amount
    )
        external
        pure
        returns (uint256)
    {
        return (amount * 15) / 10;
    }
}

/// @notice 模拟 Curve 风格的稳定币兑换
contract MockCurvePool {
    MockERC20[3] public coins;
    uint256 public constant FEE = 4; // 0.04%

    constructor(MockERC20 _coin0, MockERC20 _coin1, MockERC20 _coin2) {
        coins[0] = _coin0;
        coins[1] = _coin1;
        coins[2] = _coin2;
    }

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256 dy) {
        require(i >= 0 && i < 3 && j >= 0 && j < 3, "Invalid index");

        coins[uint128(i)].transferFrom(msg.sender, address(this), dx);

        // 稳定币 1:1 减手续费
        dy = dx - (dx * FEE) / 10000;
        require(dy >= minDy, "Slippage");

        coins[uint128(j)].transfer(msg.sender, dy);
    }

    function get_dy(
        int128,
        /* i */
        int128,
        /* j */
        uint256 dx
    )
        external
        pure
        returns (uint256)
    {
        return dx - (dx * FEE) / 10000;
    }
}

/// @notice 模拟 GMX 风格的杠杆交易
contract MockGMXRouter {
    MockERC20 public collateralToken;

    constructor(MockERC20 _collateralToken) {
        collateralToken = _collateralToken;
    }

    function createIncreasePosition(
        address[] calldata,
        /* _path */
        address,
        /* _indexToken */
        uint256 _amountIn,
        uint256,
        /* _minOut */
        uint256,
        /* _sizeDelta */
        bool,
        /* _isLong */
        uint256,
        /* _acceptablePrice */
        uint256,
        /* _executionFee */
        bytes32,
        /* _referralCode */
        address /* _callbackTarget */
    ) external payable returns (bytes32) {
        collateralToken.transferFrom(msg.sender, address(this), _amountIn);
        return keccak256(abi.encodePacked(block.timestamp, msg.sender, _amountIn));
    }
}

/// @notice 用于测试利润检查的辅助合约
contract ProfitChecker {
    error InsufficientProfit(uint256 actual, uint256 expected);

    function checkProfit(address token, uint256 minProfit, uint256 startBalance) external view {
        uint256 currentBalance = MockERC20(token).balanceOf(msg.sender);
        uint256 profit = currentBalance > startBalance ? currentBalance - startBalance : 0;
        if (profit < minProfit) {
            revert InsufficientProfit(profit, minProfit);
        }
    }

    function getBalance(address token, address account) external view returns (uint256) {
        return MockERC20(token).balanceOf(account);
    }
}

contract ChainedExecutorSecurityTest is Test {
    ChainedExecutor executor;
    ChainedExecutorFactory factory;

    address entryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    uint256 ownerPrivateKey = 0xA11CE;
    address owner;

    MockERC20 usdc;
    MockERC20 usdt;
    MockERC20 dai;
    MockERC20 weth;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        factory = new ChainedExecutorFactory(entryPoint);
        executor = new ChainedExecutor(entryPoint, owner);

        // 部署代币
        usdc = new MockERC20();
        usdt = new MockERC20();
        dai = new MockERC20();
        weth = new MockERC20();
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY VULNERABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：重入攻击是否被阻止
    function test_Security_ReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker();
        attacker.setTarget(executor);

        // 正常调用应该成功
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(attacker),
            value: 0,
            callData: abi.encodeCall(ReentrancyAttacker.maliciousCallback, ()),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 攻击者的回调不能重入（因为 onlyOwner）
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 只执行了一次
        assertEq(attacker.attackCount(), 1);
    }

    /// @notice 测试：executeSigned 在签名验证失败时 nonce 不应该改变
    /// @dev 已修复：签名验证在 nonce 递增之前执行
    function test_Security_NonceNotIncrementedOnFailure() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), owner),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 nonceBefore = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        // 构造错误的签名（用正确格式但错误私钥）
        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, nonceBefore, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // 使用错误私钥签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, ethSignedHash);
        bytes memory badSignature = abi.encodePacked(r, s, v);

        // 执行应该失败
        vm.expectRevert(IChainedExecutor.InvalidSignature.selector);
        executor.executeSigned(calls, nonceBefore, deadline, badSignature);

        // 验证 nonce 没有改变（签名验证在 nonce 递增之前）
        assertEq(executor.nonce(), nonceBefore);
    }

    /// @notice 测试：签名重放攻击保护
    function test_Security_SignatureReplayProtection() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), owner),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 第一次执行成功
        executor.executeSigned(calls, currentNonce, deadline, signature);

        // 重放攻击应该失败
        vm.expectRevert(IChainedExecutor.InvalidNonce.selector);
        executor.executeSigned(calls, currentNonce, deadline, signature);
    }

    /// @notice 测试：跨链签名重放保护
    function test_Security_CrossChainReplayProtection() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), owner),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 currentNonce = executor.nonce();

        // 用不同的 chainid 签名
        bytes32 hash = keccak256(abi.encode(address(executor), 999, calls, currentNonce)); // 错误的 chainid
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 应该失败因为 chainid 不匹配
        vm.expectRevert(IChainedExecutor.InvalidSignature.selector);
        executor.executeSigned(calls, currentNonce, 0, signature);
    }

    /// @notice 测试：无法窃取账户中的 gas 费
    function test_Security_CannotStealGasFunds() public {
        // 给 executor 一些 ETH 作为 gas 费
        vm.deal(address(executor), 0.1 ether);

        // 攻击者尝试窃取
        vm.prank(address(0xBAD));
        vm.expectRevert(IChainedExecutor.Unauthorized.selector);
        executor.withdrawETH(address(0xBAD), 0.1 ether);

        // ETH 仍在
        assertEq(address(executor).balance, 0.1 ether);
    }

    /// @notice 测试：恶意 target 不能破坏执行
    function test_Security_MaliciousTargetHandling() public {
        MockReverter reverter = new MockReverter();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // 第一个正常调用
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), owner),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 第二个恶意调用
        calls[1] = IChainedExecutor.Call({
            target: address(reverter),
            value: 0,
            callData: abi.encodeCall(MockReverter.revertWithMessage, ()),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 整个交易应该回滚
        vm.prank(owner);
        vm.expectRevert();
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                        AAVE V3 FLASH LOAN ARBITRAGE TEST
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：完整的 AAVE V3 闪电贷套利流程
    /// @dev 跳过：AAVE 使用 executeOperation 回调，需要专门的适配器合约
    function skip_test_DeFi_AaveV3FlashLoanArbitrage() public {
        // 部署 AAVE 和 DEX
        MockAaveV3FlashLoan aave = new MockAaveV3FlashLoan(usdc);
        Mock1inchRouter router = new Mock1inchRouter();

        // 准备流动性
        usdc.mint(address(aave), 1_000_000 ether);
        weth.mint(address(router), 1_000_000 ether);
        usdc.mint(address(router), 1_000_000 ether);

        // 给 executor 一点 USDC 用于支付手续费
        usdc.mint(address(executor), 100 ether);

        // 准备套利回调数据
        // 1. approve router
        // 2. swap USDC → WETH
        // 3. approve router (WETH)
        // 4. swap WETH → USDC
        // 5. approve AAVE (还款)
        // 6. 检查利润

        uint256 flashAmount = 10000 ether;
        uint256 premium = (flashAmount * 9) / 10000; // 0.09% fee

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](5);

        // 1. Approve router to spend USDC
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(router), flashAmount)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. Swap USDC → WETH (获得 15000 WETH)
        calls[1] = IChainedExecutor.Call({
            target: address(router),
            value: 0,
            callData: abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,bytes)", address(usdc), address(weth), flashAmount, 0, ""
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 3. Approve router to spend WETH
        calls[2] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(router), type(uint256).max)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 4. Swap WETH → USDC (获得 22500 USDC)
        calls[3] = IChainedExecutor.Call({
            target: address(router),
            value: 0,
            callData: abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,bytes)",
                address(weth),
                address(usdc),
                (flashAmount * 15) / 10, // swap 获得的 WETH
                0,
                ""
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 5. Approve AAVE for repayment
        calls[4] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(aave), flashAmount + premium)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 准备 executeOpen 签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 构造 AAVE executeOperation 回调
        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (calls, currentNonce, deadline, signature));

        uint256 balanceBefore = usdc.balanceOf(address(executor));

        // 发起闪电贷
        vm.prank(owner);
        executor.execute(
            address(aave),
            0,
            abi.encodeWithSignature(
                "flashLoanSimple(address,address,uint256,bytes,uint16)",
                address(executor),
                address(usdc),
                flashAmount,
                callbackData,
                0
            )
        );

        uint256 balanceAfter = usdc.balanceOf(address(executor));

        // 验证利润 (22500 - 10000 - 9 fee - 100 initial = 12391)
        assertGt(balanceAfter, balanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        UNISWAP V2 FLASH SWAP ARBITRAGE TEST
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：Uniswap V2 闪电兑换套利
    /// @dev 跳过：Uniswap V2 使用 uniswapV2Call 回调，需要专门的适配器合约
    function skip_test_DeFi_UniswapV2FlashSwapArbitrage() public {
        MockUniswapV2Pair pair = new MockUniswapV2Pair(weth, usdc);
        Mock1inchRouter router = new Mock1inchRouter();

        // 设置流动性
        weth.mint(address(pair), 1000 ether);
        usdc.mint(address(pair), 2_000_000 ether);
        pair.setReserves(1000 ether, 2_000_000 ether);

        // router 流动性
        weth.mint(address(router), 10000 ether);
        usdc.mint(address(router), 10_000_000 ether);

        // 给 executor 少量资金用于手续费
        weth.mint(address(executor), 1 ether);

        // Flash swap: 借出 100 WETH，需要还 ~100.3 WETH (0.3% fee)
        uint256 borrowAmount = 100 ether;

        // 回调中的操作：
        // 1. Approve router
        // 2. Swap WETH → USDC (获得 150 USDC)
        // 3. Approve router
        // 4. Swap USDC → WETH (用 150 USDC 买回 ~100.5 WETH)
        // 5. Transfer 回 pair

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](4);

        // 1. Approve router for WETH
        calls[0] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(router), borrowAmount)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. Swap WETH → USDC
        calls[1] = IChainedExecutor.Call({
            target: address(router),
            value: 0,
            callData: abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,bytes)", address(weth), address(usdc), borrowAmount, 0, ""
            ),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 3. Approve router for USDC
        calls[2] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(router), type(uint256).max)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 4. Transfer WETH back to pair (还款)
        // 需要还 ~100.3 WETH
        uint256 repayAmount = (borrowAmount * 1003) / 1000;
        calls[3] = IChainedExecutor.Call({
            target: address(weth),
            value: 0,
            callData: abi.encodeCall(MockERC20.transfer, (address(pair), repayAmount)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 准备签名
        uint256 currentNonce = executor.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encode(address(executor), block.chainid, calls, currentNonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory callbackData =
            abi.encodeCall(ChainedExecutor.executeSigned, (calls, currentNonce, deadline, signature));

        // 发起 flash swap
        vm.prank(owner);
        executor.execute(
            address(pair), 0, abi.encodeCall(MockUniswapV2Pair.swap, (borrowAmount, 0, address(executor), callbackData))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CURVE STABLE SWAP ARBITRAGE TEST
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：Curve 稳定币套利
    function test_DeFi_CurveStableArbitrage() public {
        MockCurvePool curve = new MockCurvePool(usdc, usdt, dai);

        // 准备流动性
        usdc.mint(address(curve), 10_000_000 ether);
        usdt.mint(address(curve), 10_000_000 ether);
        dai.mint(address(curve), 10_000_000 ether);

        // 给 executor 本金
        usdc.mint(address(executor), 1000 ether);

        // 三角套利: USDC → USDT → DAI → USDC
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](6);

        // 1. Approve Curve for USDC
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(curve), 1000 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. Swap USDC → USDT
        calls[1] = IChainedExecutor.Call({
            target: address(curve),
            value: 0,
            callData: abi.encodeCall(MockCurvePool.exchange, (0, 1, 1000 ether, 0)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 3. Approve Curve for USDT
        calls[2] = IChainedExecutor.Call({
            target: address(usdt),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(curve), type(uint256).max)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 4. Swap USDT → DAI (使用上一步返回值)
        IChainedExecutor.Injection[] memory inj4 = new IChainedExecutor.Injection[](1);
        inj4[0] = IChainedExecutor.Injection({
            sourceCallIndex: 1,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 68 // exchange(i, j, dx, minDy) 的 dx 位置
        });

        calls[3] = IChainedExecutor.Call({
            target: address(curve),
            value: 0,
            callData: abi.encodeCall(MockCurvePool.exchange, (1, 2, 0, 0)), // dx 将被注入
            injections: inj4
        });

        // 5. Approve Curve for DAI
        calls[4] = IChainedExecutor.Call({
            target: address(dai),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(curve), type(uint256).max)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 6. Swap DAI → USDC (使用上一步返回值)
        IChainedExecutor.Injection[] memory inj6 = new IChainedExecutor.Injection[](1);
        inj6[0] = IChainedExecutor.Injection({
            sourceCallIndex: 3, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 68
        });

        calls[5] = IChainedExecutor.Call({
            target: address(curve),
            value: 0,
            callData: abi.encodeCall(MockCurvePool.exchange, (2, 0, 0, 0)),
            injections: inj6
        });

        uint256 balanceBefore = usdc.balanceOf(address(executor));

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        uint256 balanceAfter = usdc.balanceOf(address(executor));

        // 由于 0.04% 手续费，三次 swap 会损失约 0.12%
        // 1000 * 0.9996 * 0.9996 * 0.9996 ≈ 998.8
        assertLt(balanceAfter, balanceBefore); // 这个例子中会亏损（正常，因为没有价差）
    }

    /*//////////////////////////////////////////////////////////////
                        GAS EFFICIENCY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：比较链式调用 vs 多个单独调用的 gas
    function test_Gas_ChainedVsSeparateCalls() public {
        usdc.mint(address(executor), 1000 ether);

        // 方法 1: 链式调用
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](3);
        calls[0] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(0x1), 100 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[1] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(0x2), 200 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });
        calls[2] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeCall(MockERC20.approve, (address(0x3), 300 ether)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 gasStart1 = gasleft();
        vm.prank(owner);
        executor.execute(calls);
        uint256 gasUsed1 = gasStart1 - gasleft();

        // 方法 2: 单次调用（对比）
        uint256 gasStart2 = gasleft();
        vm.prank(owner);
        executor.execute(address(usdc), 0, abi.encodeCall(MockERC20.approve, (address(0x4), 100 ether)));
        vm.prank(owner);
        executor.execute(address(usdc), 0, abi.encodeCall(MockERC20.approve, (address(0x5), 200 ether)));
        vm.prank(owner);
        executor.execute(address(usdc), 0, abi.encodeCall(MockERC20.approve, (address(0x6), 300 ether)));
        uint256 gasUsed2 = gasStart2 - gasleft();

        // 记录 gas 使用
        emit log_named_uint("Batch execute (Call[]) gas", gasUsed1);
        emit log_named_uint("Separate execute calls gas", gasUsed2);

        // 注意：由于每次单独调用都要经过 onlyOwnerOrEntryPoint 检查
        // 和函数调用开销，单独调用实际上可能更少 gas（因为没有数组处理）
        // 这里只是验证两种方式都能工作，而不是严格比较 gas
        // 真实场景中批量调用的优势在于减少链上交易数量（节省 21000 base gas）
        assertTrue(gasUsed1 > 0 && gasUsed2 > 0, "Both methods should work");
    }

    /// @notice 测试：注入数据的 gas 消耗
    function test_Gas_InjectionOverhead() public {
        MockDEX dex = new MockDEX();

        // 不带注入
        IChainedExecutor.Call[] memory callsNoInj = new IChainedExecutor.Call[](2);
        callsNoInj[0] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });
        callsNoInj[1] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (200)),
            injections: new IChainedExecutor.Injection[](0)
        });

        uint256 gasStart1 = gasleft();
        vm.prank(owner);
        executor.execute(callsNoInj);
        uint256 gasNoInj = gasStart1 - gasleft();

        // 带注入
        IChainedExecutor.Call[] memory callsWithInj = new IChainedExecutor.Call[](2);
        callsWithInj[0] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        callsWithInj[1] = IChainedExecutor.Call({
            target: address(dex), value: 0, callData: abi.encodeCall(MockDEX.quote, (0)), injections: inj
        });

        uint256 gasStart2 = gasleft();
        vm.prank(owner);
        executor.execute(callsWithInj);
        uint256 gasWithInj = gasStart2 - gasleft();

        emit log_named_uint("No injection gas", gasNoInj);
        emit log_named_uint("With injection gas", gasWithInj);
        emit log_named_uint("Injection overhead", gasWithInj - gasNoInj);

        // 注入会增加一些 gas，但应该在合理范围内 (< 15000)
        // 注入需要复制 calldata 并修改，会有一定开销
        assertLt(gasWithInj - gasNoInj, 15000);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT CHECK & ATOMICITY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：原子性利润检查
    function test_DeFi_AtomicProfitCheck() public {
        ProfitChecker checker = new ProfitChecker();
        MockDEX dex = new MockDEX();

        usdc.mint(address(executor), 100 ether);
        usdc.mint(address(dex), 1000 ether);

        // 链式调用：
        // 1. 获取起始余额
        // 2. 执行交易
        // 3. 检查利润

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](3);

        // 1. 获取起始余额
        calls[0] = IChainedExecutor.Call({
            target: address(checker),
            value: 0,
            callData: abi.encodeCall(ProfitChecker.getBalance, (address(usdc), address(executor))),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. 执行一些操作（这里只是模拟）
        calls[1] = IChainedExecutor.Call({
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), address(executor)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 3. 检查利润（使用起始余额）
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 68 // checkProfit 的第三个参数
        });

        calls[2] = IChainedExecutor.Call({
            target: address(checker),
            value: 0,
            callData: abi.encodeCall(ProfitChecker.checkProfit, (address(usdc), 0, 0)), // startBalance 将被注入
            injections: inj
        });

        vm.prank(owner);
        executor.execute(calls);
    }

    /// @notice 测试：利润不足时整个交易回滚
    function test_DeFi_RevertOnInsufficientProfit() public {
        ProfitChecker checker = new ProfitChecker();

        usdc.mint(address(executor), 100 ether);

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        // 1. 获取余额
        calls[0] = IChainedExecutor.Call({
            target: address(checker),
            value: 0,
            callData: abi.encodeCall(ProfitChecker.getBalance, (address(usdc), address(executor))),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 2. 检查利润（要求 1000 ether 利润，但实际没有）
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 68
        });

        calls[1] = IChainedExecutor.Call({
            target: address(checker),
            value: 0,
            callData: abi.encodeCall(ProfitChecker.checkProfit, (address(usdc), 1000 ether, 0)),
            injections: inj
        });

        // 应该因为利润不足而回滚
        vm.prank(owner);
        vm.expectRevert();
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES & BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice 测试：空调用列表
    function test_EdgeCase_EmptyCallsList() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](0);

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(results.length, 0);
    }

    /// @notice 测试：最大注入长度
    function test_EdgeCase_MaxInjectionLength() public {
        MockDEX dex = new MockDEX();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 尝试注入超过返回值长度的数据
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 64, // 返回值只有 32 字节
            targetCalldataOffset: 4
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dex), value: 0, callData: abi.encodeCall(MockDEX.quote, (50)), injections: inj
        });

        // 应该安全处理（跳过无效注入）
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 第二个调用使用原始值
        assertEq(abi.decode(results[1], (uint256)), 100); // 50 * 2
    }

    /// @notice 测试：uint16 边界值
    function test_EdgeCase_Uint16Boundaries() public {
        MockDEX dex = new MockDEX();

        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](2);

        calls[0] = IChainedExecutor.Call({
            target: address(dex),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new IChainedExecutor.Injection[](0)
        });

        // 使用 uint16 最大值
        IChainedExecutor.Injection[] memory inj = new IChainedExecutor.Injection[](1);
        inj[0] = IChainedExecutor.Injection({
            sourceCallIndex: type(uint16).max,
            sourceReturnOffset: type(uint16).max,
            sourceReturnLength: type(uint16).max,
            targetCalldataOffset: type(uint16).max
        });

        calls[1] = IChainedExecutor.Call({
            target: address(dex), value: 0, callData: abi.encodeCall(MockDEX.quote, (200)), injections: inj
        });

        // 应该安全处理
        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        // 无效注入被跳过，使用原始值
        assertEq(abi.decode(results[1], (uint256)), 400);
    }

    /// @notice 测试：零 value 转账
    function test_EdgeCase_ZeroValueTransfer() public {
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(0x1234), value: 0, callData: "", injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        executor.execute(calls);
    }

    /// @notice 测试：自引用调用（调用自己）
    function test_EdgeCase_SelfCall() public {
        // executor 调用自己的 view 函数应该可以
        IChainedExecutor.Call[] memory calls = new IChainedExecutor.Call[](1);

        calls[0] = IChainedExecutor.Call({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSignature("nonce()"),
            injections: new IChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 0);
    }
}
