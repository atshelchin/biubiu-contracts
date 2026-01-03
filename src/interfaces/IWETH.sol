// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IWETH
 * @notice Interface for Wrapped ETH contract
 * @dev Standard WETH interface with depositAndApprove extension
 */
interface IWETH {
    // ============ Events ============

    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event DepositAndApprove(address indexed account, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ============ ERC20 Standard ============

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    // ============ WETH Functions ============

    /**
     * @notice Deposit native coin and receive WETH
     */
    function deposit() external payable;

    /**
     * @notice Deposit native coin, receive WETH, and approve spender in one transaction
     * @param spender The address to approve for spending the deposited WETH
     */
    function depositAndApprove(address spender) external payable;

    /**
     * @notice Withdraw all WETH and receive native coin
     */
    function withdraw() external;

    /**
     * @notice Withdraw a specific amount of WETH and receive native coin
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external;
}
