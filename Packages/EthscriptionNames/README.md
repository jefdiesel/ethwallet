# EthscriptionNames

A Swift package for parsing, validating, and resolving Ethscription names.

Ethscription names are human-readable identifiers stored on Ethereum using the [Ethscriptions protocol](https://docs.ethscriptions.com). They work similarly to ENS names but use ethscriptions instead of smart contracts.

## Features

- Parse and validate Ethscription name formats
- Compute content hashes for API lookups
- Build transaction calldata for claiming names
- Resolve names to Ethereum addresses
- Reverse lookup: find names owned by an address
- Transfer names between addresses
- Bulk transfers (ESIP-5)

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/EthscriptionNames.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Packages → enter the repository URL.

## Quick Start

```swift
import EthscriptionNames

// Parse a name
let name = try EthscriptionName("alice")
print(name.displayName)  // "alice.eths"
print(name.contentURI)   // "data:,alice"
print(name.contentHash)  // "0x..." (SHA-256)

// Resolve to an address
let resolver = EthscriptionNameResolver()
let owner = try await resolver.resolve("alice")
print(owner)  // "0x1234...abcd"

// Build a claim transaction
let tx = try EthscriptionNameTransaction.claim("myname", from: myAddress)
// Use tx.to, tx.value, tx.calldata with your web3 library
```

## How Ethscription Names Work

### The Protocol

1. **Format**: Names are inscribed as `data:,{name}` in transaction calldata
2. **Identity**: The SHA-256 hash of the content uniquely identifies the name
3. **First-come-first-serve**: Only the first valid inscription counts
4. **Transferable**: Names can be transferred like any ethscription

### Creating a Name

To claim a name, send a transaction **to yourself** with the name encoded as calldata:

```
Transaction {
    from: 0xYourAddress
    to:   0xYourAddress  // Self-inscription
    value: 0
    data: 0x646174613a2c616c696365  // hex("data:,alice")
}
```

The ethscription is created when the transaction is mined. You now own "alice".

### Resolving a Name

To find who owns a name:

1. Compute the content: `data:,{name}`
2. Hash with SHA-256
3. Query the API for the ethscription with that content hash
4. Return the `current_owner` field

### Transferring a Name

To transfer a name (or any ethscription):

```
Transaction {
    from: 0xCurrentOwner
    to:   0xNewOwner
    value: 0
    data: 0x{ethscription_transaction_hash}  // The ID of the ethscription
}
```

## API Reference

### EthscriptionName

Represents a parsed and validated name.

```swift
// Create from string
let name = try EthscriptionName("alice")
let name = try EthscriptionName("alice.eths")  // .eths suffix is optional

// Properties
name.name          // "alice" (normalized)
name.displayName   // "alice.eths"
name.contentURI    // "data:,alice"
name.contentHash   // "0x..." (SHA-256 hash)
name.calldata      // "0x..." (hex-encoded content URI)

// Validation
EthscriptionName.isValid("alice")  // true
EthscriptionName.isValid("")       // false
EthscriptionName.isValid("a b")    // false (spaces not allowed)
```

#### Name Rules

- **Length**: 1-64 characters
- **Characters**: Letters, numbers, hyphens, underscores, dots
- **Case**: Case-insensitive (normalized to lowercase)
- **Suffix**: `.eths` suffix is optional and stripped during parsing

### EthscriptionNameResolver

Resolves names via the Ethscriptions API.

```swift
let resolver = EthscriptionNameResolver()

// Forward resolution
let owner = try await resolver.resolve("alice")

// Check if name exists
let exists = try await resolver.exists("alice")

// Get full details
let result = try await resolver.lookup("alice")
print(result?.owner)
print(result?.transactionHash)

// Reverse resolution
let names = try await resolver.reverseResolve("0x1234...")
```

#### Caching

Results are cached for 5 minutes by default:

```swift
resolver.cacheExpiry = 600  // 10 minutes
resolver.clearCache()        // Clear all cached results
resolver.pruneCache()        // Remove expired entries only
```

### EthscriptionNameTransaction

Builds transaction parameters for name operations.

```swift
// Claim a new name
let claimTx = try EthscriptionNameTransaction.claim("myname", from: myAddress)

// Transfer a name
let transferTx = EthscriptionNameTransaction.transfer(
    ethscriptionId: "0x...",  // The ethscription's transaction hash
    to: recipientAddress
)

// Bulk transfer (ESIP-5)
let bulkTx = EthscriptionNameTransaction.bulkTransfer(
    ethscriptionIds: ["0x...", "0x...", "0x..."],
    to: recipientAddress
)

// Transaction properties
tx.to        // Recipient address
tx.value     // "0x0" (always zero)
tx.calldata  // Hex-encoded data

// Gas estimation
tx.estimatedGasLimit
tx.estimateCost(gasPriceWei: 30_000_000_000)
```

### Errors

```swift
enum EthscriptionNameError: Error {
    case emptyName
    case invalidFormat(String)
    case nameNotFound(String)
    case networkError(String)
    case invalidResponse
    case rateLimited
    case apiUnavailable
}
```

## Integration Examples

### With web3swift

```swift
import web3swift
import EthscriptionNames

// Claim a name
let name = try EthscriptionName("myname")
let tx = EthscriptionNameTransaction.claim(name, from: myAddress)

var transaction = CodableTransaction(
    to: EthereumAddress(tx.to)!,
    value: 0,
    data: Data(hex: tx.calldata)
)

try await web3.eth.send(transaction)
```

### With WalletConnect

```swift
import EthscriptionNames

let tx = try EthscriptionNameTransaction.claim("myname", from: address)

let params: [String: Any] = [
    "from": address,
    "to": tx.to,
    "value": tx.value,
    "data": tx.calldata
]

try await walletConnect.sendTransaction(params)
```

## Testing

```bash
swift test
```

## License

MIT License - see LICENSE file.

## Resources

- [Ethscriptions Protocol](https://docs.ethscriptions.com)
- [Ethscriptions API](https://api.ethscriptions.com)
- [Ethscriptions Explorer](https://ethscriptions.com)
- [ESIP-5: Bulk Transfers](https://docs.ethscriptions.com/esips/esip-5)
