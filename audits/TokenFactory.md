# Solidity Audit Report

## TokenFactory.sol

**Contract Version:** Solidity ^0.8.20
**Audit Date:** 2025-12-30
**Risk Level:** LOW

**Repository:** https://github.com/atshelchin/biubiu-contracts
**Commit:** `6458249a0e952c96f401bbd3755dfdbee9405828`
**Auditor:** Claude (AI Security Review)

---

## Executive Summary

TokenFactory is a factory contract for deploying ERC20 tokens using CREATE2 for deterministic addresses. It includes a premium membership system and referral fee mechanism. The contract also deploys SimpleToken instances.

---

## Contract Overview

| Property | Value |
|----------|-------|
| Lines of Code | 495 |
| External Dependencies | IBiuBiuPremium interface |
| Reentrancy Guard | None (stateless operations) |
| Owner | Immutable constant |
| Fee | 0.005 ETH (non-members) |

---

## Contracts Included

1. **SimpleToken** - Basic ERC20 with optional minting
2. **TokenFactory** - Factory for deploying SimpleToken

---

## Findings

### L-01: Silent Payment Failures (Low)

**Location:** Lines 261-273

**Description:**
If referrer or owner payment fails, the transaction continues without reverting.

```solidity
(bool success,) = payable(referrer).call{value: referralAmount}("");
if (success) {
    emit ReferralPaid(referrer, msg.sender, referralAmount);
}
```

**Impact:** Low - Funds may remain in contract if payments fail.

**Recommendation:** This is intentional to prevent griefing. The `ownerWithdraw` pattern would help recover stuck funds if added.

---

### L-02: No Recovery Function (Low)

**Location:** Contract-wide

**Description:**
The contract lacks `receive()`, `ownerWithdraw()`, or fallback functions to recover accidentally sent ETH or tokens.

**Impact:** Low - Any ETH sent directly or stuck from failed payments cannot be recovered.

**Recommendation:** Consider adding an `ownerWithdraw()` function.

---

### L-03: SimpleToken Ownership Not Transferable (Low)

**Location:** SimpleToken contract (Lines 25, 32-35)

**Description:**
The SimpleToken owner is set at construction and cannot be transferred.

**Impact:** Low - If owner key is compromised, there's no recovery for mintable tokens.

**Recommendation:** Acceptable for simple token use cases.

---

### I-01: CREATE2 Salt Includes All Parameters (Informational)

**Location:** Line 226

**Description:**
The salt properly includes all parameters ensuring unique addresses per configuration.

```solidity
bytes32 salt = keccak256(abi.encodePacked(msg.sender, name, symbol, decimals, initialSupply, mintable));
```

**Impact:** None - Good practice.

---

## Security Best Practices Checklist

| Category | Status | Notes |
|----------|--------|-------|
| Reentrancy Protection | OK | No state changes after external calls |
| Integer Overflow/Underflow | OK | Solidity 0.8+ |
| Access Control | OK | Owner checks in SimpleToken |
| Input Validation | OK | Empty name/symbol checks |
| Event Emission | OK | Comprehensive events |
| CREATE2 Usage | OK | Deterministic deployment |

---

## Gas Optimizations

| Optimization | Status |
|--------------|--------|
| Bit shift for 50% | OK (`>> 1`) |
| Unchecked loops | Could be added |
| Storage packing | OK |

---

## Conclusion

TokenFactory.sol is a well-designed factory contract with proper CREATE2 implementation. The premium/referral system works correctly. Minor improvements could include adding fund recovery functions.

**Overall Assessment:** Production-ready with minor recommendations.
