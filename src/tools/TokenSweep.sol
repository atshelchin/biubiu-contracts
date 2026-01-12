// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenSweep, Wallet} from "../interfaces/ITokenSweep.sol";

/**
 * @title TokenSweep
 * @notice Batch sweep tokens from multiple wallets to a single recipient
 * @dev Part of BiuBiu Tools - https://biubiu.tools
 *
 * @dev IMPORTANT: This contract requires EIP-7702 (Set EOA account code)
 *
 * EIP-7702 Dependency:
 * - Each wallet in the `wallets` array must be an EOA that has delegated its code to this contract via EIP-7702
 * - The EOA signs a 7702 authorization: `authorization = [chain_id, address(TokenSweep), nonce, ...]`
 * - After delegation, the EOA can be "called" as if it were this contract
 * - When `drainToAddress` is called on the delegated EOA:
 *   - `address(this)` returns the EOA's address (not TokenSweep's address)
 *   - The EOA's private key can sign messages where `ecrecover() == address(this)`
 *   - Token transfers use the EOA's balances directly
 *
 * Flow:
 * 1. User delegates EOA code to TokenSweep via EIP-7702 transaction
 * 2. User signs drain authorization with EOA's private key
 * 3. Anyone calls `multicall([{wallet: EOA, signature: ...}], recipient, tokens, ...)`
 * 4. TokenSweep calls `EOA.drainToAddress(...)` which executes this contract's code in EOA's context
 * 5. Tokens are transferred from EOA to recipient
 *
 * Security:
 * - Only the EOA's private key holder can sign valid drain authorizations
 * - Signature includes chainId, recipient, tokens, and deadline to prevent replay attacks
 * - EIP-7702 delegation can be revoked by the EOA owner at any time
 *
 * Compatibility:
 * - Requires EVM chains supporting EIP-7702 (Ethereum post-Pectra upgrade)
 * - NOT compatible with chains without EIP-7702 (Tron, BSC pre-upgrade, etc.)
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract TokenSweep is ITokenSweep {
    // Hardcoded constants (no external dependencies)
    address public constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;
    uint256 public constant NON_MEMBER_FEE = 0.01 ether;

    // Usage types
    uint8 public constant USAGE_FREE = 0;
    uint8 public constant USAGE_PAID = 1;

    // Statistics
    uint256 public totalFreeUsage;
    uint256 public totalPaidUsage;

    // Reentrancy guard (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;

    // Custom errors (gas efficient)
    error ReentrancyDetected();
    error InsufficientPayment();
    error UnauthorizedCaller();
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidRecipient();
    error TransferFailed();
    error ETHTransferFailed();

    function multicall(
        Wallet[] calldata wallets,
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        address referrer,
        bytes calldata signature
    ) external payable nonReentrant {
        // Verify authorization if signature provided
        if (signature.length > 0) {
            _verifyAuthorization(signature, msg.sender, recipient);
        }

        // Collect fee (non-members pay directly)
        _collectFee(referrer);

        // Execute multicall
        _executeMulticall(wallets, recipient, tokens, deadline);

        emit MulticallExecuted(msg.sender, recipient, wallets.length, USAGE_PAID);
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
     * @dev Collect fee from non-member
     */
    function _collectFee(address referrer) internal {
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

        // Transfer all contract balance to vault
        uint256 contractBalance = address(this).balance;
        if (contractBalance > 0) {
            // forge-lint: disable-next-line(unchecked-call)
            (bool success,) = payable(VAULT).call{value: contractBalance}("");
            if (success) {
                emit VaultPaid(VAULT, msg.sender, contractBalance);
            }
        }
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
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
    }

    function _nonReentrantAfter() private {
        _locked = 1;
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

        // Check s value to prevent signature malleability (EIP-2)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
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
}
