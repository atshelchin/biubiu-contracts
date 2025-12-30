# Solidity Audit Report

## BiuBiuPremium.sol

**Contract Version:** Solidity ^0.8.20
**Audit Date:** 2025-12-30
**Risk Level:** LOW

**Repository:** https://github.com/atshelchin/biubiu-contracts
**Commit:** `6458249a0e952c96f401bbd3755dfdbee9405828`
**Auditor:** Claude (AI Security Review)

---

## Executive Summary

BiuBiuPremium is an NFT-based subscription system implementing ERC721 without external dependencies. Users can purchase time-limited premium subscriptions across three tiers (Daily, Monthly, Yearly) with an optional referral system.

---

## Contract Overview

| Property | Value |
|----------|-------|
| Lines of Code | 654 |
| External Dependencies | None (custom ERC721) |
| Reentrancy Guard | Yes (1/2 pattern) |
| Owner | Immutable constant |
| Pricing | Daily: 0.01 ETH, Monthly: 0.05 ETH, Yearly: 0.1 ETH |

---

## Subscription Tiers

| Tier | Price | Duration |
|------|-------|----------|
| Daily | 0.01 ETH | 1 day |
| Monthly | 0.05 ETH | 30 days |
| Yearly | 0.1 ETH | 365 days |

---

## Findings

### L-01: Unchecked Low-Level Call to Owner (Low)

**Location:** Line 384

**Description:**
Payment to OWNER uses unchecked low-level call. If owner is a reverting contract, funds remain in contract.

```solidity
payable(OWNER).call{value: contractBalance}("");
```

**Impact:** Low - Funds recoverable via `ownerWithdraw()`.

---

### L-02: Silent Referral Payment Failure (Low)

**Location:** Lines 367-376

**Description:**
When referral payment fails, transaction continues with `referralAmount` reset to 0.

```solidity
(bool referralSuccess,) = payable(referrer).call{value: referralAmount}("");
if (referralSuccess) {
    emit ReferralPaid(referrer, referralAmount);
} else {
    referralAmount = 0;
}
```

**Impact:** Low - Referrer may unknowingly miss payments. Consider adding `ReferralFailed` event.

---

### L-03: Auto-Activation on Transfer (Low)

**Location:** Lines 236-239

**Description:**
NFTs are automatically activated for recipients who have no active subscription.

```solidity
if (activeSubscription[to] == 0) {
    activeSubscription[to] = tokenId;
    emit Activated(to, tokenId);
}
```

**Impact:** Low - May be unexpected behavior but is beneficial UX.

---

### I-01: Hardcoded Owner Address (Informational)

**Location:** Line 57

**Description:**
Owner address is immutable constant, preventing ownership transfer.

```solidity
address public constant OWNER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;
```

**Impact:** Informational - Intentional design choice for simplicity.

---

### I-02: Renewal Count Overflow (Informational)

**Location:** Lines 353-355

**Description:**
Renewal count uses `unchecked` but overflow is practically impossible.

```solidity
unchecked {
    _tokenAttributes[tokenId].renewalCount += 1;
}
```

**Impact:** None - Would require 2^256 renewals.

---

### I-03: On-Chain SVG Generation (Informational)

**Location:** Lines 552-607

**Description:**
Full on-chain SVG generation for tokenURI. Different visuals for Active vs Expired status.

**Impact:** None - Good for full decentralization.

---

## Security Best Practices Checklist

| Category | Status | Notes |
|----------|--------|-------|
| Reentrancy Protection | OK | 1/2 pattern |
| Integer Overflow/Underflow | OK | Solidity 0.8+ |
| Access Control | OK | Token owner checks |
| Input Validation | OK | Zero address, payment checks |
| CEI Pattern | OK | State before external calls |
| ERC721 Compliance | OK | Full implementation |
| Safe Mint | OK | Receiver capability check |

---

## Gas Optimizations

| Optimization | Status |
|--------------|--------|
| Custom errors | OK |
| Immutable constants | OK |
| Bit shift for 50% | OK |
| Unchecked math | OK |
| Packed struct | Could optimize TokenAttributes |

---

## ERC721 Implementation

| Function | Status |
|----------|--------|
| balanceOf | OK |
| ownerOf | OK |
| approve | OK |
| getApproved | OK |
| setApprovalForAll | OK |
| isApprovedForAll | OK |
| transferFrom | OK |
| safeTransferFrom | OK |
| tokenURI | OK (on-chain) |
| supportsInterface | OK |

---

## Conclusion

BiuBiuPremium.sol is a well-designed subscription NFT contract with proper security measures. The custom ERC721 implementation is correct, and the subscription/referral system is sound.

**Key Strengths:**
- Proper reentrancy protection
- CEI pattern adherence
- Gas-efficient design
- Full on-chain metadata

**Overall Assessment:** Production-ready.
