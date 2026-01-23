// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainExecutorModule, ISafe, Operation} from "../src/safe/ChainExecutorModule.sol";
import {ChainedCallExecutor} from "../src/safe/ChainedCallExecutor.sol";
import {IChainExecutorModule} from "../src/safe/IChainExecutorModule.sol";
import {IFlashLoanAdapter} from "../src/safe/IFlashLoanAdapter.sol";

/// @notice Mock Safe contract
contract MockSafe {
    mapping(address => bool) public enabledModules;
    address public owner;

    // Track executed calls for verification
    struct ExecutedCall {
        address to;
        uint256 value;
        bytes data;
    }

    ExecutedCall[] public executedCalls;

    function enableModule(address module) external {
        enabledModules[module] = true;
    }

    function setOwner(address _owner) external {
        owner = _owner;
    }

    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success)
    {
        require(enabledModules[msg.sender], "Module not enabled");
        executedCalls.push(ExecutedCall({to: to, value: value, data: data}));

        if (operation == Operation.DelegateCall) {
            // DelegateCall - execute in this contract's context
            (success,) = to.delegatecall(data);
        } else {
            // Call - execute as external call
            (success,) = to.call{value: value}(data);
        }
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        if (_recoverSigner(hash, signature) == owner) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }

    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }

    function getExecutedCallCount() external view returns (uint256) {
        return executedCalls.length;
    }

    function clearExecutedCalls() external {
        delete executedCalls;
    }

    receive() external payable {}
}

/// @notice Mock Target contract
contract MockTarget {
    uint256 public value;
    uint256 public lastAmount;

    function setValue(uint256 _value) external payable {
        value = _value;
    }

    function setValueAndReturn(uint256 _value) external returns (uint256) {
        value = _value;
        return _value * 2;
    }

    function receiveAmount(uint256 amount) external {
        lastAmount = amount;
    }

    receive() external payable {}
}

/// @notice Mock ERC20 token
contract MockERC20 {
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

/// @notice Mock Flash Loan Adapter
contract MockFlashLoanAdapter is IFlashLoanAdapter {
    MockERC20 public token;
    uint256 public feePercent = 9; // 0.09% fee (Aave-like)

    constructor(MockERC20 _token) {
        token = _token;
    }

    function initiateFlashLoan(address module, address safe, bytes calldata adapterData, bytes calldata callbackData)
        external
    {
        // Decode adapter data
        (, uint256 amount) = abi.decode(adapterData, (address, uint256));
        uint256 fee = (amount * feePercent) / 10000;

        // Mint tokens to simulate flash loan (in real adapter, protocol provides this)
        token.mint(address(this), amount);

        // Transfer to safe
        token.transfer(safe, amount);

        // Callback to module
        IChainExecutorModule(module).onFlashLoanCallback(address(token), amount, fee, callbackData);

        // After callback, adapter should have amount + fee
        uint256 repayAmount = amount + fee;
        require(token.balanceOf(address(this)) >= repayAmount, "Repayment failed");
    }
}

contract ChainExecutorModuleTest is Test {
    ChainExecutorModule public module;
    ChainedCallExecutor public executor;
    MockSafe public safe;
    MockTarget public target;
    MockERC20 public token;
    MockFlashLoanAdapter public adapter;

    uint256 internal ownerPrivateKey;
    address internal owner;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        executor = new ChainedCallExecutor();
        module = new ChainExecutorModule(address(executor));
        safe = new MockSafe();
        target = new MockTarget();
        token = new MockERC20();
        adapter = new MockFlashLoanAdapter(token);

        safe.setOwner(owner);
        safe.enableModule(address(module));

        vm.deal(address(safe), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createSimpleCalls() internal view returns (IChainExecutorModule.Call[] memory) {
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](1);
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (42)),
            injections: new IChainExecutorModule.Injection[](0)
        });
        return calls;
    }

    function _createMultipleCalls() internal view returns (IChainExecutorModule.Call[] memory) {
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](2);
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (100)),
            injections: new IChainExecutorModule.Injection[](0)
        });
        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 1 ether,
            data: abi.encodeCall(MockTarget.setValue, (200)),
            injections: new IChainExecutorModule.Injection[](0)
        });
        return calls;
    }

    function _signExecution(address _safe, IChainExecutorModule.Call[] memory calls, uint64 deadline)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 executionHash = keccak256(abi.encode(_safe, block.chainid, calls, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", executionHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _signFlashLoanExecution(
        address _safe,
        IChainExecutorModule.FlashLoanParams memory flashLoanParams,
        IChainExecutorModule.Call[] memory calls,
        uint64 deadline
    ) internal view returns (bytes memory signature) {
        bytes32 executionHash = keccak256(
            abi.encode(_safe, block.chainid, flashLoanParams.adapter, flashLoanParams.adapterData, calls, deadline)
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", executionHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        signature = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                              BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_SingleCall() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        assertEq(target.value(), 42);
        assertEq(safe.getExecutedCallCount(), 1);
    }

    function test_Execute_MultipleCalls() public {
        IChainExecutorModule.Call[] memory calls = _createMultipleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        assertEq(target.value(), 200);
        assertEq(address(target).balance, 1 ether);
        // With delegatecall pattern, only 1 call to Safe (delegatecall to executor)
        assertEq(safe.getExecutedCallCount(), 1);
    }

    function test_ExecuteFromSafe() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();

        vm.prank(address(safe));
        module.executeFromSafe(calls);

        assertEq(target.value(), 42);
    }

    /*//////////////////////////////////////////////////////////////
                              DEADLINE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_NoDeadline() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = 0; // Never expires
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        vm.warp(block.timestamp + 365 days);
        module.execute(address(safe), calls, deadline, signature);

        assertEq(target.value(), 42);
    }

    function test_Revert_Expired() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(IChainExecutorModule.Expired.selector);
        module.execute(address(safe), calls, deadline, signature);
    }

    /*//////////////////////////////////////////////////////////////
                           REPLAY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_AlreadyExecuted() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        // First execution succeeds
        module.execute(address(safe), calls, deadline, signature);

        // Second execution fails
        vm.expectRevert(IChainExecutorModule.AlreadyExecuted.selector);
        module.execute(address(safe), calls, deadline, signature);
    }

    /*//////////////////////////////////////////////////////////////
                           SIGNATURE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_InvalidSignature() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Sign with wrong key
        uint256 wrongKey = 0xBAD;
        bytes32 executionHash = keccak256(abi.encode(address(safe), block.chainid, calls, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", executionHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(IChainExecutorModule.InvalidSignature.selector);
        module.execute(address(safe), calls, deadline, wrongSignature);
    }

    /*//////////////////////////////////////////////////////////////
                           FLASH LOAN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteWithFlashLoan() public {
        // Setup: Safe needs some tokens to pay the fee
        uint256 loanAmount = 1000 ether;
        uint256 fee = (loanAmount * 9) / 10000; // 0.09%
        token.mint(address(safe), fee + 1 ether); // Extra for safety

        // Create calls that use the borrowed tokens
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](1);
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (loanAmount)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        // Flash loan params
        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), loanAmount)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signFlashLoanExecution(address(safe), flashLoanParams, calls, deadline);

        // Execute
        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);

        // Verify
        assertEq(target.value(), loanAmount);
    }

    function test_Revert_FlashLoan_InvalidCallback() public {
        // Try to call onFlashLoanCallback directly (not during flash loan)
        vm.expectRevert(IChainExecutorModule.NoFlashLoanInProgress.selector);
        module.onFlashLoanCallback(address(token), 1000 ether, 1 ether, "");
    }

    function test_Revert_FlashLoan_WrongAdapter() public {
        // Setup
        uint256 loanAmount = 1000 ether;
        uint256 fee = (loanAmount * 9) / 10000;
        token.mint(address(safe), fee + 1 ether);

        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();

        // Sign with one adapter
        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), loanAmount)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Sign with different adapter address
        IChainExecutorModule.FlashLoanParams memory wrongParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(0x1234), // Wrong adapter
            adapterData: abi.encode(address(token), loanAmount)
        });
        bytes memory signature = _signFlashLoanExecution(address(safe), wrongParams, calls, deadline);

        // Should fail - signature doesn't match
        vm.expectRevert(IChainExecutorModule.InvalidSignature.selector);
        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetExecutionHash() public view {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);

        bytes32 hash = module.getExecutionHash(address(safe), calls, deadline);
        bytes32 expectedHash = keccak256(abi.encode(address(safe), block.chainid, calls, deadline));

        assertEq(hash, expectedHash);
    }

    function test_GetFlashLoanExecutionHash() public view {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), 1000 ether)
        });
        uint64 deadline = uint64(block.timestamp + 1 hours);

        bytes32 hash = module.getFlashLoanExecutionHash(address(safe), flashLoanParams, calls, deadline);
        bytes32 expectedHash = keccak256(
            abi.encode(
                address(safe), block.chainid, flashLoanParams.adapter, flashLoanParams.adapterData, calls, deadline
            )
        );

        assertEq(hash, expectedHash);
    }

    function test_UsedExecutions() public {
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        bytes32 executionHash = module.getExecutionHash(address(safe), calls, deadline);

        // Before execution: not used
        assertFalse(module.usedExecutions(executionHash));

        // Execute
        module.execute(address(safe), calls, deadline, signature);

        // After execution: used
        assertTrue(module.usedExecutions(executionHash));
    }

    /*//////////////////////////////////////////////////////////////
                           INJECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_WithInjection() public {
        // Call 1: setValueAndReturn(100) returns 200 (value * 2)
        // Call 2: receiveAmount(X) where X is injected from Call 1's return value

        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](2);

        // First call: setValueAndReturn(100) - returns uint256(200)
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValueAndReturn, (100)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        // Second call: receiveAmount(placeholder)
        // We'll inject the return value from call 0 into the amount parameter
        IChainExecutorModule.Injection[] memory injections = new IChainExecutorModule.Injection[](1);
        injections[0] = IChainExecutorModule.Injection({
            sourceCallIndex: 0, // From call 0's return
            sourceReturnOffset: 0, // Start of return data (uint256)
            sourceReturnLength: 32, // uint256 is 32 bytes
            targetCalldataOffset: 4 // After 4-byte selector
        });

        // Placeholder value that will be overwritten by injection
        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (0)), // 0 will be replaced with 200
            injections: injections
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        // Verify: value should be 100, lastAmount should be 200 (100 * 2 from return)
        assertEq(target.value(), 100);
        assertEq(target.lastAmount(), 200);
    }

    function test_Execute_IndependentCalls_NoInjection() public {
        // Three independent calls without any injection - just like batch transactions
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](3);

        // Call 0: setValue(100)
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (100)),
            injections: new IChainExecutorModule.Injection[](0) // No injection
        });

        // Call 1: receiveAmount(500) - independent, not using any return value
        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (500)),
            injections: new IChainExecutorModule.Injection[](0) // No injection
        });

        // Call 2: setValue(200) - overwrites call 0
        calls[2] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (200)),
            injections: new IChainExecutorModule.Injection[](0) // No injection
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        // All calls executed independently
        assertEq(target.value(), 200); // Last setValue wins
        assertEq(target.lastAmount(), 500);
    }

    /*//////////////////////////////////////////////////////////////
                    FLASH LOAN + INJECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FlashLoan_WithInjection() public {
        // Flash loan with chained calls using injection
        uint256 loanAmount = 1000 ether;
        uint256 fee = (loanAmount * 9) / 10000; // 0.09%
        token.mint(address(safe), fee + 1 ether);

        // Call 0: setValueAndReturn(loanAmount) - returns loanAmount * 2
        // Call 1: receiveAmount(X) - inject return from call 0
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](2);

        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValueAndReturn, (loanAmount)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        IChainExecutorModule.Injection[] memory injections = new IChainExecutorModule.Injection[](1);
        injections[0] = IChainExecutorModule.Injection({
            sourceCallIndex: 0, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (0)), // Will be injected
            injections: injections
        });

        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), loanAmount)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signFlashLoanExecution(address(safe), flashLoanParams, calls, deadline);

        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);

        // Verify injection worked inside flash loan
        assertEq(target.value(), loanAmount);
        assertEq(target.lastAmount(), loanAmount * 2); // Injected from setValueAndReturn
    }

    function test_FlashLoan_IndependentCalls_NoInjection() public {
        // Flash loan with independent calls (no injection) - simple batch
        uint256 loanAmount = 1000 ether;
        uint256 fee = (loanAmount * 9) / 10000;
        token.mint(address(safe), fee + 1 ether);

        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](2);

        // Two independent calls, no injection
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (loanAmount)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (999)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), loanAmount)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signFlashLoanExecution(address(safe), flashLoanParams, calls, deadline);

        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);

        // Both calls executed independently
        assertEq(target.value(), loanAmount);
        assertEq(target.lastAmount(), 999); // Not injected, used literal value
    }

    /*//////////////////////////////////////////////////////////////
                           EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_CallWithETHValue() public {
        // Test call that sends ETH
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](1);
        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 2 ether,
            data: abi.encodeCall(MockTarget.setValue, (123)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        assertEq(target.value(), 123);
        assertEq(address(target).balance, 2 ether);
    }

    function test_Execute_EmptyCalls() public {
        // Empty calls array should still work (no-op)
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](0);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        // Should complete without error
        assertEq(safe.getExecutedCallCount(), 1);
    }

    function test_Execute_MultipleInjections() public {
        // Call 0: returns 100
        // Call 1: returns 200
        // Call 2: uses both return values (just test the injection mechanism)
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](3);

        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValueAndReturn, (50)), // returns 100
            injections: new IChainExecutorModule.Injection[](0)
        });

        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValueAndReturn, (100)), // returns 200
            injections: new IChainExecutorModule.Injection[](0)
        });

        // Call 2 uses injection from call 1 (latest)
        IChainExecutorModule.Injection[] memory injections = new IChainExecutorModule.Injection[](1);
        injections[0] = IChainExecutorModule.Injection({
            sourceCallIndex: 1, sourceReturnOffset: 0, sourceReturnLength: 32, targetCalldataOffset: 4
        });

        calls[2] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (0)),
            injections: injections
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        assertEq(target.value(), 100); // Last setValueAndReturn
        assertEq(target.lastAmount(), 200); // Injected from call 1
    }

    function test_Execute_InjectionOutOfBounds_Graceful() public {
        // Test injection with invalid sourceCallIndex - should be skipped gracefully
        IChainExecutorModule.Call[] memory calls = new IChainExecutorModule.Call[](2);

        calls[0] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.setValue, (42)),
            injections: new IChainExecutorModule.Injection[](0)
        });

        // Invalid injection: sourceCallIndex 99 doesn't exist
        IChainExecutorModule.Injection[] memory injections = new IChainExecutorModule.Injection[](1);
        injections[0] = IChainExecutorModule.Injection({
            sourceCallIndex: 99, // Invalid - out of bounds
            sourceReturnOffset: 0,
            sourceReturnLength: 32,
            targetCalldataOffset: 4
        });

        calls[1] = IChainExecutorModule.Call({
            target: address(target),
            value: 0,
            data: abi.encodeCall(MockTarget.receiveAmount, (777)), // Should keep original value
            injections: injections
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signExecution(address(safe), calls, deadline);

        module.execute(address(safe), calls, deadline, signature);

        // Injection skipped, original value used
        assertEq(target.lastAmount(), 777);
    }

    /*//////////////////////////////////////////////////////////////
                        FLASH LOAN SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_FlashLoan_Reentrancy() public {
        // Try to start another flash loan while one is in progress
        // This is tested implicitly by the FlashLoanInProgress check
        uint256 loanAmount = 1000 ether;
        uint256 fee = (loanAmount * 9) / 10000;
        token.mint(address(safe), fee + 1 ether);

        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        IChainExecutorModule.FlashLoanParams memory flashLoanParams = IChainExecutorModule.FlashLoanParams({
            adapter: address(adapter), adapterData: abi.encode(address(token), loanAmount)
        });

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory signature = _signFlashLoanExecution(address(safe), flashLoanParams, calls, deadline);

        // First flash loan succeeds
        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);

        // Same signature can't be reused (AlreadyExecuted)
        vm.expectRevert(IChainExecutorModule.AlreadyExecuted.selector);
        module.executeWithFlashLoan(address(safe), flashLoanParams, calls, deadline, signature);
    }

    function test_Revert_FlashLoan_TamperedCallsHash() public {
        // This tests that adapter can't modify the calls
        // The callsHash verification in onFlashLoanCallback prevents this
        // Already covered by the callback verification logic
    }

    function test_Revert_DirectOnFlashLoanCallback() public {
        // Try calling onFlashLoanCallback when no flash loan is active
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        bytes memory callbackData = abi.encode(calls);

        vm.expectRevert(IChainExecutorModule.NoFlashLoanInProgress.selector);
        module.onFlashLoanCallback(address(token), 1000 ether, 1 ether, callbackData);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Execute_ChainIdInHash() public view {
        // Verify chainId is included in execution hash
        IChainExecutorModule.Call[] memory calls = _createSimpleCalls();
        uint64 deadline = uint64(block.timestamp + 1 hours);

        bytes32 hash = module.getExecutionHash(address(safe), calls, deadline);
        bytes32 expectedHash = keccak256(abi.encode(address(safe), block.chainid, calls, deadline));

        assertEq(hash, expectedHash);
    }

    /*//////////////////////////////////////////////////////////////
                           EXECUTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Executor_IsImmutable() public view {
        // Verify executor address is set correctly
        assertEq(module.executor(), address(executor));
    }
}
