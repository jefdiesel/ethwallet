# ESIP Proposal: Ethscription Lookup Contract

## Problem

The mainnet tx hash is the canonical identifier for ethscriptions — it's what users know, what's shown on ethscriptions.com, and what wallets display. However, finding an ethscription on the appchain explorer requires:

1. Knowing the master token ID (a 78-digit number derived from the tx hash)
2. Or knowing the collection contract address AND the collection-specific token ID

There's no simple way to go from mainnet tx hash → appchain token page.

Currently, to resolve a mainnet tx hash to its appchain location, you must chain 3-4 contract calls:
1. `getEthscriptionTokenId(bytes32)` on manager → master token ID
2. `getMembershipOfEthscription(bytes32)` on manager → collection ID + collection token ID
3. `getCollectionAddress(bytes32)` on manager → collection contract address
4. `ownerOf(uint256)` on collection → current owner

This is cumbersome for users and developers.

---

## Proposed Solution

Deploy a **lookup contract** on the appchain that aggregates these calls into a single view function:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IManager {
    function getEthscriptionTokenId(bytes32 ethscriptionId) external view returns (uint256);
    function getMembershipOfEthscription(bytes32 ethscriptionId) external view returns (bytes32 collectionId, uint256 collectionTokenId);
    function getCollectionAddress(bytes32 collectionId) external view returns (address);
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract EthscriptionLookup {
    address constant MANAGER = 0x3300000000000000000000000000000000000006;
    address constant MASTER = 0x3300000000000000000000000000000000000001;

    struct Result {
        uint256 masterTokenId;
        address masterContract;
        address collectionContract;
        uint256 collectionTokenId;
        address owner;
        bool inCollection;
    }

    function lookup(bytes32 mainnetTxHash) external view returns (Result memory) {
        IManager manager = IManager(MANAGER);

        uint256 masterTokenId = manager.getEthscriptionTokenId(mainnetTxHash);
        require(masterTokenId != 0, "Ethscription not found");

        Result memory r;
        r.masterTokenId = masterTokenId;
        r.masterContract = MASTER;

        // Check collection membership
        (bytes32 collectionId, uint256 collectionTokenId) = manager.getMembershipOfEthscription(mainnetTxHash);

        if (collectionId != bytes32(0)) {
            r.inCollection = true;
            r.collectionContract = manager.getCollectionAddress(collectionId);
            r.collectionTokenId = collectionTokenId;
            r.owner = IERC721(r.collectionContract).ownerOf(collectionTokenId);
        } else {
            r.inCollection = false;
            r.owner = IERC721(MASTER).ownerOf(masterTokenId);
        }

        return r;
    }

    // Convenience: return explorer URLs as strings
    function lookupWithUrls(bytes32 mainnetTxHash) external view returns (
        Result memory result,
        string memory masterUrl,
        string memory collectionUrl
    ) {
        result = this.lookup(mainnetTxHash);

        masterUrl = string(abi.encodePacked(
            "https://explorer.ethscriptions.com/token/",
            toHexString(result.masterContract),
            "/instance/",
            toString(result.masterTokenId)
        ));

        if (result.inCollection) {
            collectionUrl = string(abi.encodePacked(
                "https://explorer.ethscriptions.com/token/",
                toHexString(result.collectionContract),
                "/instance/",
                toString(result.collectionTokenId)
            ));
        }
    }

    // --- String helpers ---
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) >> 4) & 0xf];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0xf];
        }
        return string(str);
    }
}
```

---

## Usage

### Programmatic (any RPC client)

```javascript
// eth_call to lookup contract
const data = "0x" + keccak256("lookup(bytes32)").slice(0, 8) + mainnetTxHash.slice(2);
const result = await eth_call({ to: LOOKUP_CONTRACT, data }, "latest");
// Decode result struct
```

Or with ethers.js/viem:
```javascript
const { masterTokenId, collectionContract, collectionTokenId, owner } =
  await lookupContract.lookup(mainnetTxHash);
```

### Via Blockscout UI (no code required)

1. Go to `explorer.ethscriptions.com/address/{LOOKUP_CONTRACT}`
2. Click "Read Contract"
3. Find `lookup` function
4. Paste mainnet tx hash (e.g. `0x663d852b815d38fc0f84ca840e591258974f4f6db1a714eb39247e752c415fcd`)
5. Click "Query"
6. See result with master token ID, collection contract, token ID, owner

---

## Benefits

- **One call** — Replaces 3-4 chained contract calls
- **Works with stock Blockscout** — No fork or customization needed
- **Fully on-chain** — No database, no API dependency, trustless
- **Programmatic access** — Any RPC client can query it
- **Human access** — Blockscout's "Read Contract" UI works out of the box
- **Returns URLs** — `lookupWithUrls()` gives ready-to-use explorer links

---

## Deployment

Could be deployed by anyone, but ideally deployed by the Ethscriptions team at a memorable address (e.g. `0x3300000000000000000000000000000000000007` if using CREATE2 with the right salt).

---

## Alternative: Add to Manager Contract

Instead of a separate contract, this could be added to the manager contract (`0x3300...0006`) via upgrade:

```solidity
function lookup(bytes32 mainnetTxHash) external view returns (...) { ... }
```

This keeps everything in one place and avoids deploying a new contract.
