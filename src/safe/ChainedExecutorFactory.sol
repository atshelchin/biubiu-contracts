// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainedExecutor} from "./ChainedExecutor.sol";

/// @title ChainedExecutorFactory
/// @notice 使用 CREATE2 确定性部署 ChainedExecutor 智能合约账户
/// @author BiuBiu
contract ChainedExecutorFactory {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-4337 EntryPoint 地址
    address public immutable entryPoint;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _entryPoint ERC-4337 EntryPoint 合约地址
    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice 创建新的 ChainedExecutor 账户
    /// @param owner 账户所有者
    /// @param salt 用于 CREATE2 的盐值
    /// @return account 新创建的账户地址
    function createAccount(address owner, uint256 salt) external returns (address account) {
        bytes32 finalSalt = keccak256(abi.encodePacked(owner, salt));

        // 检查是否已存在
        account = getAddress(owner, salt);
        if (account.code.length > 0) {
            return account;
        }

        // CREATE2 部署
        account = address(new ChainedExecutor{salt: finalSalt}(entryPoint, owner));

        emit AccountCreated(account, owner, salt);
    }

    /// @notice 计算账户地址 (不部署)
    /// @param owner 账户所有者
    /// @param salt 盐值
    /// @return 预计的账户地址
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes32 finalSalt = keccak256(abi.encodePacked(owner, salt));

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                finalSalt,
                keccak256(abi.encodePacked(type(ChainedExecutor).creationCode, abi.encode(entryPoint, owner)))
            )
        );

        return address(uint160(uint256(hash)));
    }

    /// @notice 获取创建账户的 initCode (用于 ERC-4337 UserOp)
    /// @param owner 账户所有者
    /// @param salt 盐值
    /// @return initCode 可直接用于 UserOperation.initCode
    function getInitCode(address owner, uint256 salt) external view returns (bytes memory) {
        return abi.encodePacked(address(this), abi.encodeCall(this.createAccount, (owner, salt)));
    }
}
