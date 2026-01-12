// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IChainedExecutor} from "./IChainedExecutor.sol";

/// @title ChainedExecutor
/// @notice 极简智能合约账户：支持 ERC-4337 和 EOA 双模式，链式交易执行
/// @dev 前一笔交易的返回值可动态注入后续交易，适用于复杂 DeFi 套利
/// @author BiuBiu
contract ChainedExecutor is IChainedExecutor {
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
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _entryPoint, address _owner) {
        entryPoint = _entryPoint;
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev 仅允许 owner 调用
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @dev 仅允许 EntryPoint 调用 (ERC-4337 执行函数)
    /// @notice 安全性由 validateUserOp 的签名验证保证
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert Unauthorized();
        _;
    }

    /// @dev 仅允许 owner 或 EntryPoint 调用
    modifier onlyOwnerOrEntryPoint() {
        if (msg.sender != owner && msg.sender != entryPoint) revert Unauthorized();
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
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
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

    /// @notice 执行单个调用 (ERC-4337 标准接口)
    /// @dev owner 直接调用或 EntryPoint 通过 ERC-4337 流程调用
    function execute(address target, uint256 value, bytes calldata data) external payable onlyOwnerOrEntryPoint {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    /// @notice 链式执行 (核心功能)
    /// @dev owner 直接调用或 EntryPoint 通过 ERC-4337 流程调用
    /// @dev 支持动态参数注入，前一笔交易返回值可注入后续交易
    function execute(Call[] calldata calls) external payable onlyOwnerOrEntryPoint returns (bytes[] memory results) {
        results = _executeInternal(calls);
        emit Executed(calls.length, keccak256(abi.encodePacked(block.timestamp, block.prevrandao, nonce)));
    }

    /// @notice 带签名的链式执行 (用于闪电贷回调等场景)
    /// @dev 任何人可调用，但需要 owner 签名授权
    /// @param calls 调用列表
    /// @param _nonce 防重放 nonce
    /// @param deadline 签名过期时间 (0 表示永不过期)
    /// @param signature owner 的签名
    function executeSigned(Call[] calldata calls, uint256 _nonce, uint256 deadline, bytes calldata signature)
        external
        payable
        returns (bytes[] memory results)
    {
        // 检查过期时间 (deadline=0 表示永不过期)
        if (deadline != 0 && block.timestamp > deadline) revert InvalidSignature();

        // 构造待签名消息
        bytes32 hash = keccak256(abi.encode(address(this), block.chainid, calls, _nonce, deadline));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        // 验证签名 (先验证签名再改变状态)
        if (!_validateSignature(ethSignedHash, signature)) revert InvalidSignature();

        // 验证并递增 nonce
        if (_nonce != nonce) revert InvalidNonce();
        ++nonce;

        // 执行
        results = _executeInternal(calls);
        emit Executed(calls.length, keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _nonce)));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _executeInternal(Call[] calldata calls) internal returns (bytes[] memory results) {
        uint256 len = calls.length;
        results = new bytes[](len);

        for (uint256 i; i < len; ++i) {
            Call calldata c = calls[i];

            bytes memory finalCallData =
                c.injections.length > 0 ? _applyInjections(c.callData, c.injections, results) : c.callData;

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
            (bool success, bytes memory result) =
                owner.staticcall(
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
