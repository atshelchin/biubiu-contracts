// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainedExecutor, PackedUserOperation} from "../src/safe/ChainedExecutor.sol";
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
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](1);

        calls[0] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new ChainedExecutor.Injection[](0)
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_Execute_AsEntryPoint() public {
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](1);

        calls[0] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new ChainedExecutor.Injection[](0)
        });

        vm.prank(entryPoint);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
    }

    function test_Execute_RevertUnauthorized() public {
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](0);

        vm.prank(address(0xBAD));
        vm.expectRevert(ChainedExecutor.Unauthorized.selector);
        executor.execute(calls);
    }

    /*//////////////////////////////////////////////////////////////
                         CHAINED EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InjectionChain() public {
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](3);

        // Call 0: quote(100) → 200
        calls[0] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new ChainedExecutor.Injection[](0)
        });

        // Call 1: quote(result[0]) → 400
        ChainedExecutor.Injection[] memory inj1 = new ChainedExecutor.Injection[](1);
        inj1[0] = ChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = ChainedExecutor.Call({
            target: address(dexB),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (0)),
            injections: inj1
        });

        // Call 2: quote(result[1]) → 800
        ChainedExecutor.Injection[] memory inj2 = new ChainedExecutor.Injection[](1);
        inj2[0] = ChainedExecutor.Injection({
            sourceCallIndex: 1,
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[2] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (0)),
            injections: inj2
        });

        vm.prank(owner);
        bytes[] memory results = executor.execute(calls);

        assertEq(abi.decode(results[0], (uint256)), 200);
        assertEq(abi.decode(results[1], (uint256)), 400);
        assertEq(abi.decode(results[2], (uint256)), 800);
    }

    function test_ExtractMultipleReturns() public {
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](2);

        // getValues(10) → (20, 30, addr)
        calls[0] = ChainedExecutor.Call({
            target: address(multi),
            value: 0,
            callData: abi.encodeCall(MockMultiReturn.getValues, (10)),
            injections: new ChainedExecutor.Injection[](0)
        });

        // 使用第二个返回值 (30)
        ChainedExecutor.Injection[] memory inj = new ChainedExecutor.Injection[](1);
        inj[0] = ChainedExecutor.Injection({
            sourceCallIndex: 0,
            sourceReturnOffset: 32, // 第二个返回值
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (0)),
            injections: inj
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)));
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
        vm.expectRevert(ChainedExecutor.Unauthorized.selector);
        executor.validateUserOp(userOp, userOpHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         STANDARD EXECUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteSingle() public {
        vm.prank(owner);
        executor.execute(address(dexA), 0, abi.encodeCall(MockDEX.quote, (100)));
    }

    function test_ExecuteBatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        targets[0] = address(dexA);
        targets[1] = address(dexB);
        values[0] = 0;
        values[1] = 0;
        datas[0] = abi.encodeCall(MockDEX.quote, (100));
        datas[1] = abi.encodeCall(MockDEX.quote, (200));

        vm.prank(owner);
        executor.executeBatch(targets, values, datas);
    }

    /*//////////////////////////////////////////////////////////////
                            MISC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteOpen() public {
        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](1);

        calls[0] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (50)),
            injections: new ChainedExecutor.Injection[](0)
        });

        // 任何人都可以调用
        vm.prank(address(0xBEEF));
        bytes[] memory results = executor.executeOpen(calls);

        assertEq(abi.decode(results[0], (uint256)), 100);
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

        ChainedExecutor.Call[] memory calls = new ChainedExecutor.Call[](1);
        calls[0] = ChainedExecutor.Call({
            target: address(dexA),
            value: 0,
            callData: abi.encodeCall(MockDEX.quote, (100)),
            injections: new ChainedExecutor.Injection[](0)
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
}
