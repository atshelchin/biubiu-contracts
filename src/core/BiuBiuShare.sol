// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBiuBiuShare} from "../interfaces/IBiuBiuShare.sol";

/**
 * @title BiuBiuShare
 * @notice ERC20 DAO token for BiuBiuVault revenue distribution
 * @dev Fixed supply minted to founder at deployment
 */
contract BiuBiuShare is IBiuBiuShare {
    string public constant name = "BiuBiu Share";
    string public constant symbol = "BBS";
    uint8 public constant decimals = 0;
    uint256 public constant totalSupply = 1_000_000;
    address public constant FOUNDER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    constructor() {
        balanceOf[FOUNDER] = totalSupply;
        emit Transfer(address(0), FOUNDER, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
        }

        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }
}
