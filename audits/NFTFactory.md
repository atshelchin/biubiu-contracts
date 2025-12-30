# Solidity Audit Report

## NFTFactory.sol

**Contract Version:** Solidity ^0.8.20
**Audit Date:** 2025-12-30
**Risk Level:** LOW

**Repository:** https://github.com/atshelchin/biubiu-contracts
**Commit:** `6458249a0e952c96f401bbd3755dfdbee9405828`
**Auditor:** Claude (AI Security Review)

---

## Executive Summary

NFTFactory is a factory contract for deploying ERC721 NFT collections (SocialNFT) with CREATE2 deterministic addresses. It includes premium membership integration, referral fees, and creates NFTs with random traits and social "drift" features.

---

## Contract Overview

| Property | Value |
|----------|-------|
| Lines of Code | 619 |
| External Dependencies | IBiuBiuPremium, INFTMetadata |
| Reentrancy Guard | Yes (1/2 pattern) |
| Owner | Immutable constant |
| Fee | 0.005 ETH (non-members) |

---

## Contracts Included

1. **NFTFactory** - Factory for deploying SocialNFT
2. **SocialNFT** - ERC721 with traits, drift history, and on-chain metadata

---

## Findings

### L-01: Silent Payment Failures (Low)

**Location:** Lines 146-159

**Description:**
Referrer and owner payment failures are silently ignored.

```solidity
(bool success,) = payable(referrer).call{value: referralAmount}("");
if (success) {
    emit ReferralPaid(referrer, msg.sender, referralAmount);
}
```

**Impact:** Low - Funds may remain in contract. Intentional design to prevent griefing.

---

### L-02: No Fund Recovery (Low)

**Location:** NFTFactory contract

**Description:**
NFTFactory lacks `receive()` and `ownerWithdraw()` functions to recover stuck funds.

**Impact:** Low - Any ETH from failed payments cannot be recovered.

---

### L-03: Predictable Randomness (Low)

**Location:** SocialNFT Lines 566-578

**Description:**
Trait generation uses block-based entropy which miners could theoretically manipulate.

```solidity
uint256 seed = uint256(keccak256(abi.encodePacked(
    block.timestamp, block.prevrandao, hash1, hash2, msg.sender, tokenId, totalSupply, address(this)
)));
```

**Impact:** Low - For cosmetic NFT traits, this is acceptable. Not suitable for high-value outcomes.

---

### I-01: External Metadata Contract Dependency (Informational)

**Location:** SocialNFT Line 267

**Description:**
SocialNFT depends on external NFTMetadata contract at hardcoded address.

```solidity
address public constant METADATA_CONTRACT = 0xF68B52ceEAFb4eDB2320E44Efa0be2EBe7a715A6;
```

**Impact:** Informational - If NFTMetadata is not deployed, tokenURI will fail.

---

### I-02: Drift History Gas Considerations (Informational)

**Location:** SocialNFT Lines 317, 485

**Description:**
Drift history grows unbounded with transfers. Very active tokens may have large arrays.

**Impact:** Informational - Paginated getters are provided to mitigate.

---

## Security Best Practices Checklist

| Category | Status | Notes |
|----------|--------|-------|
| Reentrancy Protection | OK | 1/2 pattern in NFTFactory |
| Integer Overflow/Underflow | OK | Solidity 0.8+ with unchecked where safe |
| Access Control | OK | onlyOwner for minting |
| Input Validation | OK | Name/symbol empty checks |
| Event Emission | OK | Comprehensive coverage |
| ERC721 Compliance | OK | Full implementation with safeTransfer |

---

## Gas Optimizations

| Optimization | Status |
|--------------|--------|
| Unchecked increments | OK |
| Bit shift for percentages | OK |
| Pagination for large arrays | OK |

---

## Conclusion

NFTFactory.sol is a feature-rich NFT factory with social features. The implementation is secure with proper reentrancy protection. The drift/message system is unique and well-implemented.

**Overall Assessment:** Production-ready with minor recommendations for fund recovery.
