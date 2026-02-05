# Ethscriptions Appchain: Collection & Item Lookup

This document describes how to look up collection membership and item details for any ethscription on the Ethscriptions Appchain.

## Overview

The appchain at `mainnet.ethscriptions.com` provides on-chain collection management through two contract types:

1. **Manager Contract** - Global registry for all collections
2. **Collection Contracts** - Per-collection ERC-721 compatible contracts

## RPC Endpoint

```
https://mainnet.ethscriptions.com
```

All calls use standard Ethereum JSON-RPC `eth_call`.

---

## Manager Contract

**Address:** `0x3300000000000000000000000000000000000006`

### Methods

#### `getEthscriptionTokenId(bytes32 ethscriptionId)`

Returns the token ID for an ethscription within its collection.

```
Selector: 0x7e6d9544
Input: ethscription ID (32 bytes, padded)
Output: uint256 tokenId
```

#### `getMembershipOfEthscription(bytes32 ethscriptionId)`

Returns collection membership info for an ethscription.

```
Selector: 0x73a3a428
Input: ethscription ID (32 bytes)
Output: (address collectionContract, uint256 tokenId, ...)
```

#### `isInCollection(bytes32 ethscriptionId, bytes32 collectionId)`

Check if an ethscription belongs to a specific collection.

```
Selector: 0x4f8df83f
Input: ethscription ID (32 bytes) + collection ID (32 bytes)
Output: bool
```

---

## Collection Contract

Each collection has its own ERC-721 compatible contract. Example:

| Collection | Contract Address |
|------------|------------------|
| Milady on-chain | `0x015Dfb804BFE6EBb921c1D05cb83C1aB02EBEf08` |
| Call Data Comrades | `0xBB41...` |

### Methods

#### `tokenURI(uint256 tokenId)`

Returns full metadata JSON for a token.

```
Selector: 0xc87b56dd
Input: tokenId (uint256, 32 bytes padded)
Output: ABI-encoded string (data URI)
```

**Response format:**
```json
{
  "name": "Milady 1",
  "ethscription_id": "0x36c7d4453c0c7ff591a102c11a1b1c387b9610ada800cc93456f1ca68bec2974",
  "ethscription_number": 812531,
  "image": "data:image/svg+xml;base64,...",
  "attributes": [
    { "trait_type": "Background", "value": "Pink" },
    { "trait_type": "Eyes", "value": "Closed" }
  ]
}
```

#### `ownerOf(uint256 tokenId)`

Returns the current owner of a token on the appchain.

```
Selector: 0x6352211e
Input: tokenId (uint256)
Output: address
```

#### `balanceOf(address owner)`

Returns how many tokens an address owns in this collection.

```
Selector: 0x70a08231
Input: owner address (20 bytes, padded to 32)
Output: uint256
```

#### `tokenOfOwnerByIndex(address owner, uint256 index)`

Returns the token ID at a given index for an owner (ERC-721 Enumerable).

```
Selector: 0x2f745c59
Input: owner (32 bytes) + index (32 bytes)
Output: uint256 tokenId
```

---

## Example: Lookup Flow

### 1. Get collection info from ethscription ID

```javascript
const ethscriptionId = "0x36c7d4453c0c7ff591a102c11a1b1c387b9610ada800cc93456f1ca68bec2974";

// Call Manager.getMembershipOfEthscription
const result = await rpcCall("eth_call", [{
  to: "0x3300000000000000000000000000000000000006",
  data: "0x73a3a428" + ethscriptionId.slice(2).padStart(64, "0")
}, "latest"]);

// Decode to get collection address and tokenId
```

### 2. Get item metadata from collection

```javascript
const collectionAddress = "0x015Dfb804BFE6EBb921c1D05cb83C1aB02EBEf08";
const tokenId = 1;

// Call Collection.tokenURI
const tokenIdHex = tokenId.toString(16).padStart(64, "0");
const result = await rpcCall("eth_call", [{
  to: collectionAddress,
  data: "0xc87b56dd" + tokenIdHex
}, "latest"]);

// Decode ABI string response
const hex = result.slice(2);
const offset = parseInt(hex.slice(0, 64), 16) * 2;
const length = parseInt(hex.slice(offset, offset + 64), 16);
const strHex = hex.slice(offset + 64, offset + 64 + length * 2);
const uri = strHex.match(/.{2}/g).map(b => String.fromCharCode(parseInt(b, 16))).join("");

// Parse the data URI
let metadata;
if (uri.startsWith("data:application/json;base64,")) {
  metadata = JSON.parse(atob(uri.slice(29)));
} else if (uri.startsWith("data:application/json,")) {
  metadata = JSON.parse(decodeURIComponent(uri.slice(22)));
}

console.log(metadata);
// { name: "Milady 1", ethscription_id: "0x...", image: "data:image/svg+xml;base64,...", attributes: [...] }
```

---

## Batch Requests

The RPC supports batch requests for efficiency:

```javascript
const batch = [];
for (let i = 1; i <= 50; i++) {
  batch.push({
    jsonrpc: "2.0",
    id: i,
    method: "eth_call",
    params: [{
      to: collectionAddress,
      data: "0xc87b56dd" + i.toString(16).padStart(64, "0")
    }, "latest"]
  });
}

const response = await fetch("https://mainnet.ethscriptions.com", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(batch)
});

const results = await response.json();
```

---

## Notes

- The `ethscription_id` in metadata matches the L1 Ethereum transaction hash that created the ethscription
- Images are typically base64-encoded SVGs containing embedded PNGs for pixel art
- Token IDs are 1-indexed (start at 1, not 0)
- The appchain mirrors L1 ownership - transfers on L1 are reflected on the appchain
