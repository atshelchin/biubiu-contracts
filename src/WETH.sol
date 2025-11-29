// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title WETH with Approve on Deposit
 * @notice Wrapped ETH contract with additional functionality to approve spender during deposit
 * @dev Implements ERC20 standard with depositAndApprove function
 */
contract WETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event DepositAndApprove(address indexed account, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Deposit native coin and receive WETH
     */
    function deposit() public payable {
        require(msg.value > 0, "WETH: deposit amount must be greater than 0");
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    /**
     * @notice Deposit native coin, receive WETH, and approve spender in one transaction
     * @param spender The address to approve for spending the deposited WETH
     * @dev The approval amount is accumulated with existing allowance
     */
    function depositAndApprove(address spender) public payable {
        require(msg.value > 0, "WETH: deposit amount must be greater than 0");
        require(spender != address(0), "WETH: approve to the zero address");

        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        allowance[msg.sender][spender] += msg.value;

        emit DepositAndApprove(msg.sender, spender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
    }

    /**
     * @notice Withdraw all WETH and receive native coin
     * @dev Uses CEI (Checks-Effects-Interactions) pattern for reentrancy protection
     */
    function withdraw() public {
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "WETH: no balance to withdraw");

        balanceOf[msg.sender] = 0;
        totalSupply -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "WETH: ETH transfer failed");

        emit Withdrawal(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @notice Transfer WETH to another address
     * @param to The recipient address
     * @param value The amount to transfer
     */
    function transfer(address to, uint256 value) public returns (bool) {
        require(to != address(0), "WETH: transfer to the zero address");
        require(balanceOf[msg.sender] >= value, "WETH: insufficient balance");

        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Approve spender to spend WETH on behalf of msg.sender
     * @param spender The address to approve
     * @param value The amount to approve
     */
    function approve(address spender, uint256 value) public returns (bool) {
        require(spender != address(0), "WETH: approve to the zero address");

        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Transfer WETH from one address to another using allowance
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount to transfer
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(from != address(0), "WETH: transfer from the zero address");
        require(to != address(0), "WETH: transfer to the zero address");
        require(balanceOf[from] >= value, "WETH: insufficient balance");
        require(allowance[from][msg.sender] >= value, "WETH: insufficient allowance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @notice Allow contract to receive ETH directly
     */
    receive() external payable {
        deposit();
    }

    /**
     * @notice Fallback function to receive ETH
     */
    fallback() external payable {
        deposit();
    }
}
