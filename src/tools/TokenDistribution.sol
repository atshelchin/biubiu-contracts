// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenDistribution, Recipient, DistributionAuth, FailedTransfer} from "../interfaces/ITokenDistribution.sol";
import {IBiuBiuPremium} from "../interfaces/IBiuBiuPremium.sol";
import {IWETH} from "../interfaces/IWETH.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/// @title TokenDistribution
/// @notice Batch distribute ETH, ERC20, ERC721, ERC1155 tokens to multiple recipients
/// @dev Supports self-execute and delegated execute modes with Merkle tree verification
/// @dev Part of BiuBiu Tools - https://biubiu.tools
contract TokenDistribution is ITokenDistribution {
    // Immutables (set via constructor for cross-chain deterministic deployment)
    IBiuBiuPremium public immutable PREMIUM_CONTRACT;
    IWETH public immutable WETH;

    // Constants
    uint256 public constant MAX_BATCH_SIZE = 100;

    constructor(address _premiumContract, address _weth) {
        PREMIUM_CONTRACT = IBiuBiuPremium(_premiumContract);
        WETH = IWETH(_weth);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("TokenDistribution"), keccak256("1"), block.chainid, address(this))
        );
    }

    /// @notice Get the vault address from PREMIUM_CONTRACT
    function VAULT() public view returns (address) {
        return PREMIUM_CONTRACT.VAULT();
    }

    /// @notice Get the non-member fee from PREMIUM_CONTRACT
    function NON_MEMBER_FEE() public view returns (uint256) {
        return PREMIUM_CONTRACT.NON_MEMBER_FEE();
    }

    // Token types
    uint8 public constant TOKEN_TYPE_WETH = 0;
    uint8 public constant TOKEN_TYPE_ERC20 = 1;
    uint8 public constant TOKEN_TYPE_ERC721 = 2;
    uint8 public constant TOKEN_TYPE_ERC1155 = 3;

    // Usage types
    uint8 public constant USAGE_FREE = 0;
    uint8 public constant USAGE_PREMIUM = 1;
    uint8 public constant USAGE_PAID = 2;

    // Statistics
    uint256 public totalFreeUsage;
    uint256 public totalPremiumUsage;
    uint256 public totalPaidUsage;
    uint256 public totalFreeAuthUsage;
    uint256 public totalPremiumAuthUsage;
    uint256 public totalPaidAuthUsage;

    // EIP-712 Domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant DISTRIBUTION_AUTH_TYPEHASH = keccak256(
        "DistributionAuth(bytes32 uuid,address token,uint8 tokenType,uint256 tokenId,uint256 totalAmount,uint256 totalBatches,bytes32 merkleRoot,uint256 deadline)"
    );
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Reentrancy guard (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;

    // Storage for delegated execute
    mapping(bytes32 uuid => mapping(uint256 batchId => bool)) public batchExecuted;
    mapping(bytes32 uuid => uint256) public executedBatchCount;
    mapping(bytes32 uuid => uint256) public distributedAmount;
    mapping(bytes32 uuid => uint256) public totalBatches;

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

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyDetected();
        _locked = 2;
        _;
        _locked = 1;
    }

    /// @notice Self-execute distribution (owner sends transaction) - paid version
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

        // Check premium status and collect fee
        (uint8 usageType, uint256 availableETH) = _checkAndCollectFeeForDistribute(msg.value, referrer);

        // Execute distribution
        (totalDistributed, failed) = _executeDistribute(token, tokenType, tokenId, recipients, availableETH);

        // Refund unused ETH
        _refundETH(msg.sender);

        emit Distributed(msg.sender, token, tokenType, len, totalDistributed, usageType);
    }

    /// @notice Self-execute distribution (free version)
    /// @param token Token address (address(0) for native ETH)
    /// @param tokenType Token type (0=WETH not allowed here, 1=ERC20, 2=ERC721, 3=ERC1155)
    /// @param tokenId ERC1155 token ID (0 for others)
    /// @param recipients List of recipients (max 100)
    /// @return totalDistributed Total amount successfully distributed
    /// @return failed Array of failed transfers with details (address, value, reason)
    function distributeFree(address token, uint8 tokenType, uint256 tokenId, Recipient[] calldata recipients)
        external
        payable
        nonReentrant
        returns (uint256 totalDistributed, FailedTransfer[] memory failed)
    {
        uint256 len = recipients.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert BatchTooLarge();

        totalFreeUsage++;

        // Execute distribution with full msg.value available
        (totalDistributed, failed) = _executeDistribute(token, tokenType, tokenId, recipients, msg.value);

        // Refund unused ETH
        _refundETH(msg.sender);

        emit Distributed(msg.sender, token, tokenType, len, totalDistributed, USAGE_FREE);
    }

    /// @dev Internal function to execute distribution
    function _executeDistribute(
        address token,
        uint8 tokenType,
        uint256 tokenId,
        Recipient[] calldata recipients,
        uint256 availableETH
    ) internal returns (uint256 totalDistributed, FailedTransfer[] memory failed) {
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
    }

    /// @dev Check premium status and collect fee for distribute
    function _checkAndCollectFeeForDistribute(uint256 msgValue, address referrer)
        internal
        returns (uint8 usageType, uint256 availableETH)
    {
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(msg.sender);

        availableETH = msgValue;

        if (isPremium) {
            totalPremiumUsage++;
            return (USAGE_PREMIUM, availableETH);
        }

        // Non-member must pay
        uint256 fee = NON_MEMBER_FEE();
        if (availableETH < fee) revert InsufficientPayment();
        availableETH -= fee;

        totalPaidUsage++;
        _collectFee(fee, referrer);

        return (USAGE_PAID, availableETH);
    }

    /// @notice Delegated execute distribution (executor sends transaction on behalf of owner) - paid version
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
        // Validate and verify signature
        address signer = _validateAndVerifyAuth(auth, signature, batchId, recipients.length, proofLengths.length);

        // Check premium status and collect fee
        uint8 usageType = _checkPremiumAndCollectFeeForAuth(signer, referrer);

        // Execute distribution with auth
        (batchAmount, failed) =
            _executeDistributeWithAuth(auth, signer, batchId, recipients, proofs, proofLengths, usageType);
    }

    /// @notice Delegated execute distribution (free version)
    /// @param auth Authorization struct signed by owner
    /// @param signature Owner's EIP-712 signature
    /// @param batchId Batch number to execute
    /// @param recipients Recipients for this batch
    /// @param proofs Flattened Merkle proofs for all recipients
    /// @param proofLengths Length of each recipient's proof
    /// @return batchAmount Total amount successfully distributed in this batch
    /// @return failed Array of failed transfers with details (address, value, reason)
    function distributeWithAuthFree(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths
    ) external payable nonReentrant returns (uint256 batchAmount, FailedTransfer[] memory failed) {
        // Validate and verify signature
        address signer = _validateAndVerifyAuth(auth, signature, batchId, recipients.length, proofLengths.length);

        totalFreeAuthUsage++;

        // Execute distribution with auth
        (batchAmount, failed) =
            _executeDistributeWithAuth(auth, signer, batchId, recipients, proofs, proofLengths, USAGE_FREE);
    }

    /// @dev Validate inputs and verify signature
    function _validateAndVerifyAuth(
        DistributionAuth calldata auth,
        bytes calldata signature,
        uint256 batchId,
        uint256 recipientsLen,
        uint256 proofLengthsLen
    ) internal view returns (address signer) {
        _validateAuthInputs(auth, batchId, recipientsLen, proofLengthsLen);
        signer = _verifySignature(auth, signature);
    }

    /// @dev Execute distribution with auth
    function _executeDistributeWithAuth(
        DistributionAuth calldata auth,
        address signer,
        uint256 batchId,
        Recipient[] calldata recipients,
        bytes32[] calldata proofs,
        uint8[] calldata proofLengths,
        uint8 usageType
    ) internal returns (uint256 batchAmount, FailedTransfer[] memory failed) {
        _updateBatchState(auth.uuid, batchId, auth.totalBatches);

        // Verify Merkle proofs
        _verifyMerkleProofs(auth.merkleRoot, batchId, recipients, proofs, proofLengths);

        // Execute distribution
        (batchAmount, failed) = _executeDistributionByType(auth, signer, recipients);
        distributedAmount[auth.uuid] += batchAmount;

        _refundETH(signer);
        emit DistributedWithAuth(auth.uuid, signer, batchId, recipients.length, batchAmount, usageType);
    }

    /// @dev Check premium status and collect fee for auth distribution
    function _checkPremiumAndCollectFeeForAuth(address signer, address referrer) internal returns (uint8 usageType) {
        (bool isPremium,,) = PREMIUM_CONTRACT.getSubscriptionInfo(signer);

        if (isPremium) {
            totalPremiumAuthUsage++;
            return USAGE_PREMIUM;
        }

        // Non-member must pay
        uint256 fee = NON_MEMBER_FEE();
        if (msg.value < fee) revert InsufficientPayment();

        totalPaidAuthUsage++;
        _collectFee(fee, referrer);

        return USAGE_PAID;
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

    function _updateBatchState(bytes32 uuid, uint256 batchId, uint256 _totalBatches) internal {
        batchExecuted[uuid][batchId] = true;
        executedBatchCount[uuid]++;
        if (totalBatches[uuid] == 0) {
            totalBatches[uuid] = _totalBatches;
        }
    }

    function _executeDistributionByType(DistributionAuth calldata auth, address signer, Recipient[] calldata recipients)
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
            if (!success) revert RefundFailed();
            emit Refunded(to, remainingETH);
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
            (bool success,) = payable(VAULT()).call{value: ownerAmount}("");
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
}
