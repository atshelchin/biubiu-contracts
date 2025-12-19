// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IWETH {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function withdraw(uint256 amount) external;
}

interface IBiuBiuPremium {
    function getSubscriptionInfo(address user)
        external
        view
        returns (bool isPremium, uint256 expiryTime, uint256 remainingTime);
}

/// @title TokenDistribution
/// @notice Batch distribute ETH, ERC20, ERC721, ERC1155 tokens to multiple recipients
/// @dev Supports self-execute and delegated execute modes with Merkle tree verification
contract TokenDistribution {
    // Constants
    IBiuBiuPremium public constant PREMIUM_CONTRACT = IBiuBiuPremium(0xc5c4bb399938625523250B708dc5c1e7dE4b1626);
    IWETH public constant WETH = IWETH(0xe3E75C1fe9AE82993FEb6F9CA2e9627aaE1e3d18);
    uint256 public constant NON_MEMBER_FEE = 0.005 ether;
    uint256 public constant MAX_BATCH_SIZE = 100;
    address public constant OWNER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;

    // Token types
    uint8 public constant TOKEN_TYPE_WETH = 0;
    uint8 public constant TOKEN_TYPE_ERC20 = 1;
    uint8 public constant TOKEN_TYPE_ERC721 = 2;
    uint8 public constant TOKEN_TYPE_ERC1155 = 3;

    // EIP-712 Domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant DISTRIBUTION_AUTH_TYPEHASH = keccak256(
        "DistributionAuth(bytes32 uuid,address token,uint8 tokenType,uint256 tokenId,uint256 totalAmount,uint256 totalBatches,bytes32 merkleRoot,uint256 deadline)"
    );
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Reentrancy guard
    uint256 private _locked = 0;

    // Storage for delegated execute
    mapping(bytes32 uuid => mapping(uint256 batchId => bool)) public batchExecuted;
    mapping(bytes32 uuid => uint256) public executedBatchCount;
    mapping(bytes32 uuid => uint256) public distributedAmount;
    mapping(bytes32 uuid => uint256) public totalBatches;

    // Structs
    struct Recipient {
        address to;
        uint256 value; // ERC20/ETH/ERC1155: amount, ERC721: tokenId
    }

    struct DistributionAuth {
        bytes32 uuid;
        address token;
        uint8 tokenType;
        uint256 tokenId; // ERC1155 only
        uint256 totalAmount;
        uint256 totalBatches;
        bytes32 merkleRoot;
        uint256 deadline;
    }

    struct FailedTransfer {
        address to;
        uint256 value;
        bytes reason;
    }

    // Errors
    error ReentrancyDetected();
    error BatchTooLarge();
    error InsufficientPayment();
    error InvalidRecipient();
    error DeadlineExpired();
    error BatchAlreadyExecuted();
    error InvalidBatchId();
    error InvalidSignature();
    error InvalidProof();
    error InvalidProofLength();
    error InvalidTokenType();
    error TransferFailed();
    error ETHTransferFailed();
    error RefundFailed();
    error WithdrawalFailed();

    // Events
    event Distributed(
        address indexed sender,
        address indexed token,
        uint8 tokenType,
        uint256 recipientCount,
        uint256 totalAmount,
        bool isPremium
    );
    event DistributedWithAuth(
        bytes32 indexed uuid, address indexed signer, uint256 batchId, uint256 recipientCount, uint256 batchAmount
    );
    event TransferSkipped(address indexed recipient, uint256 value, bytes reason);
    event Refunded(address indexed to, uint256 amount);
    event FeeCollected(address indexed payer, uint256 amount);
    event ReferralPaid(address indexed referrer, uint256 amount);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("TokenDistribution"), keccak256("1"), block.chainid, address(this))
        );
    }

    modifier nonReentrant() {
        if (_locked == 1) revert ReentrancyDetected();
        _locked = 1;
        _;
        _locked = 0;
    }

    /// @notice Self-execute distribution (owner sends transaction)
    /// @param token Token address (address(0) for native ETH)
    /// @param tokenType Token type (0=WETH not allowed here, 1=ERC20, 2=ERC721, 3=ERC1155)
    /// @param tokenId ERC1155 token ID (0 for others)
    /// @param recipients List of recipients (max 100)
    /// @param referrer Referrer address for fee sharing
    /// @return totalDistributed Total amount successfully distributed
    /// @return failed Array of failed transfers with details (address, value, reason)
    function distribute(
        address token,
        uint8 tokenType,
        uint256 tokenId,
        Recipient[] calldata recipients,
        address referrer
    ) external payable nonReentrant returns (uint256 totalDistributed, FailedTransfer[] memory failed) {
        uint256 len = recipients.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert BatchTooLarge();

        // Check premium status
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(msg.sender);

        // Collect fee if not premium
        uint256 availableETH = msg.value;
        if (!isPremium) {
            if (availableETH < NON_MEMBER_FEE) revert InsufficientPayment();
            availableETH -= NON_MEMBER_FEE;
            _collectFee(NON_MEMBER_FEE, referrer);
        }

        if (token == address(0)) {
            // Native ETH distribution
            (totalDistributed, failed) = _distributeETH(recipients, availableETH);
        } else if (tokenType == TOKEN_TYPE_ERC20) {
            (totalDistributed, failed) = _distributeERC20(token, msg.sender, recipients);
        } else if (tokenType == TOKEN_TYPE_ERC721) {
            (totalDistributed, failed) = _distributeERC721(token, msg.sender, recipients);
        } else if (tokenType == TOKEN_TYPE_ERC1155) {
            (totalDistributed, failed) = _distributeERC1155(token, msg.sender, tokenId, recipients);
        } else {
            revert InvalidTokenType();
        }

        // Refund unused ETH
        uint256 remainingETH = address(this).balance;
        if (remainingETH > 0) {
            (bool success,) = payable(msg.sender).call{value: remainingETH}("");
            if (!success) revert RefundFailed();
            emit Refunded(msg.sender, remainingETH);
        }

        emit Distributed(msg.sender, token, tokenType, len, totalDistributed, isPremium);
    }

    /// @notice Delegated execute distribution (executor sends transaction on behalf of owner)
    /// @param auth Authorization struct signed by owner
    /// @param signature Owner's EIP-712 signature
    /// @param batchId Batch number to execute
    /// @param recipients Recipients for this batch
    /// @param proofs Flattened Merkle proofs for all recipients
    /// @param proofLengths Length of each recipient's proof
    /// @param referrer Referrer address for fee sharing
    /// @return batchAmount Total amount successfully distributed in this batch
    /// @return failed Array of failed transfers with details (address, value, reason)
    function distributeWithAuth(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths,
        address referrer
    ) external payable nonReentrant returns (uint256 batchAmount, FailedTransfer[] memory failed) {
        // Validate, verify signature, and update state in one call to reduce stack depth
        address signer =
            _validateVerifyAndUpdate(auth, signature, batchId, recipients.length, proofLengths.length, referrer);

        // Verify Merkle proofs
        _verifyMerkleProofs(auth.merkleRoot, batchId, recipients, proofs, proofLengths);

        // Execute distribution and finalize
        (batchAmount, failed) = _executeAndFinalize(auth, signer, batchId, recipients);
    }

    function _validateVerifyAndUpdate(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        uint256 recipientsLen,
        uint256 proofLengthsLen,
        address referrer
    ) internal returns (address signer) {
        _validateAuthInputs(auth, batchId, recipientsLen, proofLengthsLen);
        signer = _verifySignature(auth, signature);
        _checkPremiumAndCollectFee(signer, referrer);
        _updateBatchState(auth.uuid, batchId, auth.totalBatches);
    }

    function _executeAndFinalize(
        DistributionAuth calldata auth,
        address signer,
        uint256 batchId,
        Recipient[] calldata recipients
    ) internal returns (uint256 batchAmount, FailedTransfer[] memory failed) {
        (batchAmount, failed) = _executeDistribution(auth, signer, recipients);
        distributedAmount[auth.uuid] += batchAmount;
        _refundETH(signer);
        emit DistributedWithAuth(auth.uuid, signer, batchId, recipients.length, batchAmount);
    }

    function _validateAuthInputs(
        DistributionAuth calldata auth,
        uint256 batchId,
        uint256 recipientsLen,
        uint256 proofLengthsLen
    ) internal view {
        if (recipientsLen == 0 || recipientsLen > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (batchId >= auth.totalBatches) revert InvalidBatchId();
        if (batchExecuted[auth.uuid][batchId]) revert BatchAlreadyExecuted();
        if (proofLengthsLen != recipientsLen) revert InvalidProof();
    }

    function _checkPremiumAndCollectFee(address signer, address referrer) internal {
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(signer);
        if (!isPremium) {
            if (msg.value < NON_MEMBER_FEE) revert InsufficientPayment();
            _collectFee(NON_MEMBER_FEE, referrer);
        }
    }

    function _updateBatchState(bytes32 uuid, uint256 batchId, uint256 _totalBatches) internal {
        batchExecuted[uuid][batchId] = true;
        executedBatchCount[uuid]++;
        if (totalBatches[uuid] == 0) {
            totalBatches[uuid] = _totalBatches;
        }
    }

    function _executeDistribution(DistributionAuth calldata auth, address signer, Recipient[] calldata recipients)
        internal
        returns (uint256 batchAmount, FailedTransfer[] memory failed)
    {
        if (auth.tokenType == TOKEN_TYPE_WETH) {
            (batchAmount, failed) = _distributeWETH(signer, recipients);
        } else if (auth.tokenType == TOKEN_TYPE_ERC20) {
            (batchAmount, failed) = _distributeERC20(auth.token, signer, recipients);
        } else if (auth.tokenType == TOKEN_TYPE_ERC721) {
            (batchAmount, failed) = _distributeERC721(auth.token, signer, recipients);
        } else if (auth.tokenType == TOKEN_TYPE_ERC1155) {
            (batchAmount, failed) = _distributeERC1155(auth.token, signer, auth.tokenId, recipients);
        } else {
            revert InvalidTokenType();
        }
    }

    function _refundETH(address to) internal {
        uint256 remainingETH = address(this).balance;
        if (remainingETH > 0) {
            (bool success,) = payable(to).call{value: remainingETH}("");
            if (success) {
                emit Refunded(to, remainingETH);
            }
        }
    }

    /// @notice Query if a batch has been executed
    function isBatchExecuted(bytes32 uuid, uint256 batchId) external view returns (bool) {
        return batchExecuted[uuid][batchId];
    }

    /// @notice Query distribution progress
    function getProgress(bytes32 uuid)
        external
        view
        returns (uint256 _executedBatches, uint256 _totalBatches, uint256 _distributedAmount)
    {
        return (executedBatchCount[uuid], totalBatches[uuid], distributedAmount[uuid]);
    }

    // ============ Internal Functions ============

    function _collectFee(uint256 fee, address referrer) internal {
        uint256 ownerAmount = fee;

        if (referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = fee >> 1; // 50%
            ownerAmount = fee - referralAmount; // Remaining 50% for owner
            (bool success,) = payable(referrer).call{value: referralAmount}("");
            if (success) {
                emit ReferralPaid(referrer, referralAmount);
            } else {
                // If referrer transfer fails, owner gets the full fee
                ownerAmount = fee;
            }
        }

        if (ownerAmount > 0) {
            (bool success,) = payable(OWNER).call{value: ownerAmount}("");
            if (success) {
                emit FeeCollected(msg.sender, ownerAmount);
            }
        }
    }

    function _distributeETH(Recipient[] calldata recipients, uint256 availableETH)
        internal
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;
        // Pre-allocate max possible size, will resize at end
        FailedTransfer[] memory tempFailed = new FailedTransfer[](len);
        uint256 failedCount;

        for (uint256 i; i < len;) {
            Recipient calldata r = recipients[i];
            if (r.to == address(0)) {
                tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "zero address");
                emit TransferSkipped(r.to, r.value, "zero address");
            } else if (availableETH < r.value) {
                tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "insufficient ETH");
                emit TransferSkipped(r.to, r.value, "insufficient ETH");
            } else {
                availableETH -= r.value;
                (bool success,) = payable(r.to).call{value: r.value}("");
                if (success) {
                    totalDistributed += r.value;
                } else {
                    tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "transfer failed");
                    emit TransferSkipped(r.to, r.value, "transfer failed");
                }
            }
            unchecked {
                ++i;
            }
        }

        // Resize array to actual failed count
        failed = new FailedTransfer[](failedCount);
        for (uint256 i; i < failedCount;) {
            failed[i] = tempFailed[i];
            unchecked {
                ++i;
            }
        }
    }

    function _distributeWETH(address from, Recipient[] calldata recipients)
        internal
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;

        // Calculate total amount needed
        uint256 totalNeeded;
        for (uint256 i; i < len;) {
            totalNeeded += recipients[i].value;
            unchecked {
                ++i;
            }
        }

        // Transfer WETH from signer to this contract
        try WETH.transferFrom(from, address(this), totalNeeded) returns (bool success) {
            if (!success) revert TransferFailed();
        } catch {
            revert TransferFailed();
        }

        // Withdraw WETH to ETH
        try WETH.withdraw(totalNeeded) {}
        catch {
            revert TransferFailed();
        }

        // Pre-allocate max possible size
        FailedTransfer[] memory tempFailed = new FailedTransfer[](len);
        uint256 failedCount;

        // Distribute ETH
        for (uint256 i; i < len;) {
            Recipient calldata r = recipients[i];
            if (r.to == address(0)) {
                tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "zero address");
                emit TransferSkipped(r.to, r.value, "zero address");
            } else {
                (bool success,) = payable(r.to).call{value: r.value}("");
                if (success) {
                    totalDistributed += r.value;
                } else {
                    tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "transfer failed");
                    emit TransferSkipped(r.to, r.value, "transfer failed");
                }
            }
            unchecked {
                ++i;
            }
        }

        // Resize array to actual failed count
        failed = new FailedTransfer[](failedCount);
        for (uint256 i; i < failedCount;) {
            failed[i] = tempFailed[i];
            unchecked {
                ++i;
            }
        }
    }

    function _distributeERC20(address token, address from, Recipient[] calldata recipients)
        internal
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;
        FailedTransfer[] memory tempFailed = new FailedTransfer[](len);
        uint256 failedCount;

        for (uint256 i; i < len;) {
            Recipient calldata r = recipients[i];
            if (r.to == address(0)) {
                tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "zero address");
                emit TransferSkipped(r.to, r.value, "zero address");
            } else {
                try IERC20(token).transferFrom(from, r.to, r.value) returns (bool success) {
                    if (success) {
                        totalDistributed += r.value;
                    } else {
                        tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "transfer returned false");
                        emit TransferSkipped(r.to, r.value, "transfer returned false");
                    }
                } catch (bytes memory reason) {
                    tempFailed[failedCount++] = FailedTransfer(r.to, r.value, reason);
                    emit TransferSkipped(r.to, r.value, reason);
                }
            }
            unchecked {
                ++i;
            }
        }

        failed = new FailedTransfer[](failedCount);
        for (uint256 i; i < failedCount;) {
            failed[i] = tempFailed[i];
            unchecked {
                ++i;
            }
        }
    }

    function _distributeERC721(address token, address from, Recipient[] calldata recipients)
        internal
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;
        FailedTransfer[] memory tempFailed = new FailedTransfer[](len);
        uint256 failedCount;

        for (uint256 i; i < len;) {
            Recipient calldata r = recipients[i];
            uint256 tokenId = r.value; // value stores tokenId for ERC721
            if (r.to == address(0)) {
                tempFailed[failedCount++] = FailedTransfer(r.to, tokenId, "zero address");
                emit TransferSkipped(r.to, tokenId, "zero address");
            } else {
                try IERC721(token).transferFrom(from, r.to, tokenId) {
                    totalDistributed += 1;
                } catch (bytes memory reason) {
                    tempFailed[failedCount++] = FailedTransfer(r.to, tokenId, reason);
                    emit TransferSkipped(r.to, tokenId, reason);
                }
            }
            unchecked {
                ++i;
            }
        }

        failed = new FailedTransfer[](failedCount);
        for (uint256 i; i < failedCount;) {
            failed[i] = tempFailed[i];
            unchecked {
                ++i;
            }
        }
    }

    function _distributeERC1155(address token, address from, uint256 tokenId, Recipient[] calldata recipients)
        internal
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;
        FailedTransfer[] memory tempFailed = new FailedTransfer[](len);
        uint256 failedCount;

        for (uint256 i; i < len;) {
            Recipient calldata r = recipients[i];
            if (r.to == address(0)) {
                tempFailed[failedCount++] = FailedTransfer(r.to, r.value, "zero address");
                emit TransferSkipped(r.to, r.value, "zero address");
            } else {
                try IERC1155(token).safeTransferFrom(from, r.to, tokenId, r.value, "") {
                    totalDistributed += r.value;
                } catch (bytes memory reason) {
                    tempFailed[failedCount++] = FailedTransfer(r.to, r.value, reason);
                    emit TransferSkipped(r.to, r.value, reason);
                }
            }
            unchecked {
                ++i;
            }
        }

        failed = new FailedTransfer[](failedCount);
        for (uint256 i; i < failedCount;) {
            failed[i] = tempFailed[i];
            unchecked {
                ++i;
            }
        }
    }

    function _verifySignature(DistributionAuth calldata auth, bytes calldata signature)
        internal
        view
        returns (address)
    {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 structHash = keccak256(
            abi.encode(
                DISTRIBUTION_AUTH_TYPEHASH,
                auth.uuid,
                auth.token,
                auth.tokenType,
                auth.tokenId,
                auth.totalAmount,
                auth.totalBatches,
                auth.merkleRoot,
                auth.deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

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

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();

        return signer;
    }

    function _verifyMerkleProofs(
        bytes32 merkleRoot,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths
    ) internal pure {
        // Calculate total proof elements needed
        uint256 totalProofLen;
        uint256 recipientsLen = recipients.length;
        for (uint256 i; i < recipientsLen;) {
            totalProofLen += proofLengths[i];
            unchecked {
                ++i;
            }
        }

        // Verify proofs array has enough elements
        if (proofs.length < totalProofLen) revert InvalidProofLength();

        uint256 proofOffset;
        uint256 baseIndex = batchId * MAX_BATCH_SIZE;

        for (uint256 i; i < recipientsLen;) {
            // Compute leaf: keccak256(index, recipient, value)
            bytes32 computedHash = keccak256(abi.encodePacked(baseIndex + i, recipients[i].to, recipients[i].value));

            // Verify proof inline
            uint8 proofLen = proofLengths[i];
            for (uint256 j; j < proofLen;) {
                bytes32 proofElement = proofs[proofOffset + j];
                if (computedHash <= proofElement) {
                    computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
                } else {
                    computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
                }
                unchecked {
                    ++j;
                }
            }
            proofOffset += proofLen;

            if (computedHash != merkleRoot) revert InvalidProof();

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}

    /// @notice Withdraw stuck ETH or ERC20 tokens to OWNER
    /// @param token Token address (address(0) for ETH)
    /// @dev Can be called by anyone, but funds always go to OWNER
    function ownerWithdraw(address token) external nonReentrant {
        if (token == address(0)) {
            uint256 balance = address(this).balance;
            if (balance == 0) revert WithdrawalFailed();
            (bool success,) = payable(OWNER).call{value: balance}("");
            if (!success) revert WithdrawalFailed();
        } else {
            // Get balance using staticcall
            (bool success, bytes memory data) =
                token.staticcall(abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), address(this)));
            if (!success || data.length < 32) revert WithdrawalFailed();

            uint256 balance = abi.decode(data, (uint256));
            if (balance == 0) revert WithdrawalFailed();

            // Transfer using transfer(address,uint256)
            (success, data) =
                token.call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), OWNER, balance));
            // For tokens that don't return bool, check if call succeeded
            if (!success) revert WithdrawalFailed();
            if (data.length > 0 && !abi.decode(data, (bool))) revert WithdrawalFailed();
        }
    }
}
