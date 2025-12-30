# Solidity Audit Report

## TokenDistribution.sol

**Contract Version:** Solidity ^0.8.20
**Audit Date:** 2025-12-30
**Risk Level:** LOW

**Repository:** https://github.com/atshelchin/biubiu-contracts
**Commit:** `6458249a0e952c96f401bbd3755dfdbee9405828`
**Auditor:** Claude (AI Security Review)

---

## Executive Summary

TokenDistribution is a batch token distribution contract supporting ETH, WETH, ERC20, ERC721, and ERC1155 tokens. It features both self-execute and delegated execute modes with EIP-712 signatures and Merkle tree verification.

---

## Contract Overview

| Property | Value |
|----------|-------|
| Lines of Code | 787 |
| External Dependencies | IBiuBiuPremium, IWETH, IERC20/721/1155 |
| Reentrancy Guard | Yes (1/2 pattern) |
| Owner | Immutable constant |
| Fee | 0.005 ETH (non-members) |
| Max Batch Size | 100 recipients |

---

## Findings

### L-01: WETH Address Chain-Specific (Low)

**Location:** Line 35

**Description:**
WETH address is hardcoded and may differ across chains.

```solidity
IWETH public constant WETH = IWETH(0xFe7291380b8Dc405fEf345222f2De2408A6CA18e);
```

**Impact:** Low - Must be verified before deployment on each chain.

**Recommendation:** Verify WETH address matches the deployed WETH on target chain.

---

### L-02: totalAmount in Signature Not Validated (Low)

**Location:** Lines 62-64, 672-684

**Description:**
The `totalAmount` field in `DistributionAuth` is signed but not validated against actual distribution amounts.

**Impact:** Low - This is informational only; actual transfers are validated by Merkle proofs.

---

### L-03: Silent Transfer Failures Logged (Low)

**Location:** Lines 462-475, 527-537

**Description:**
Failed transfers are logged via `TransferSkipped` event rather than reverting. This allows partial distributions.

**Impact:** Low - Intentional design. Return value includes `FailedTransfer[]` array for handling.

---

### I-01: EIP-712 Domain Separator (Informational)

**Location:** Lines 59-66, 138-141

**Description:**
Proper EIP-712 implementation with chain-specific domain separator.

**Impact:** None - Correctly implemented.

---

### I-02: Merkle Proof Verification (Informational)

**Location:** Lines 708-756

**Description:**
Merkle proofs are verified for each recipient in delegated mode, ensuring data integrity.

**Impact:** None - Correctly implemented.

---

### I-03: Signature Malleability Protection (Informational)

**Location:** Lines 697-700

**Description:**
EIP-2 signature malleability check is implemented.

```solidity
if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
    revert InvalidSignature();
}
```

**Impact:** None - Good security practice.

---

## Security Best Practices Checklist

| Category | Status | Notes |
|----------|--------|-------|
| Reentrancy Protection | OK | 1/2 pattern |
| Integer Overflow/Underflow | OK | Solidity 0.8+ |
| Access Control | OK | Signature verification |
| Input Validation | OK | Batch size, deadline checks |
| EIP-712 Compliance | OK | Proper implementation |
| Merkle Verification | OK | Per-recipient proofs |
| Signature Malleability | OK | EIP-2 protected |

---

## Gas Optimizations

| Optimization | Status |
|--------------|--------|
| Unchecked increments | OK |
| Bit shift for 50% | OK |
| Calldata usage | OK |
| Pre-allocated arrays | OK |

---

## Token Support

| Token Type | Status |
|------------|--------|
| Native ETH | OK |
| WETH (via withdraw) | OK |
| ERC20 | OK |
| ERC721 | OK |
| ERC1155 | OK |

---

## Conclusion

TokenDistribution.sol is a comprehensive batch distribution system with robust security measures. The EIP-712 signature and Merkle proof implementation are correct. Failed transfers are gracefully handled with detailed reporting.

**Overall Assessment:** Production-ready. Verify WETH address per chain.
