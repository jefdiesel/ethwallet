# Security Audit Report

**Date:** 2026-02-07
**Auditor:** Claude Code (automated)
**Scope:** All Swift files in `Shared/`

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 1 |
| Medium | 3 |
| Low | 4 |
| Info | 5 |

---

## Critical Issues

### 1. Hardcoded Alchemy API Key
**File:** `Shared/Models/Network.swift:28`
```swift
rpcURL: URL(string: "https://eth-mainnet.g.alchemy.com/v2/aLBw6VuSaJyufMkS2zgEZ")!,
```
**Risk:** API key exposed in source code. If repo is public, key can be extracted and abused.
**Fix:** Move to KeychainService or environment variable. Use `KeychainService.shared.retrieveAPIKey(for: "alchemy")`.

---

## High Severity

### 2. WalletConnect Project ID Hardcoded
**File:** `Shared/Services/WalletConnectService.swift:26`
```swift
private let projectId = "c10f1058133aeedd0549f82a1209c62c"
```
**Risk:** Project ID visible in source. Could be rate-limited or abused.
**Fix:** Move to configuration or Keychain.

---

## Medium Severity

### 3. Custom Domain in Trusted List
**File:** `Shared/Services/PhishingProtectionService.swift:36`
```swift
"chainhost.online"
```
**Risk:** Custom domain bypasses phishing checks. Verify ownership.
**Fix:** Remove if not owned, or document why it's trusted.

### 4. WebView JavaScript Injection Surface
**File:** `Shared/Browser/BrowserView.swift`
- Uses `WKWebView` with custom message handlers
- Injects `Web3Provider.js` into all pages
- `evaluateJavaScript` called with dynamic content

**Risk:** Malicious dApps could potentially exploit message passing.
**Mitigations in place:** WebKit sandboxing, origin checks in some places.
**Recommendation:** Add origin validation for all `webkit.messageHandlers` calls.

### 5. No Rate Limiting on API Calls
**Files:** Multiple services use `URLSession.shared` directly
**Risk:** Malicious input could trigger excessive API calls.
**Fix:** Add rate limiting wrapper for external API calls.

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
1. Move Alchemy API key to Keychain/environment
2. Move WalletConnect projectId to configuration
3. Verify `chainhost.online` ownership or remove from trusted list

### Short-term
4. Add origin validation for WebView message handlers
5. Implement rate limiting for external APIs
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

The wallet implements good security practices for key storage and cryptographic operations. The main concerns are:
- Hardcoded API keys (easily fixable)
- WebView attack surface (mitigated by WebKit sandboxing)

**Recommendation:** Safe for personal use and trusted testers. Address Critical and High issues before public release.
