// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IChainedExecutor
/// @notice 链式执行器接口
/// @author BiuBiu
interface IChainedExecutor {
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
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice 获取账户所有者
    function owner() external view returns (address);

    /// @notice 获取 EntryPoint 地址
    function entryPoint() external view returns (address);

    /// @notice 获取当前 nonce
    function nonce() external view returns (uint256);

    /// @notice ERC-165 接口支持查询
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);

    /*//////////////////////////////////////////////////////////////
                            CORE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice 执行单个调用 (ERC-4337 标准接口)
    /// @param target 目标合约地址
    /// @param value 发送的 ETH 数量
    /// @param data 调用数据
    function execute(address target, uint256 value, bytes calldata data) external payable;

    /// @notice 链式执行 (核心功能)
    /// @param calls 调用列表
    /// @return results 每个调用的返回值
    function execute(Call[] calldata calls) external payable returns (bytes[] memory results);

    /// @notice 带签名的链式执行 (用于闪电贷回调等场景)
    /// @param calls 调用列表
    /// @param _nonce 防重放 nonce
    /// @param deadline 签名过期时间 (0 表示永不过期)
    /// @param signature owner 的签名
    /// @return results 每个调用的返回值
    function executeSigned(Call[] calldata calls, uint256 _nonce, uint256 deadline, bytes calldata signature)
        external
        payable
        returns (bytes[] memory results);

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice 设置新的所有者
    /// @param newOwner 新所有者地址
    function setOwner(address newOwner) external;

    /// @notice 提取 ETH
    /// @param to 接收地址
    /// @param amount 提取数量
    function withdrawETH(address to, uint256 amount) external;

    /// @notice 提取 ERC20 代币
    /// @param token 代币合约地址
    /// @param to 接收地址
    /// @param amount 提取数量
    function withdrawToken(address token, address to, uint256 amount) external;
}
