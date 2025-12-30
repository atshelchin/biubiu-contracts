// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBiuBiuPremium {
    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime);
}

interface ITokenSweep {
    function drainToAddress(address recipient, address[] calldata tokens, uint256 deadline, bytes calldata signature)
        external;
}

struct Wallet {
    address wallet;
    bytes signature; // 65 bytes: r (32) + s (32) + v (1)
}

contract TokenSweep {
    IBiuBiuPremium public constant PREMIUM_CONTRACT = IBiuBiuPremium(0xc5c4bb399938625523250B708dc5c1e7dE4b1626);
    uint256 public constant NON_MEMBER_FEE = 0.005 ether;
    address public constant OWNER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;

    // Usage types
    uint8 public constant USAGE_FREE = 0;
    uint8 public constant USAGE_PREMIUM = 1;
    uint8 public constant USAGE_PAID = 2;

    // Statistics
    uint256 public totalFreeUsage;
    uint256 public totalPremiumUsage;
    uint256 public totalPaidUsage;

    // Reentrancy guard
    uint256 private _locked = 0;

    // Custom errors (gas efficient)
    error ReentrancyDetected();
    error InsufficientPayment();
    error NoBalanceToWithdraw();
    error UnauthorizedCaller();
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidRecipient();
    error TransferFailed();
    error ETHTransferFailed();
    error WithdrawalFailed();

    event OwnerWithdrew(address indexed owner, address indexed token, uint256 amount);
    event ReferralPaid(address indexed referrer, address indexed caller, uint256 amount);
    event OwnerPaid(address indexed owner, address indexed caller, uint256 amount);
    event MulticallExecuted(address indexed caller, address indexed recipient, uint256 walletsCount, uint8 usageType);

    function multicall(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        address referrer,
        bytes calldata signature
    ) external payable nonReentrant {
        // Determine who to check for membership (caller or authorized signer)
        address checker = signature.length > 0 ? _verifyAuthorization(signature, msg.sender, recipient) : msg.sender;

        // Check premium status and collect fee
        uint8 usageType = _checkAndCollectFee(checker, referrer);

        // Execute multicall
        _executeMulticall(wallets, recipient, tokens, deadline);

        emit MulticallExecuted(msg.sender, recipient, wallets.length, usageType);
    }

    /**
     * @notice Multicall free version (no payment required)
     */
    function multicallFree(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        // Verify authorization if signature provided
        if (signature.length > 0) {
            _verifyAuthorization(signature, msg.sender, recipient);
        }

        totalFreeUsage++;

        // Execute multicall
        _executeMulticall(wallets, recipient, tokens, deadline);

        emit MulticallExecuted(msg.sender, recipient, wallets.length, USAGE_FREE);
    }

    /**
     * @dev Internal function to execute multicall
     */
    function _executeMulticall(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline
    ) internal {
        unchecked {
            uint256 len = wallets.length;
            for (uint256 i; i < len; ++i) {
                Wallet calldata w = wallets[i];
                ITokenSweep(w.wallet).drainToAddress(recipient, tokens, deadline, w.signature);
            }
        }
    }

    /**
     * @dev Check premium status and collect fee if needed
     */
    function _checkAndCollectFee(address checker, address referrer) internal returns (uint8 usageType) {
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(checker);

        if (isPremium) {
            totalPremiumUsage++;
            return USAGE_PREMIUM;
        }

        // Non-member must pay
        if (msg.value < NON_MEMBER_FEE) revert InsufficientPayment();

        totalPaidUsage++;

        // Split fee with referrer (50%)
        if (referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = msg.value >> 1; // 50% using bit shift

            // forge-lint: disable-next-line(unchecked-call)
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, msg.sender, referralAmount);
            }
        }

        // Transfer all contract balance to owner (including current payment and any accumulated funds)
        uint256 contractBalance = address(this).balance;
        if (contractBalance > 0) {
            // forge-lint: disable-next-line(unchecked-call)
            (bool success,) = payable(OWNER).call{value: contractBalance}("");
            if (success) {
                emit OwnerPaid(OWNER, msg.sender, contractBalance);
            }
        }

        return USAGE_PAID;
    }

    function drainToAddress(address recipient, address[] calldata tokens, uint256 deadline, bytes calldata signature)
        external
    {
        // Validate deadline and recipient
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (recipient == address(0)) revert InvalidRecipient();

        // Verify signature
        _verifyDrainSignature(signature, recipient, tokens, deadline);

        // Transfer all tokens
        unchecked {
            uint256 len = tokens.length;
            for (uint256 i; i < len; ++i) {
                address token = tokens[i];
                if (token == address(0)) continue;

                (bool success, bytes memory data) =
                    token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

                if (success && data.length >= 32) {
                    uint256 balance = abi.decode(data, (uint256));

                    if (balance > 0) {
                        (success, data) =
                            token.call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, balance));

                        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
                            revert TransferFailed();
                        }
                    }
                }
            }
        }

        // Transfer ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success,) = recipient.call{value: ethBalance}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_locked == 1) revert ReentrancyDetected();
        _locked = 1;
    }

    function _nonReentrantAfter() private {
        _locked = 0;
    }

    /**
     * @dev Verify authorization signature and return signer address
     * @param signature The signature bytes (65 bytes: r, s, v)
     * @param caller The address calling multicall
     * @param recipient The recipient address for tokens
     * @return signer The address that signed the authorization
     */
    function _verifyAuthorization(bytes calldata signature, address caller, address recipient)
        private
        view
        returns (address)
    {
        if (signature.length != 65) revert InvalidSignature();

        // Extract v, r, s from signature using assembly for gas efficiency
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // Construct human-readable message for signature
        string memory message = string(
            abi.encodePacked(
                "TokenSweep Authorization\n\n",
                "I authorize wallet:\n",
                _toHexString(caller),
                "\n\nto call multicall on my behalf\n\n",
                "Recipient address:\n",
                _toHexString(recipient),
                "\n\nChain ID: ",
                _toString(block.chainid)
            )
        );

        bytes32 messageHash = keccak256(bytes(message));

        // Recover signer address
        address signer = ecrecover(messageHash, v, r, s);
        if (signer == address(0)) revert InvalidSignature();

        return signer;
    }

    /**
     * @dev Verify drainToAddress signature
     * @param signature The signature bytes (65 bytes: r, s, v)
     * @param recipient The recipient address for tokens
     * @param tokens The array of token addresses to drain
     * @param deadline The deadline timestamp
     */
    function _verifyDrainSignature(
        bytes calldata signature,
        address recipient,
        address[] calldata tokens,
        uint256 deadline
    ) private view {
        if (signature.length != 65) revert InvalidSignature();

        // Extract v, r, s from signature (r=32, s=32, v=1)
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // Check s value to prevent signature malleability (EIP-2)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }

        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(block.chainid, address(this), recipient, tokens, deadline))
            )
        );

        if (ecrecover(messageHash, v, r, s) != address(this)) {
            revert UnauthorizedCaller();
        }
    }

    /**
     * @dev Convert address to hex string
     */
    function _toHexString(address addr) private pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            // Safe cast: extracting single byte from address (0-255)
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 value = uint8(uint160(addr) >> (8 * (19 - i)));
            buffer[2 + i * 2] = _hexChar(value >> 4);
            buffer[3 + i * 2] = _hexChar(value & 0x0f);
        }
        return string(buffer);
    }

    /**
     * @dev Convert uint256 to string
     */
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // Safe cast: value % 10 is always 0-9, adding 48 gives ASCII '0'-'9' (48-57)
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Get hex character
     */
    function _hexChar(uint8 value) private pure returns (bytes1) {
        if (value < 10) {
            // Safe cast: 48 + value (0-9) = 48-57, which is within uint8 range
            // forge-lint: disable-next-line(unsafe-typecast)
            return bytes1(uint8(48 + value)); // 0-9
        }
        // Safe cast: 87 + value (10-15) = 97-102, which is within uint8 range
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes1(uint8(87 + value)); // a-f
    }

    /**
     * @dev Receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback
     */
    fallback() external payable {}

    /**
     * @dev Handle ERC721 token reception
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Handle ERC1155 single token reception
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handle ERC1155 batch token reception
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Support ERC165 interface detection
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x150b7a02 // ERC721Receiver
            || interfaceId == 0x4e2312e0 // ERC1155Receiver-single
            || interfaceId == 0xbc197c81; // ERC1155Receiver-batch
    }

    /**
     * @notice Withdraw ETH or ERC20 tokens to OWNER
     * @param token The token address (use address(0) for ETH)
     * @dev Can be called by anyone, but funds/tokens always go to OWNER
     */
    function ownerWithdraw(address token) external nonReentrant {
        uint256 amount;

        if (token == address(0)) {
            // Withdraw ETH
            amount = address(this).balance;
            if (amount == 0) revert NoBalanceToWithdraw();

            (bool success,) = payable(OWNER).call{value: amount}("");
            if (!success) revert WithdrawalFailed();
        } else {
            // Withdraw ERC20 token
            (bool success, bytes memory data) =
                token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

            if (!success || data.length < 32) revert WithdrawalFailed();

            amount = abi.decode(data, (uint256));
            if (amount == 0) revert NoBalanceToWithdraw();

            (success, data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, OWNER, amount));

            if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
                revert WithdrawalFailed();
            }
        }

        emit OwnerWithdrew(OWNER, token, amount);
    }
}
