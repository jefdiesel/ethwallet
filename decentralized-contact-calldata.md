# Decentralized Contact in Calldata

## The Concept

A contact as an ethscription is a data inscription that declares identity from a wallet address. The address itself is the proof of identity. No ENS, no server, no registry contract.

## Basic Contact Card

```
data:application/json,{"p":"contact","v":1,"name":"jef","bio":"...","links":{"twitter":"...","github":"..."}}
```

Inscribed from your wallet, this is a self-authenticating contact card. The wallet that created it IS the verification.

## What Makes It Decentralized

- **No contract owns it** — it's just calldata from your address
- **No service controls it** — any indexer can read it
- **No domain needed** — your wallet address is your identifier
- **Immutable proof** — the chain proves you published it

## Schema

```json
{
  "p": "contact",
  "v": 1,
  "name": "",
  "bio": "",
  "avatar": "",
  "links": {
    "twitter": "",
    "github": "",
    "website": "",
    "discord": "",
    "telegram": "",
    "email": ""
  }
}
```

| Field | Description |
|-------|-------------|
| `p` | Protocol identifier, always `contact` |
| `v` | Version number, increment on update |
| `name` | Display name |
| `bio` | Short description |
| `avatar` | Data URI or ethscription ID referencing an image |
| `links` | Key-value pairs of platform and handle/URL |

## Updates

Inscribe a new contact with a higher `v`. Clients read the latest version from your address matching the contact schema.

```
data:application/json,{"p":"contact","v":2,"name":"jef","bio":"updated bio","links":{...}}
```

Resolution rule: find all ethscriptions from an address where `p` = `contact`, use the one with the highest `v`.

## Web of Trust

Contacts can reference each other through trust inscriptions:

```
data:application/json,{"p":"contact","op":"trust","addr":"0xabc..."}
```

Revoke trust:

```
data:application/json,{"p":"contact","op":"untrust","addr":"0xabc..."}
```

This builds a social graph entirely from calldata. Anyone can crawl L1 and reconstruct the full web of trust. No contract, no service — just inscriptions pointing at other inscriptions.

## Discovery

### By Address

Query any indexer for ethscriptions created by a specific address where content starts with `data:application/json,{"p":"contact"`.

### By Trust Graph

1. Start from a known address
2. Read their trust inscriptions
3. Resolve each trusted address's contact card
4. Recurse to build a contact network

### By Name Search

Indexers can build a lookup table of `name` fields to addresses. Conflicts are resolved by earliest inscription or trust weight.

## Avatar as Ethscription

Instead of embedding image data in the contact card, reference another ethscription by ID:

```json
{
  "p": "contact",
  "v": 1,
  "name": "jef",
  "avatar": "0x1234...abcd"
}
```

The avatar image lives as its own ethscription. Composable, reusable, and doesn't bloat the contact inscription.

## Why No Smart Contract

A contact system doesn't need a smart contract. It needs:

1. **A schema** — that clients agree to interpret
2. **An address** — as the identity anchor
3. **Calldata** — as the storage layer
4. **Convention** — as the protocol

The protocol is the convention, not the code. Any client that reads L1 calldata and applies the same rules arrives at the same state. This is the ethscriptions philosophy applied to identity.

## Properties

| Property | How It's Achieved |
|----------|-------------------|
| Self-sovereign | Your wallet signs it |
| Censorship-resistant | Lives on Ethereum L1 calldata |
| Portable | Any client can read it from any node |
| Verifiable | On-chain signature proves authorship |
| Composable | References other inscriptions by ID |
| Updatable | New version inscriptions supersede old ones |
| No infrastructure | No server, no DNS, no contract deployment |
