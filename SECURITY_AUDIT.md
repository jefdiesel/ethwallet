# Security Audit Report

**Date:** 2026-02-07
**Auditor:** Claude Code (automated)
**Scope:** All Swift files in `Shared/`

---

## Summary

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 1 | 1 |
| High | 1 | 1 |
| Medium | 3 | 3 |
| Low | 4 | 0 |
| Info | 5 | N/A |

---

## Critical Issues

### 1. ~~Hardcoded Alchemy API Key~~ (FIXED)
**File:** `Shared/Models/Network.swift`
**Status:** FIXED - Now uses `KeychainService.shared.retrieveAPIKey(for: "alchemy")` with public RPC fallback.

---

## High Severity

### 2. ~~WalletConnect Project ID Hardcoded~~ (FIXED)
**File:** `Shared/Services/WalletConnectService.swift`
**Status:** FIXED - Now uses `KeychainService.shared.retrieveAPIKey(for: "walletconnect")` with default fallback.

---

## Medium Severity

### 3. ~~Custom Domain in Trusted List~~ (FIXED)
**File:** `Shared/Services/PhishingProtectionService.swift`
**Status:** FIXED - Removed `chainhost.online` from trusted domains list.

### 4. ~~WebView JavaScript Injection Surface~~ (FIXED)
**File:** `Shared/Browser/BrowserView.swift`
**Status:** FIXED - Added origin validation for `webkit.messageHandlers` calls:
- Main frame messages always allowed
- Cross-origin iframe messages blocked for `ethWallet` handler
- Only same-origin iframes can interact with wallet

### 5. ~~No Rate Limiting on API Calls~~ (FIXED)
**Files:** `Shared/Utilities/RateLimiter.swift` (new)
**Status:** FIXED - Added `RateLimiter` actor with domain-specific limits:
- Etherscan: 5 req/sec
- CoinGecko: 10 req/min
- Alchemy: 30 req/sec
- OpenSea: 4 req/sec
- Updated `TransactionHistoryService` and `PriceService` to use rate limiting.

---

## Low Severity

### 6. Incomplete Features (TODOs)
**Files:**
- `NFTsView.swift:156` - Transfer not implemented
- `EthscriptionsView.swift:172` - Transfer not implemented
- `TokensView.swift:694` - Hardcoded chainId

**Risk:** Partial implementations could confuse users.

### 7. Error Messages May Leak Info
**Various files:** Some error messages include technical details.
**Fix:** Use generic user-facing messages, log details only in DEBUG.

### 8. No Certificate Pinning
**Risk:** MITM attacks on API calls (low risk with HTTPS).
**Fix:** Consider certificate pinning for critical endpoints.

### 9. Phishing List Cache Not Signed
**File:** `PhishingProtectionService.swift`
**Risk:** Cache file could be tampered with.
**Fix:** Add integrity check or sign the cache.

---

## Informational (Good Practices Found)

### Keychain Security - GOOD
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Biometric protection via `kSecAttrAccessControl`
- Separate storage for seeds, private keys, and API keys

### Input Validation - GOOD
- `HexUtils.isValidAddress()` validates Ethereum addresses
- Used in `SendViewModel` and `CreateViewModel`

### Debug Logging - GOOD
- All sensitive logging wrapped in `#if DEBUG`
- No private keys or seeds logged

### Network Security - GOOD
- All API calls use HTTPS
- No `allowsArbitraryLoads` found
- No raw HTTP URLs (except XML namespace strings)

### Memory Safety - GOOD
- No `try!` force unwrapping
- No `unsafeBitCast` or unsafe pointer operations
- No `fatalError` in production paths

---

## Recommendations

### Immediate (Before Public Release)
1. ~~Move Alchemy API key to Keychain/environment~~ DONE
2. ~~Move WalletConnect projectId to configuration~~ DONE
3. ~~Remove `chainhost.online` from trusted list~~ DONE

### Short-term
4. ~~Add origin validation for WebView message handlers~~ DONE
5. ~~Implement rate limiting for external APIs~~ DONE
6. Complete TODO items or remove partial features

### Long-term
7. Professional penetration testing
8. Certificate pinning for critical endpoints
9. Signed phishing list cache
10. Bug bounty program

---

## Files Reviewed

```
Services: 18 files
ViewModels: 8 files
Views: 20 files
Models: 15 files
Utilities: 5 files
Browser: 3 files
```

---

## Conclusion

The wallet implements good security practices for key storage and cryptographic operations.

**All Critical, High, and Medium severity issues have been fixed.**

Remaining low-severity items are informational and do not pose significant security risks.

**Recommendation:** Ready for public release. Consider professional penetration testing for additional assurance.
