// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ChainedExecutor
/// @notice 极简智能合约账户：支持 ERC-4337 和 EOA 双模式，链式交易执行
/// @dev 前一笔交易的返回值可动态注入后续交易，适用于复杂 DeFi 套利
/// @author BiuBiu
contract ChainedExecutor {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice 参数注入规则
    struct Injection {
        uint16 sourceCallIndex;
        uint16 sourceReturnOffset;
        uint16 sourceReturnLength;
        uint16 targetCalldataOffset;
    }

    /// @notice 单个调用定义
    struct Call {
        address target;
        uint256 value;
        bytes callData;
        Injection[] injections;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice 账户所有者
    address public owner;

    /// @notice ERC-4337 EntryPoint 地址
    address public immutable entryPoint;

    /// @notice 防重放 nonce
    uint256 public nonce;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event Executed(uint256 callCount, bytes32 indexed executionId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error CallFailed(uint256 index, bytes reason);
    error InvalidSignature();
    error InvalidNonce();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _entryPoint, address _owner) {
        entryPoint = _entryPoint;
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwnerOrEntryPoint() {
        if (msg.sender != owner && msg.sender != entryPoint) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         ERC-4337 INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-4337 验证 UserOperation
    /// @dev 由 EntryPoint 调用
    /// @param userOp 用户操作
    /// @param userOpHash 操作哈希
    /// @param missingAccountFunds 需要支付给 EntryPoint 的 gas 费
    /// @return validationData 0 表示验证成功
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        if (msg.sender != entryPoint) revert Unauthorized();

        // 验证签名 (支持 EOA 和智能合约账户)
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        if (!_validateSignature(hash, userOp.signature)) {
            return 1; // SIG_VALIDATION_FAILED
        }

        // 验证 nonce
        if (userOp.nonce != nonce) {
            return 1;
        }
        ++nonce;

        // 支付 gas 费给 EntryPoint
        if (missingAccountFunds > 0) {
            (bool ok,) = entryPoint.call{value: missingAccountFunds}("");
            (ok); // 忽略失败，EntryPoint 会处理
        }

        return 0; // 验证成功
    }

    /*//////////////////////////////////////////////////////////////
                            CORE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice 执行链式调用 (EOA 或 EntryPoint)
    function execute(Call[] calldata calls) external payable onlyOwnerOrEntryPoint returns (bytes[] memory results) {
        results = _executeInternal(calls);
        emit Executed(calls.length, keccak256(abi.encodePacked(block.timestamp, block.prevrandao, nonce)));
    }

    /// @notice 执行链式调用 (开放调用，用于闪电贷回调)
    function executeOpen(Call[] calldata calls) external payable returns (bytes[] memory results) {
        results = _executeInternal(calls);
    }

    /// @notice 简单执行单个调用 (ERC-4337 标准接口)
    function execute(address target, uint256 value, bytes calldata data) external payable onlyOwnerOrEntryPoint {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    /// @notice 批量执行 (ERC-4337 标准接口)
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable onlyOwnerOrEntryPoint {
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(datas[i]);
            if (!ok) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _executeInternal(Call[] calldata calls) internal returns (bytes[] memory results) {
        uint256 len = calls.length;
        results = new bytes[](len);

        for (uint256 i; i < len; ++i) {
            Call calldata c = calls[i];

            bytes memory finalCallData = c.injections.length > 0
                ? _applyInjections(c.callData, c.injections, results)
                : c.callData;

            (bool ok, bytes memory ret) = c.target.call{value: c.value}(finalCallData);
            if (!ok) revert CallFailed(i, ret);

            results[i] = ret;
        }
    }

    function _applyInjections(
        bytes calldata originalCallData,
        Injection[] calldata injections,
        bytes[] memory previousResults
    ) internal pure returns (bytes memory result) {
        result = originalCallData;

        for (uint256 i; i < injections.length; ++i) {
            Injection calldata inj = injections[i];

            if (inj.sourceCallIndex >= previousResults.length) continue;
            bytes memory src = previousResults[inj.sourceCallIndex];
            if (src.length == 0) continue;
            if (inj.sourceReturnOffset + inj.sourceReturnLength > src.length) continue;
            if (inj.targetCalldataOffset + inj.sourceReturnLength > result.length) continue;

            for (uint256 j; j < inj.sourceReturnLength; ++j) {
                result[inj.targetCalldataOffset + j] = src[inj.sourceReturnOffset + j];
            }
        }
    }

    /// @notice 验证签名 (支持 EOA 和智能合约账户)
    /// @dev EOA: ECDSA 签名验证; 合约: ERC-1271 验证
    function _validateSignature(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        // 检查 owner 是否是合约
        if (owner.code.length > 0) {
            // ERC-1271: 调用合约的 isValidSignature
            (bool success, bytes memory result) = owner.staticcall(
                abi.encodeWithSelector(0x1626ba7e, hash, signature) // isValidSignature(bytes32,bytes)
            );
            return success && result.length >= 32 && abi.decode(result, (bytes4)) == 0x1626ba7e;
        } else {
            // EOA: ECDSA 签名验证
            return _recoverSigner(hash, signature) == owner;
        }
    }

    /// @notice ECDSA 签名恢复
    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;

        return ecrecover(hash, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setOwner(address newOwner) external onlyOwner {
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
                             ETH HANDLING
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok);
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        (bool ok,) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-165 SUPPORT
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0x60fc6b6e; // IAccount (ERC-4337)
    }
}

/*//////////////////////////////////////////////////////////////
                        ERC-4337 TYPES
//////////////////////////////////////////////////////////////*/

/// @notice ERC-4337 v0.7 PackedUserOperation
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}
