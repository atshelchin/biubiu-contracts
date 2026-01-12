// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IChainedExecutorFactory
/// @notice ChainedExecutor 工厂接口
/// @author BiuBiu
interface IChainedExecutorFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice 获取 EntryPoint 地址
    function entryPoint() external view returns (address);

    /// @notice 计算账户地址 (不部署)
    /// @param owner 账户所有者
    /// @param salt 盐值
    /// @return 预计的账户地址
    function getAddress(address owner, uint256 salt) external view returns (address);

    /// @notice 获取创建账户的 initCode (用于 ERC-4337 UserOp)
    /// @param owner 账户所有者
    /// @param salt 盐值
    /// @return initCode 可直接用于 UserOperation.initCode
    function getInitCode(address owner, uint256 salt) external view returns (bytes memory);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice 创建新的 ChainedExecutor 账户
    /// @param owner 账户所有者
    /// @param salt 用于 CREATE2 的盐值
    /// @return account 新创建的账户地址
    function createAccount(address owner, uint256 salt) external returns (address account);
}
