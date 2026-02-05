# Ethscriptions Documentation - Complete Extraction

All content extracted from https://docs.ethscriptions.com/

---

## TABLE OF CONTENTS

1. [Home Page (Introducing Ethscriptions)](#page-1-home)
2. [AppChain Overview](#page-2-appchain-overview)
3. [Quick Start](#page-3-quick-start)
4. [Protocol Specification](#page-4-protocol-specification)
5. [What are ESIPs?](#page-5-what-are-esips)
6. [Accepted ESIPs](#page-6-accepted-esips)
7. [Draft ESIPs](#page-7-draft-esips)
8. [ESIP-1: Smart Contract Ethscription Transfers](#page-8-esip-1)
9. [ESIP-2: Safe Trustless Smart Contract Ethscription Escrow](#page-9-esip-2)
10. [ESIP-3: Smart Contract Ethscription Creations](#page-10-esip-3)
11. [ESIP-5: Bulk Ethscription Transfers from EOAs](#page-11-esip-5)
12. [ESIP-6: Opt-in Ethscription Non-uniqueness](#page-12-esip-6)
13. [ESIP-7: Support Gzipped Calldata in Ethscription Creation](#page-13-esip-7)
14. [ESIP-8: Ethscription Attachments aka "BlobScriptions"](#page-14-esip-8)
15. [Protocol Handlers](#page-15-protocol-handlers)
16. [Collections](#page-16-collections)
17. [Fixed Denomination Tokens](#page-17-fixed-denomination-tokens)
18. [Running a Node](#page-18-running-a-node)

---

<a id="page-1-home"></a>
# PAGE 1: HOME — https://docs.ethscriptions.com/

## Introducing Ethscriptions

### Overview

Ethscriptions are digital artifacts created by encoding data in Ethereum transaction calldata. Unlike smart contract-based NFTs that store data in contract storage, ethscriptions use calldata—making them significantly cheaper while remaining 100% on-chain, permissionless, and censorship resistant.

The Ethscriptions protocol allows users to create and transfer digital artifacts at a fraction of the cost of traditional NFTs. Today, ethscriptions are used for images, tokens, and programmable assets.

### The Ethscriptions AppChain

The Ethscriptions AppChain is a trust-minimized Ethereum L2 that provides cryptographic state, receipts, and EVM compatibility for ethscriptions. It uses a derivation pipeline that:

1. Observes Ethereum L1 calldata and events
2. Translates ethscription intents into deposit transactions
3. Executes them on an EVM with predeploy contracts

The AppChain is a Stage-2 rollup with no privileged roles—anyone can run a node and derive the canonical state from L1 data alone.

### Two Ways to Consume Ethscriptions

| Approach | Description |
|----------|-------------|
| Traditional Indexer | Off-chain service that indexes L1 transactions and maintains state in a database. Simple queries, existing integrations. |
| Ethscriptions AppChain | On-chain L2 with smart contracts, Merkle proofs, and EVM state. Enables protocol extensions, collections, and tokens. |

Both approaches read the same L1 data and produce the same canonical ethscription state.

### Links
* [Ethscriptions Protocol GitHub](https://github.com/ethscriptions-protocol/)
* [Ethscriptions.com](https://ethscriptions.com/)

### What is Calldata?

Ethscriptions are cheaper than smart contracts because they store data on-chain using Ethereum transaction calldata, not smart contract storage.

When you send someone eth via an Ethereum transaction, calldata is the "notes field." Sometimes people write things in the notes field, but typically when you send eth to a person you leave it blank. When you interact with a smart contract, however, you add the information you're passing to the smart contract—the function name and parameters—to the calldata field.

Ethscriptions encode data into calldata as Data URIs, but this information is not directed at smart contracts on L1. Instead, the AppChain's derivation node observes these Data URIs and translates them into L2 transactions.

This video breaks it down: [What are Ethscriptions? Venmo but you put an image in the "notes" field.](https://www.youtube.com/watch?v=SjVrSihJOkU)

### FAQ

**Are Ethscriptions secure and trustless?**

Yes. The Ethscriptions AppChain is a trust-minimized L2 with no privileged sequencer or admin roles. Anyone can run their own node and derive the canonical state from Ethereum L1 data. The derivation is deterministic—given the same L1 blocks, every node produces identical L2 state.

**Are Ethscriptions decentralized?**

Yes. Ethscriptions reinterpret existing Ethereum data, which is decentralized by nature. No one's permission is required to use Ethscriptions and no one can ban you from using it. The AppChain uses based sequencing, meaning L2 block ordering is determined by L1 block ordering—not by a centralized sequencer.

**How does the AppChain stay trust-minimized?**

The AppChain achieves trust-minimization through:

1. Based sequencing - L2 blocks are anchored to L1 blocks, preventing sequencer manipulation
2. Deterministic derivation - State can be independently verified from L1 data
3. No admin keys - No privileged roles that can pause, censor, or modify the chain
4. Open source - All code is publicly available for verification

**Who invented Ethscriptions?**

The first ethscription was created in 2016, but the formal protocol was developed by [Tom Lehman](https://twitter.com/dumbnamenumbers) and [Michael Hirsch](https://x.com/0xHirsch). In addition to Bitcoin inscriptions, he was inspired by the famous "proto-Ethscription" from the Poly Network hacker that you can see in [this transaction](https://etherscan.io/tx/0x0ae3d3ce3630b5162484db5f3bdfacdfba33724ffb195ea92a6056beaa169490).

The author writes: "ETHEREUM HAS THE POTENTIAL TO BE A SECURED AND ANONYMOUS COMMUNICATION CHANNEL, BUT ITS NOT FRIENDLY TO AVERAGE USERS..."

**More questions?**

Jump into the [Discord](https://discord.gg/ethscriptions)!

---

<a id="page-2-appchain-overview"></a>
# PAGE 2: APPCHAIN OVERVIEW — https://docs.ethscriptions.com/ethscriptions-appchain/overview

## What is the AppChain?

The Ethscriptions AppChain is an Ethereum Layer 2 that processes ethscriptions through a derivation pipeline that turns L1 ethscription activity into canonical L2 blocks.

### Key Features

- Merkle state with cryptographic proofs
- Transaction receipts for operations
- EVM compatibility with standard tooling

### Two Consumption Approaches

The document contrasts traditional indexers (off-chain, database-backed) with the AppChain (on-chain L2 with smart contracts), noting both read identical L1 data and produce canonical ethscription state.

| Approach | Description |
|----------|-------------|
| Traditional Indexer | Off-chain service that indexes L1 transactions and maintains state in a database. Simple queries, existing integrations. |
| AppChain | On-chain L2 with smart contracts, Merkle proofs, and EVM state. Enables protocol extensions, collections, and tokens. |

### Genesis Block Information

AppChain anchors to L1 block 17478949; Traditional Indexer uses 17478950. This one-block difference accommodates the AppChain's L2 genesis block containing initial state.

### Operational Process

The derivation pipeline involves observing L1 via JSON-RPC, translating intents into deposit transactions, executing via Engine API to geth, and sealing blocks with predeploy contract state mutations.

### AppChain-Exclusive Capabilities

- **Protocol Handlers** - pluggable extension system
- **Collections** - curated NFT collections with merkle enforcement
- **Fixed Denomination Tokens** - ERC-20 tokens in fixed batches tied to NFT notes

### Architecture Components

- **Derivation Node** - Ruby-based, observes L1, parses intents, builds deposits
- **Execution Client** - modified geth, executes transactions, maintains EVM state

### Advantages

Users benefit from preserved ethscription workflows with potential cost reductions for complex operations. Developers access standard EVM tooling and verifiable state, while validators can independently confirm state derivation from L1 data deterministically.

---

<a id="page-3-quick-start"></a>
# PAGE 3: QUICK START — https://docs.ethscriptions.com/overview/quick-start

## Quick Start

### Creating Ethscriptions

The process involves converting an image (max ~90KB) to Base64, then to hex, before sending a 0 ETH transaction with the hex data to the intended owner's address.

Steps:
1. Convert an image (max size: ~90KB) to a Base64-encoded data URI using services like base64-image.de
2. Convert to hex via tools like hexhero
3. Send a zero-value transaction to the intended owner with the hex data included
4. Await confirmation on the platform

### Duplicate Prevention

By default, duplicate content is rejected—only the first ethscription with a given data URI is valid. Add `rule=esip6` to your Data URI to permit duplicates per ESIP-6 specifications.

### Transfers

Transfers require identifying the ethscription's transaction hash ID and sending a 0 ETH transaction to the new proposed owner with that ID in the hex data field.

Multiple transfers can be batched by concatenating IDs without the "0x" prefix.

### Tracking Options

Users can either:
1. Rely on ethscriptions.com
2. Run their own indexer following the protocol specification (with open-source code available)
3. Operate an AppChain node for cryptographic state with Merkle proofs

### Inscription Methods

Two approaches exist:
1. Posting calldata directly to Ethereum L1 with Data URI hex data
2. Smart contracts emit `ethscriptions_protocol_CreateEthscription` events per ESIP-3 standards

The AppChain processes both methods and converts them into L2 transactions through a deterministic pipeline.

---

<a id="page-4-protocol-specification"></a>
# PAGE 4: PROTOCOL SPECIFICATION — https://docs.ethscriptions.com/overview/protocol-specification

## Protocol Specification

### Core Indexing Mechanism

The protocol determines state by indexing Ethereum transactions sequentially starting from designated genesis blocks. "Successful transactions" are required—those with `status == 1` or `null` (for older blocks).

### Genesis Blocks

Traditional indexer genesis blocks: `1608625, 3369985, 3981254, 5873780, 8205613, 9046950, 9046974, 9239285, 9430552, 10548855, 10711341, 15437996, 17478950`

AppChain L1 anchor block: `17478949`

### Data URI Validation

Any syntactically valid mimetype is allowed. The validation process requires Base64 strict decoding per RFC 4648, where `encode(decode(b64_string)) == b64_string` must be true.

### UTF-8 Conversion

Hex input data converts by removing the `0x` prefix, parsing pairs as hex bytes, decoding via TextDecoder, and removing null bytes.

### Creation Rules

Ethscriptions emerge from EOA transactions with valid data URIs as calldata when:
- The transaction has a recipient address
- The data URI is unique *or* the data uri has the parameter `rule=esip6`

Uniqueness requires no prior ethscription from earlier blocks or earlier transaction indices sharing the same SHA256 hash of the UTF-8 data URI.

### Creation Methods

1. **EOA transactions** with input data matching valid data URI format and a recipient address
2. **Smart contracts** under ESIP-3 (starting block 18130000)
3. **Compressed content** via ESIP-7 gzip support (block 19376500 onward)
4. **Blob attachments** under ESIP-8 (block 19526000 onward)

The transaction hash becomes the ethscription's ID, with the recipient as initial owner and sender as creator.

### Transfer Specifications

Valid transfers are ordered by block number, then transaction index.

**EOA direct transfers:** Transaction input data contains the ethscription ID. The sender must own the ethscription.

**ESIP-5 bulk transfers** (block 18330000+): If the input data of a transaction (without its leading 0x) is a sequence of 1 or more valid ethscription ids (without their leading 0x), that transaction will constitute a valid transfer for each ethscription that is owned by the transaction's creator.

**ESIP-1 smart contract transfers** (block 17672762+): Via `ethscriptions_protocol_TransferEthscription(address indexed recipient, bytes32 indexed ethscriptionId)` event

**ESIP-2 safe escrow transfers** (block 17764910+): Via `ethscriptions_protocol_TransferEthscriptionForPreviousOwner(address indexed previousOwner, address indexed recipient, bytes32 indexed ethscriptionId)` event

---

<a id="page-5-what-are-esips"></a>
# PAGE 5: WHAT ARE ESIPs? — https://docs.ethscriptions.com/esips/what-are-esips

## What are ESIPs?

Proposals for improvement to the Ethscriptions protocol.

---

<a id="page-6-accepted-esips"></a>
# PAGE 6: ACCEPTED ESIPs — https://docs.ethscriptions.com/esips/accepted-esips

## Accepted ESIPs

1. **ESIP-1: Smart Contract Ethscription Transfers** — LIVE
2. **ESIP-2: Safe Trustless Smart Contract Ethscription Escrow**
3. **ESIP-3: Smart Contract Ethscription Creations**
4. **ESIP-5: Bulk Ethscription Transfers from EOAs**
5. **ESIP-6: Opt-in Ethscription Non-uniqueness**
6. **ESIP-7: Support Gzipped Calldata in Ethscription Creation**
7. **ESIP-8: Ethscription Attachments aka "BlobScriptions"**

---

<a id="page-7-draft-esips"></a>
# PAGE 7: DRAFT ESIPs — https://docs.ethscriptions.com/esips/draft-esips

## Draft ESIPs

(No content — page contains only the heading "Draft ESIPs")

---

<a id="page-8-esip-1"></a>
# PAGE 8: ESIP-1 — https://docs.ethscriptions.com/esips/accepted-esips/esip-1-smart-contract-ethscription-transfers

## ESIP-1: Smart Contract Ethscription Transfers

### Version History

* June 29: Changed event name to be more explicit and to reduce changes of collision.
* June 29: Added spec for case in which there are multiple transfers in a given transaction.

### Specification

Incorporate one new smart contract event into the Ethscriptions Protocol:

```solidity
ethscriptions_protocol_TransferEthscription(
  address indexed recipient,
  bytes32 indexed ethscriptionId
)
```

Event signature:

```solidity
// "0xf30861289185032f511ff94a8127e470f3d0e6230be4925cb6fad33f3436dffb"
keccak256("ethscriptions_protocol_TransferEthscription(address,bytes32)")
```

When a contract emits `ethscriptions_protocol_TransferEthscription`, the protocol should register a valid ethscription transfer from the emitting contract to `recipient` of the `ethscription` with id `ethscriptionId`, provided the emitting contract owns that ethscription when emitting the event, and the event is emitted in `17672762` or a later block.

If there are multiple valid events they should be processed in the order of their log index.

If the input data of the transaction also represents a valid transfer, this transfer will be processed before all event-based transfers.

### Rationale

Ethscriptions can be transferred to any address, which means smart contracts can own them. However, smart contracts cannot currently transfer or create ethscriptions themselves.

This limitation prevents development of protocol-dependent applications requiring smart contract functionality, including decentralized marketplaces, and creates obstacles for smart contract wallet users.

The proposal establishes a straightforward, gas-efficient mechanism enabling smart contracts to execute ethscription transfers.

### Notes

An earlier iteration included an additional event for Ethscription creation, but the author determined a separate proposal would better serve the project's emphasis on deliberate, incremental improvements.

---

<a id="page-9-esip-2"></a>
# PAGE 9: ESIP-2 — https://docs.ethscriptions.com/esips/accepted-esips/esip-2-safe-trustless-smart-contract-ethscription-escrow

## ESIP-2: Safe Trustless Smart Contract Ethscription Escrow

### Abstract

This proposal introduces ESIP-2, an enhancement to the Ethscriptions Protocol that enables smart contracts to safely and trustlessly escrow Ethscriptions.

ESIP-2 accomplishes this by offering a mechanism for conditional transfers, relieving contracts from the requirement to identify the depositor of a given Ethscription.

### Specification

Add a new smart contract event into the Ethscriptions Protocol:

```solidity
event ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
    address indexed previousOwner,
    address indexed recipient,
    bytes32 indexed ethscriptionId
);
```

When a contract emits this event, the protocol should register a valid ethscription transfer from the emitting contract to `recipient` of the ethscription with id `ethscriptionId`, provided:

1. The emitting contract owns the ethscription with id `ethscriptionId` when it emits the event.
2. The ethscription's previous owner was `previousOwner` as defined below.

An ethscription's "current owner" is the address that is in the "to" of the most recent valid transfer of that ethscription.

An ethscription's "previous owner" is the address that is in the "from" of the most recent valid transfer.

"Previous owner" doesn't necessarily mean "previous unique owner." For example, if you transfer an ethscription to me and then I transfer it to myself, I will be both the "current owner" and the "previous owner."

#### Implementation Guidelines

After ESIP-2, a valid ethscription transfer must have two properties:

1. Its "from" must equal the "to" of the previous valid transfer
2. Transfers sent under ESIP-2 will have an "enforced previous owner." In the case one exists, the enforced previous owner must equal the "from" of the previous valid transfer.

Below is an example of how an Ethscription transfers could be validated after the implementation of ESIP-2:

```javascript
const _ = require('lodash');

function validTransfers(ethscriptionTransfers) {
  const sorted = _.sortBy(
    ethscriptionTransfers,
    ['blockNumber', 'transactionIndex', 'transferIndex']
  );

  const valid = [];

  for (const transfer of sorted) {
    const lastValid = valid[valid.length - 1];
    const basicRulePasses = valid.length === 0 || transfer.from === lastValid.to;
    const previousOwnerRulePasses =
      transfer.enforcedPreviousOwner === null ||
      transfer.enforcedPreviousOwner === (lastValid?.from || null);

    if (basicRulePasses && previousOwnerRulePasses) {
      valid.push(transfer);
    }
  }

  return valid;
}
```

### Rationale

ESIP-2 is formulated primarily to enable smart contracts to safely escrow ethscriptions.

The idea of the smart contract escrow is that you send an ethscription to a smart contract, and, though that ethscription is owned by the smart contract, you retain some power over it—typically the ability to withdraw it and the ability to instruct the smart contract to send it to someone else.

Marketplaces are a common use-case for smart contract ethscription escrow. Because it is currently not possible for people to give smart contracts approval to transfer their ethscriptions, in order to list an ethscription for sale it must be transferred to the marketplace contract first.

With the introduction of `ethscriptions_protocol_TransferEthscription` in ESIP-1, smart contracts have the capability send and receive ethscriptions and function as marketplaces / escrows. However with just ESIP-1, smart contracts cannot obtain the information required to function as **safe** escrows without additional help.

The purpose of ESIP-2 is to enable smart contracts to overcome this limitation.

#### Who is the Depositor?

As an escrow, a smart contract should act to the benefit of the depositor of a given ethscription. However, because smart contracts cannot access ethscription ownership information, contracts cannot determine who deposited a given ethscription.

For example, if Alice and Bob both send a transaction to a smart contract with calldata `0xb1bdb91f010c154dd04e5c11a6298e91472c27a347b770684981873a6408c11c`, the smart contract can recognize this as a potential deposit, but it cannot know which (if either) of Alice or Bob's transactions is a legitimate deposit.

Because the contract can't determine the ethscription's depositor, it cannot determine who should have the power to control the ethscription once deposited. For example, the smart contract cannot determine who should have the power to withdraw the ethscription.

Because a smart contract cannot distinguish between Alice and Bob's deposits, it might treat them equally, leading to this exploit:

1. Alice "Deposits" id 0x123
2. Bob Deposits id 0x123
3. (Bob's deposit is real, Alice's isn't)
4. Alice requests a withdraw
5. Contract emits `ethscriptions_protocol_TransferEthscription(Alice, 0x123)`
6. Bob requests a withdraw
7. Contract emits `ethscriptions_protocol_TransferEthscription(Bob, 0x123)`

Alice owns the ethscription after (5) and the transfer in (7) fails.

#### Giving Contracts More Information

The most straightforward way to avoid this exploit is to require a trusted third party to confirm which deposits are valid.

For example, after you deposited id 0x123 you could go to the trusted party, ask them to verify it was your deposit that caused the contract to own id 0x123, and create a signed message memorializing this information.

Then you could present this signed message to the escrow contract to prove your deposit was legitimate. The contract would know to believe your message by comparing the signer of the message to the address of the trusted party.

Finally, when deposits are pending confirmation, they cannot be withdrawn, because the contract doesn't know who should have the ability to do so.

Here's how the exploit would be foiled using this approach:

1. Alice "Deposits" id 0x123
2. Bob Deposits id 0x123
3. Smart Contract Freezes Assets
4. Third Party informs "Bob is real depositor"
5. Alice requests a withdraw
6. Contracts does nothing
7. Bob requests a withdraw
8. Contract emits `ethscriptions_protocol_TransferEthscription(Bob, 0x123)`

This solution works, but if the third party is not available it will be impossible for anyone to withdraw their assets. It would be preferable to have a decentralized alternative.

#### Reducing Contract Informational Needs

If a contract doesn't itself have a piece of information, it is not possible to deliver that information to the contract in a trustless fashion. Because of this, trustless solutions for contract escrow involve reducing the information a contract requires to make correct decisions, rather than supplying the contract with inaccessible information.

Specifically, ESIP-2 creates a mechanism for smart contracts to act in the interests of a depositor without having to know who that depositor is. Contracts achieve this through conditional transfers. Instead absolute transfers like "Send 0x123 to Alice," contracts can say "Send 0x123 to Alice, *if and only if* Alice deposited 0x123."

Now the potential exploit looks like this:

1. Alice "Deposits" id 0x123
2. Bob Deposits id 0x123
3. (Bob's deposit is real, Alice's isn't)
4. Alice requests a withdraw
5. Contracts emits `ethscriptions_protocol_TransferEthscriptionForPreviousOwner(Alice, Alice, 0x123)`
6. Bob requests a withdraw
7. Contract emits `ethscriptions_protocol_TransferEthscriptionForPreviousOwner(Bob, Bob, 0x123)`

With ESIP-2 the contract doesn't have to gather the information necessary to determine which of Alice and Bob's withdrawal requests are legitimate and to change its behavior accordingly.

Instead, the contract does the same thing for Alice's withdraw as it does for Bob's. However, because `TransferEthscriptionForPreviousOwner` is only valid when Alice is the legitimate previous owner—which she cannot be here as her deposit is invalid—this transfer is invalid under the protocol and, like all invalid transfers, will be ignored by indexers.

The goal is to make smart contracts "dumber." Instead of smart contracts having to decide which user requests to ignore based on different user permissions, the smart contract can treat all user requests the same, knowing that the invalid requests will be filtered out at the protocol level.

### Example Smart Contract

This is an example implementation of an `EthscriptionsEscrower` base contract that a marketplace can inherit from.

For example, a marketplace would call something like `_transferEthscription(seller, msg.sender, ethscriptionId)` in the "buy" function.

In addition to ESIP-2 it contains an additional best practice of an enforced 5 block cooldown period between transfers to account for potential indexer delays and reorgs.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library EthscriptionsEscrowerStorage {
    struct Layout {
        mapping(address => mapping(bytes32 => uint256)) ethscriptionReceivedOnBlockNumber;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256('ethscriptions.contracts.storage.EthscriptionsEscrowerStorage');

    function s() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

contract EthscriptionsEscrower {
    error EthscriptionNotDeposited();
    error EthscriptionAlreadyReceivedFromSender();
    error InvalidEthscriptionLength();
    error AdditionalCooldownRequired(uint256 additionalBlocksNeeded);

    event ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
        address indexed previousOwner,
        address indexed recipient,
        bytes32 indexed id
    );

    event PotentialEthscriptionDeposited(
        address indexed owner,
        bytes32 indexed potentialEthscriptionId
    );

    event PotentialEthscriptionWithdrawn(
        address indexed owner,
        bytes32 indexed potentialEthscriptionId
    );

    uint256 public constant ETHSCRIPTION_TRANSFER_COOLDOWN_BLOCKS = 5;

    function _transferEthscription(address previousOwner, address to, bytes32 ethscriptionId) internal virtual {
        _validateTransferEthscription(previousOwner, to, ethscriptionId);

        emit ethscriptions_protocol_TransferEthscriptionForPreviousOwner(previousOwner, to, ethscriptionId);

        _afterTransferEthscription(previousOwner, to, ethscriptionId);
    }

    function withdrawEthscription(bytes32 ethscriptionId) public virtual {
        _transferEthscription(msg.sender, msg.sender, ethscriptionId);

        emit PotentialEthscriptionWithdrawn(msg.sender, ethscriptionId);
    }

    function _onPotentialEthscriptionDeposit(address previousOwner, bytes memory userCalldata) internal virtual {
        if (userCalldata.length != 32) revert InvalidEthscriptionLength();

        bytes32 potentialEthscriptionId = abi.decode(userCalldata, (bytes32));

        if (userEthscriptionPossiblyStored(previousOwner, potentialEthscriptionId)) {
            revert EthscriptionAlreadyReceivedFromSender();
        }

        EthscriptionsEscrowerStorage.s().ethscriptionReceivedOnBlockNumber[previousOwner][potentialEthscriptionId] = block.number;

        emit PotentialEthscriptionDeposited(previousOwner, potentialEthscriptionId);
    }

    function _validateTransferEthscription(
        address previousOwner,
        address to,
        bytes32 ethscriptionId
    ) internal view virtual {
        if (userEthscriptionDefinitelyNotStored(previousOwner, ethscriptionId)) {
            revert EthscriptionNotDeposited();
        }

        uint256 blocksRemaining = blocksRemainingUntilValidTransfer(previousOwner, ethscriptionId);

        if (blocksRemaining != 0) {
            revert AdditionalCooldownRequired(blocksRemaining);
        }
    }

    function _afterTransferEthscription(
        address previousOwner,
        address to,
        bytes32 ethscriptionId
    ) internal virtual {
        delete EthscriptionsEscrowerStorage.s().ethscriptionReceivedOnBlockNumber[previousOwner][ethscriptionId];
    }

    function blocksRemainingUntilValidTransfer(
        address previousOwner,
        bytes32 ethscriptionId
    ) public view virtual returns (uint256) {
        uint256 receivedBlockNumber = EthscriptionsEscrowerStorage.s().ethscriptionReceivedOnBlockNumber[previousOwner][ethscriptionId];

        if (receivedBlockNumber == 0) {
            revert EthscriptionNotDeposited();
        }

        uint256 blocksPassed = block.number - receivedBlockNumber;

        return blocksPassed < ETHSCRIPTION_TRANSFER_COOLDOWN_BLOCKS ?
            ETHSCRIPTION_TRANSFER_COOLDOWN_BLOCKS - blocksPassed :
            0;
    }

    function userEthscriptionDefinitelyNotStored(
        address owner,
        bytes32 ethscriptionId
    ) public view virtual returns (bool) {
        return EthscriptionsEscrowerStorage.s().ethscriptionReceivedOnBlockNumber[owner][ethscriptionId] == 0;
    }

    function userEthscriptionPossiblyStored(
        address owner,
        bytes32 ethscriptionId
    ) public view virtual returns (bool) {
        return !userEthscriptionDefinitelyNotStored(owner, ethscriptionId);
    }

    fallback() external virtual {
        _onPotentialEthscriptionDeposit(msg.sender, msg.data);
    }
}
```

---

<a id="page-10-esip-3"></a>
# PAGE 10: ESIP-3 — https://docs.ethscriptions.com/esips/accepted-esips/esip-3-smart-contract-ethscription-creations

## ESIP-3: Smart Contract Ethscription Creations

### Abstract

ESIP-3 introduces a mechanism for smart contracts to create ethscriptions using Ethereum events. Start block: `18130000`

### Specification

Add a new smart contract event into the Ethscriptions Protocol:

```solidity
event ethscriptions_protocol_CreateEthscription(
    address indexed initialOwner,
    string contentURI
);
```

When a contract emits this event in or after block `18130000`, the protocol should register a valid ethscription creation attempt with:

1. `contentURI` interpreted as the ethscription's utf-8 encoded dataURI with all null bytes removed.
2. `initialOwner` as the created ethscription's initial owner.
3. The emitting contract as the creator.

Functionally speaking, this event is the equivalent of an EOA hex-encoding `contentURI` and putting it in the calldata of an Ethereum transaction from itself to `initialOwner`. As with ethscriptions created via input data, all null bytes are removed from the UTF8 `contentURI` of ethscriptions created through events.

As with EOA-initiated ethscription creations, ESIP-3 ethscription creations are only valid if `contentURI` is both unique and "a syntactically valid dataURI".

#### Example `contentURI` format

`data:,1234`.

Note: it is utf-8 encoded, *not* hex-encoded. Note also this specific example is a duplicate and would not result in an ethscription creation.

#### Ethscriptions and Ethereum Transactions remain 1-1

ESIP-3 does **not** change the fact that each Ethereum transaction may have only one corresponding ethscription. If multiple aspects of a transaction constitute valid ethscription creations, calldata will be prioritized over events, and events with lower log indices will be prioritized over those with higher indices.

Example 1:

1. Calldata: valid creation
2. Event Log Index 1: valid creation
3. Event Log Index 2: valid creation

In this case, an ethscription will be created according to the calldata and Events 1 and 2 will be ignored.

Example 2:

1. Calldata: empty (i.e., invalid creation)
2. Event Log Index 1: valid creation
3. Event Log Index 2: valid creation

Here, Event 1's log will trigger the ethscription creation. If calldata and Event 1 were both invalid then Event 2's log would trigger the ethscription creation.

### Rationale

Contracts must have the same powers as EOAs and this is the cheapest way to do it.

The proposal maintains the 1-1 correspondence between ethscriptions and Ethereum transactions because the convention that `ethscriptionId` = `transactionHash` has proven useful.

Multiple ethscriptions in a transaction are also an inefficient way of capturing a user's intent. Creating multiple ethscriptions in a transaction will always have an underlying purpose and structure, and we should be capturing this structure using ESIP-4.

For example, instead of forcing a user to bulk create ethscriptions of this form:

```
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17560","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17561","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17562","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17563","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17564","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17565","amt":"1000"}
data:,{"p":"erc-20","op":"mint","tick":"fair","id":"17566","amt":"1000"}
...
```

The proposal captures the user's intent with a single ethscription containing the command `mint(50)`.

#### File size

Unlike calldata, events have no size limit (aside from the 30M block gas limit). Practically this means that ESIP-3 expands ethscriptions' file size limit to beyond 3.5MB.

---

<a id="page-11-esip-5"></a>
# PAGE 11: ESIP-5 — https://docs.ethscriptions.com/esips/accepted-esips/esip-5-bulk-ethscription-transfers-from-eoas

## ESIP-5: Bulk Ethscription Transfers from EOAs

### Abstract

Bulk transferring means transferring more than one ethscription in a single Ethereum transaction.

ESIP-1 and ESIP-2 gave Smart Contracts the ability to transfer ethscriptions through events. Because multiple events can be emitted in a single transaction, ESIP-1 and ESIP-2 also gave Smart Contracts the ability to bulk transfer ethscriptions.

ESIP-5 brings EOAs to the level of Smart Contracts by introducing a mechanism for EOAs to bulk transfer ethscriptions.

### Specification

Pre-ESIP-5, this was the rule for EOAs transferring an ethscription:

> "Any Ethereum transaction whose input data is an ethscription id [...] is a valid Ethscription transfer, provided the transaction sender is the Ethscription's owner."

ESIP-5 retains the spirit of this rule, but allows users to add multiple ordered ethscription ids as input data.

If the input data of a transaction (without its leading `0x`) is a sequence of 1 or more valid ethscription ids (without their leading `0x`), that transaction will constitute a valid transfer for each ethscription that is owned by the transaction's creator.

#### An Example

Suppose a transaction has the input data:

```
0x8ad5dc6c7a6133eb1c42b2a1443125b57913c9d63376825e310e4d1222a91e24533c5e38d1b8bf75166bd6443a443cd25bd36c087e1a5b8b0881b388fa1a942c
```

We first remove the leading `0x`:

```
8ad5dc6c7a6133eb1c42b2a1443125b57913c9d63376825e310e4d1222a91e24533c5e38d1b8bf75166bd6443a443cd25bd36c087e1a5b8b0881b388fa1a942c
```

Now we observe that this hex string's length is 128, which is an even multiple of 64, which is the length of an ethscription id with its leading `0x` removed.

Now we split the hex string into two chunks of 64 characters and determine whether these chunks are valid ethscription ids. We prepend the `0x` and check for ethscriptions. Now we find:

1. `0x8ad5dc6c7a6133eb1c42b2a1443125b57913c9d63376825e310e4d1222a91e24` is Ethscription #2.
2. `0x533c5e38d1b8bf75166bd6443a443cd25bd36c087e1a5b8b0881b388fa1a942c` is Ethscription #1.

Because both ids correspond to valid ethscriptions, we proceed. If one or more weren't valid ethscriptions, we would ignore the invalid ethscriptions and continue processing.

Now we look at the ids in the order they were listed in calldata, and register in order:

1. A valid transfer for `0x8ad5dc6c7a6133eb1c42b2a1443125b57913c9d63376825e310e4d1222a91e24` if the "from" of the transaction is the owner of this ethscription as of this moment.
2. A valid transfer for `0x533c5e38d1b8bf75166bd6443a443cd25bd36c087e1a5b8b0881b388fa1a942c` if "from" of the transaction is the owner of this ethscription as of this moment.

If the "from" of the transaction is *not* the owner of the ethscription, we skip that transfer and continue processing. This means that if the "from" is the owner on some, but not all, ethscriptions some of the transfers will be valid and some will not.

### Rationale

The goal is to reduce the question of bulk transferring to a sequence of individual transfers. This is why there can be partially valid bulk transfers—creating a notion of bulk validity is additional complexity.

However, we must enforce a notion of global validity for all ethscription ids, otherwise we introduce too much potential for unintentional transfers and confusion.

---

<a id="page-12-esip-6"></a>
# PAGE 12: ESIP-6 — https://docs.ethscriptions.com/esips/accepted-esips/esip-6-opt-in-ethscription-non-uniqueness

## ESIP-6: Opt-in Ethscription Non-uniqueness

### Abstract

Currently, only the first ethscription with a given content uri is valid.

For example, if there is an existing ethscription with content `data:,1234`, then no future ethscription can be created with this same content.

This mechanic was designed for the digital artifact use-case when it is valuable to know provenance. It also makes Ethscriptions content-addressable, allowing users to look up ownership and other metadata using only ethscription content.

However, uniqueness creates problems for use-cases where guaranteed delivery is necessary. For example, if two people are using Ethscriptions as a messaging protocol, they shouldn't have to worry about making each message globally unique.

This problem is more acute in the case of Smart Contract-created ethscriptions because while people can "try again" if their ethscription is a duplicate, Smart Contracts cannot "revert" in the case of ethscription creation failure.

For example, if a Smart Contract has collected money from a user in exchange for creating an ethscription, the Smart Contract cannot return this money if the creation fails.

ESIP-6 proposes a backwards-compatible mechanism to support all of these use-cases. By default, duplicate ethscriptions will continue to be invalid, as they are today. However, users will be able to modify dataURIs to "opt-in" to potential duplication on ethscriptions they create after this ESIP is live.

### Specification

#### Opt In Non-uniqueness

To opt in to potential duplication, a user must add a special "magic" parameter to their dataURI.

In a dataURI, parameters are strings that appear after the mimetype and before the optional "base64" and the start of the content. The most common use of parameters is to specify a character encoding for the dataURI as in this example:

`data:text/plain;charset=utf-8,hi`

In this dataURI, `charset` is a parameter and it has the value `utf-8`.

We will discuss the choice of magic parameter below, but for now let's assume it is `rule=esip6`.

If a user wants to mark an ethscription "okay to duplicate" they would add the parameter `rule=esip6` to their dataURI. For example:

`data:text/plain;charset=utf-8;rule=esip6,hi`

If there were no other parameter, it would look like this:

`data:text/plain;rule=esip6,hi`

Marking an ethscription "okay to duplicate" also guarantees that it will never be invalidated as a duplicate itself because any potential duplicate would also contain the parameter `rule=esip6` which marks *it* as "okay to duplicate."

#### Updated Indexer Behavior

To implement this ESIP, indexers must change their behavior. Here is how an indexer should determine if a new ethscription is valid.

1. Determine whether the ethscription's content is a valid dataURI. The rules for dataURI validity are **not** changing in this ESIP. Everything that was a valid dataURI previously is still valid, and everything that wasn't a valid dataURI is still invalid.
   1. If the ethscription has an invalid dataURI then it is an invalid ethscription. If it has a valid dataURI, proceed to step 2.

2. Does the ethscription contain `rule=esip6` as a dataURI parameter?
   1. If yes, the ethscription is valid. If no, proceed to step 3.

3. Does another ethscription created in an earlier block, or created in the same block but with an earlier transaction index, have the same content?
   1. If yes, the ethscription is invalid. If no, it is valid.

#### Parsing dataURI parameters

DataURI validity is defined by this Ruby regular expression:

```ruby
%r{
  data:
  (?<mediatype>
    (?<mimetype> .+? / .+? )?
    (?<parameters> (?: ; .+? = .+? )* )
  )?
  (?<extension>;base64)?
  ,
  (?<data>.*)
}x
```

Here is example code you can use to find the correct parameter using this regex:

```ruby
def is_esip6?(uri)
  match = REGEXP.match(uri)
  String(match[:parameters]).split(';').include?('rule=esip6')
end
```

#### Client Behavior

Ethscriptions clients are encouraged to indicate the presence of the `rule=esip6` parameter as well as the number of duplicates that exist for a specific `rule=esip6` ethscription.

Many clients display "Ethscription Numbers" that indicate the order in which a given ethscription was created. Clients are encouraged to continue assigning numbers to all valid ethscriptions, whether or not they include the `rule=esip6` parameter.

#### Smart Contract Behavior

Because Smart Contracts cannot "try again" in the case of duplicates, Smart Contracts should include the `rule=esip6` parameter in any scenario in which ethscription creation failure would lead to loss of funds or ethscriptions.

### Rationale

Ethscriptions cannot succeed as a general protocol without the ability to guarantee message delivery. If we can't rely on our ability to create ethscriptions, we can't rely on the creation of an ethscription to trigger something important, and this limits what we can use ethscriptions to do.

The immediate need for this ESIP comes from the fact that it is impossible to create a secure Ethscriptions VM bridge if Smart Contracts cannot reliably communicate with Dumb Contracts by creating ethscriptions.

However, this proposal is not restricted to Ethscription VM-related ethscriptions because the need for message delivery is more universal.

Why do it this way?

#### Why Not Change the Default to Allow Duplicates?

Even if this were a good change, it is too late to make.

We cannot change the default retroactively because people have relied on protocol rules to make important decisions and invalidating those decisions would irreparably damage trust in the protocol.

We also cannot change the default going forward because as we have seen this will still leave past ethscriptions un-duplicatable.

#### Front Running and Censorship

In the end, ESIP-6 isn't really about the ability to create duplicate ethscriptions.

It has always been possible to create "pseudo" duplicates of ethscriptions by varying parts of images that do not affect pixels but do affect the final bytes of the ethscription. It is also possible to "duplicate" a JSON object by creating a new object that shares keys and values but differs in some respect the JSON parser ignores.

Theoretically users could take advantage of this to ensure message delivery by creating a message that was a "pseudo" duplicate of an existing message but whose bytes were different.

Unfortunately, this fix does not work because of front running. Someone can always observe the ethscription you are creating and create the same one earlier in the same block. This ESIP gives users a method to create duplicates that cannot be censored by front runners and this is absolutely necessary for Ethscriptions to be the uncensorable protocol it was always intended to be.

---

<a id="page-13-esip-7"></a>
# PAGE 13: ESIP-7 — https://docs.ethscriptions.com/esips/accepted-esips/esip-7-support-gzipped-calldata-in-ethscription-creation

## ESIP-7: Support Gzipped Calldata in Ethscription Creation

### Overview

This proposal enables gzip compression for ethscription calldata to reduce gas costs, particularly for JSON-based content that lacks native compression.

### Impact

The total size of all EOA-created ethscriptions is about 1.5gb. Gzipping these ethscriptions would reduce size by more than 500mb, a massive 35% reduction.

### Specification

Indexers must detect gzipped ethscriptions through the magic byte sequence `0x1F8B` and automatically decompress before standard processing. Users receive uncompressed results in queries, maintaining existing behavior.

### Safety Mechanism

A compression ratio ceiling of 10x prevents zip bomb attacks. When compressed, 99% of current ethscriptions would have a compression ratio of 3.85x or less, so a 10x limit should be plenty for all realistic use-cases.

### Scope

Applies only to transaction input-based ethscriptions, excluding contract-created ones or transfers.

### Performance

The reference implementation demonstrates that decompression occurs rapidly—on the order of 1ms for typical ethscription payloads—even in slower programming languages.

The proposal maintains backward compatibility while providing significant cost savings for users creating ethscriptions with compressible content.

---

<a id="page-14-esip-8"></a>
# PAGE 14: ESIP-8 — https://docs.ethscriptions.com/esips/accepted-esips/esip-8-ethscription-attachments-aka-blobscriptions

## ESIP-8: Ethscription Attachments aka "BlobScriptions"

### Links

* Reference Implementation
* ESIP-8 Discussion

### Abstract

The introduction of blobs in EIP-4844 enables anyone to store data on Ethereum for 10x to 100x cheaper than calldata. This comes at a cost, however: the Ethereum protocol doesn't guarantee the availability of blob data for more than 18 days.

However, on a practical level it is not clear how burdensome this limitation will be. Because L2s use blobs to store transaction data there will be strong incentives to create publicly accessible archives of blob data to enhance the transparency and auditability of Layer 2s.

Also, like IPFS, blob data is completely decentralized—as long as one person has blob data it can be verified and used by anyone.

This ESIP proposes using blobs to store data within the Ethscriptions Protocol. We presuppose the ready availability of blob data and require indexers to store or find user blob data along with the other blockchain data the Ethscriptions Protocol currently uses.

Specifically, ESIP-8 proposes a new "sidecar" **attachment** field for Ethscriptions that is composed from the data in one or more blobs. This field is in addition to the existing **content** field.

The name "Ethscription Attachment" is preferred over "Ethscription Blob" (or similar) because transactions can have multiple blobs, but ethscriptions can only have one attachment (that is composed of all the blobs together).

### An Example

Consider the ethscription created by this Sepolia transaction. The transaction's calldata contains the hex data `0x646174613a2c68656c6c6f2066726f6d20457468736372697074696f6e2063616c6c6461746121` which corresponds to the dataURI "data:,hello from Ethscription calldata!" which becomes the ethscription's content.

The transaction's blobs, when interpreted according to the rules described below, contains the data for this image which becomes the ethscription's attachment.

### Specification

All new ethscriptions have an optional `attachment` field. If an ethscription is created in a transaction with no blobs this field will be `null`.

If an ethscription's creation transaction does include blobs *and* the ethscription was created via calldata (i.e., not via an event emission), its blobs are concatenated and interpreted as an untagged CBOR object (as defined by RFC 8949) that decodes into a hash with *exactly* these keys:

* `content`
* `contentType`

If the concatenated data is a valid CBOR object, and that object decodes into a hash with exactly those two fields, an attachment for the ethscription is created.

The case in which the blobs are invalid and an attachment is *not* created is handled identically to the case in which there are no blobs at all. I.e., the ethscription is still created if it's otherwise valid, just with no attachment.

Note:

* There is no uniqueness requirement for the attachment's content and/or contentType.
* Attachment `content`, `contentType`, and the container CBOR object itself can each be optionally gzipped **with a maximum compression ratio of 10x**.
* The attachment is **not** valid if:
  * If the CBOR object has a tag
  * If the decoded object is not a hash
  * If the decoded hash's keys aren't exactly `content` and `contentType`. There cannot be extra keys.
  * The values of `content` and `contentType` aren't both strings (either binary or UTF-8).

When such an attachment exists, the indexer's API must include the path for retrieving it in an `attachment_path` field in the JSON representation of an ethscription with at most a one block delay between ethscription creation and inclusion of the URL. For example, if an ethscription is created in block 15, the attachment_url must appear no later than block 17.

The attachment_url field will be available *in addition* to the `content_uri` field.

#### `contentType` Max Length

To enable performant filtering by `contentType`, indexers must only store the first 1,000 characters of the user-submitted content type. Content types of more than 1,000 characters will be truncated, but the attachment will still be valid.

#### Creating an Ethscription Attachment in Javascript

You can use the `cbor` package and Viem's `toBlobs`:

```typescript
const { toBlobs } = require('viem');
const fs = require('fs');
const cbor = require('cbor');

const imagePath = '/whatever.gif'
const imageData = fs.readFileSync(imagePath);

const dataObject = {
  contentType: 'image/gif',
  content: imageData
};

const cborData = cbor.encode(dataObject);
const blobs = toBlobs({ data: cborData });
```

#### Getting Blob Data

Blob data is available on a block-level through the `blob_sidecars` API endpoint available on Ethereum Beacon nodes. If you don't want to run a node yourself, you can use Quicknode.

The input to this function is a "block id," which is a slot number (not block number) or block root. Block roots are available on normal Ethereum API requests, but only for the *previous* block (the field is `parentBeaconBlockRoot`).

This means that attachments must be populated on a one block delay.

#### Associating Blobs with Ethereum Transactions

Because the Beacon API only provides blob information on a block level, it requires some additional logic to match blobs to the transactions that created them. Fortunately, transactions now have a `blobVersionedHashes` field that can be computed from the `kzg_commitments` field on the block-level blob data.

Here's an example implementation (it's `O(n^2)` but the numbers involved are small)

```ruby
def transaction_blobs
  blob_versioned_hashes.map do |version_hash|
    blob_from_version_hash(version_hash)
  end
end

def blob_from_version_hash(version_hash)
  block_blob_sidecars.find do |blob|
    kzg_commitment = blob["kzg_commitment"].sub(/\A0x/, '')
    binary_kzg_commitment = [kzg_commitment].pack("H*")
    sha256_hash = Digest::SHA256.hexdigest(binary_kzg_commitment)
    modified_hash = "0x01" + sha256_hash[2..-1]

    version_hash == modified_hash
  end
end
```

#### Converting Blob Content to an Attachment

At a high-level we use normalize the blob data, concatenate it, and CBOR-decode it. However blobs have a few interesting quirks that make this more challenging:

* Currently blobs have a minimum length of 128kb. If your data is smaller than that you'll have to pad it (probably will null bytes) to the full length.
* Blobs are composed of "segments" of 32 bytes, none of which, when interpreted as an integer, can exceed the value of the cryptography-related "BLS modulus", which is 52435875175126190479447740508185965837690552500527637822603658699938581184513.

So if you want to use blobs you need a protocol for communicating where the data ends and a mechanism for ensuring no 32 byte segment is too large.

Here Ethscriptions will follow Viem's approach:

* Left-pad each segment with a null byte. A `0x00` in the most significant byte ensures no segment can be larger than the BLS modulus.
* End the content of every blob with `0x80`, which, when combined with the rule above, provides an unambiguous way to determine the length of the data in the blob.

When a blob creator follows these rules (or just use's Viem's `toBlobs`), you can decode it into bytes by using Viem's `fromBlobs`. There is a Ruby implementation as well in the appendix.

Once you decode the blob you can create an attachment using something like this class.

```ruby
class EthscriptionAttachment < ApplicationRecord
  class InvalidInputError < StandardError; end

  has_many :ethscriptions,
    foreign_key: :attachment_sha,
    primary_key: :sha,
    inverse_of: :attachment

  delegate :ungzip_if_necessary!, to: :class
  attr_accessor :decoded_data

  def self.from_eth_transaction(tx)
    blobs = tx.blobs.map{|i| i['blob']}

    cbor = BlobUtils.from_blobs(blobs: blobs)

    from_cbor(cbor)
  end

  def self.from_cbor(cbor_encoded_data)
    cbor_encoded_data = ungzip_if_necessary!(cbor_encoded_data)

    decoded_data = CBOR.decode(cbor_encoded_data)

    new(decoded_data: decoded_data)
  rescue EOFError, *cbor_errors => e
    raise InvalidInputError, "Failed to decode CBOR: #{e.message}"
  end

  def decoded_data=(new_decoded_data)
    @decoded_data = new_decoded_data

    validate_input!

    self.content = ungzip_if_necessary!(decoded_data['content'])
    self.content_type = ungzip_if_necessary!(decoded_data['contentType'])
    self.size = content.bytesize
    self.sha = calculate_sha

    decoded_data
  end

  def calculate_sha
    combined = [
      Digest::SHA256.hexdigest(content_type),
      Digest::SHA256.hexdigest(content),
    ].join

    "0x" + Digest::SHA256.hexdigest(combined)
  end

  def self.ungzip_if_necessary!(binary)
    HexDataProcessor.ungzip_if_necessary(binary)
  rescue Zlib::Error, CompressionLimitExceededError => e
    raise InvalidInputError, "Failed to decompress content: #{e.message}"
  end

  private

  def validate_input!
    unless decoded_data.is_a?(Hash)
      raise InvalidInputError, "Expected data to be a hash, got #{decoded_data.class} instead."
    end

    unless decoded_data.keys.to_set == ['content', 'contentType'].to_set
      raise InvalidInputError, "Expected keys to be 'content' and 'contentType', got #{decoded_data.keys} instead."
    end

    unless decoded_data.values.all?{|i| i.is_a?(String)}
      raise InvalidInputError, "Invalid value type: #{decoded_data.values.map(&:class).join(', ')}"
    end
  end

  def self.cbor_errors
    [CBOR::MalformedFormatError, CBOR::UnpackError, CBOR::StackError, CBOR::TypeError]
  end
end
```

#### Hashing Attachments

It's useful to be able to generate a unique hash of an Ethscription Attachment in order for indexers to avoid storing duplicate data and for users to determine which other ethscriptions have the same attachment. This can be done in many ways, but to promote uniformity ESIP-8 defines this canonical method of hashing Ethscription Attachments:

1. Compute the sha256 hash of the attachment's *ungzipped* `contentType` and `content` fields.
2. Remove the leading `0x` if present.
3. Concatenate the hex string representations of the hashes with the `contentType` hash first.
4. Hash this concatenated string and add a `0x` prefix.

Here is a Javascript implementation:

```typescript
import { sha256, stringToBytes } from 'viem';

const attachment = {
  contentType: 'text/plain',
  content: 'hi',
};

const contentTypeHash = sha256(stringToBytes(attachment.contentType));
const contentHash = sha256(stringToBytes(attachment.content));

const combinedHash =
  contentTypeHash.replace(/^0x/, '') + contentHash.replace(/^0x/, '');

const finalHash = sha256(combinedHash as `0x${string}`);
```

And a Ruby implementation:

```ruby
require 'digest'

attachment = {
  'contentType' => 'text/plain',
  'content' => 'hi',
}

content_type_hash = Digest::SHA256.hexdigest(attachment['contentType'])
content_hash = Digest::SHA256.hexdigest(attachment['content'])

combined_hash = content_type_hash + content_hash

final_hash = "0x" + Digest::SHA256.hexdigest(combined_hash)
```

### Appendix: Ruby `BlobUtils`

```ruby
module BlobUtils
  # Constants from Viem
  BLOBS_PER_TRANSACTION = 2
  BYTES_PER_FIELD_ELEMENT = 32
  FIELD_ELEMENTS_PER_BLOB = 4096
  BYTES_PER_BLOB = BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_BLOB
  MAX_BYTES_PER_TRANSACTION = BYTES_PER_BLOB * BLOBS_PER_TRANSACTION - 1 - (1 * FIELD_ELEMENTS_PER_BLOB * BLOBS_PER_TRANSACTION)

  # Error Classes
  class BlobSizeTooLargeError < StandardError; end
  class EmptyBlobError < StandardError; end
  class IncorrectBlobEncoding < StandardError; end

  # Adapted from Viem
  def self.to_blobs(data:)
    raise EmptyBlobError if data.empty?
    raise BlobSizeTooLargeError if data.bytesize > MAX_BYTES_PER_TRANSACTION

    if data =~ /\A0x([a-f0-9]{2})+\z/i
      data = [data].pack('H*')
    end

    blobs = []
    position = 0
    active = true

    while active && blobs.size < BLOBS_PER_TRANSACTION
      blob = []
      size = 0

      while size < FIELD_ELEMENTS_PER_BLOB
        bytes = data.byteslice(position, BYTES_PER_FIELD_ELEMENT - 1)

        # Push a zero byte so the field element doesn't overflow
        blob.push(0x00)

        # Push the current segment of data bytes
        blob.concat(bytes.bytes) unless bytes.nil?

        # If the current segment of data bytes is less than 31 bytes,
        # stop processing and push a terminator byte to indicate the end of the blob
        if bytes.nil? || bytes.bytesize < (BYTES_PER_FIELD_ELEMENT - 1)
          blob.push(0x80)
          active = false
          break
        end

        size += 1
        position += (BYTES_PER_FIELD_ELEMENT - 1)
      end

      blob.fill(0x00, blob.size...BYTES_PER_BLOB)

      blobs.push(blob.pack('C*').unpack1("H*"))
    end

    blobs
  end

  def self.from_blobs(blobs:)
    concatenated_hex = blobs.map do |blob|
      hex_blob = blob.sub(/\A0x/, '')

      sections = hex_blob.scan(/.{64}/m)

      last_non_empty_section_index = sections.rindex { |section| section != '00' * 32 }
      non_empty_sections = sections.take(last_non_empty_section_index + 1)

      last_non_empty_section = non_empty_sections.last

      if last_non_empty_section == "0080" + "00" * 30
        non_empty_sections.pop
      else
        last_non_empty_section.gsub!(/80(00)*\z/, '')
      end

      non_empty_sections = non_empty_sections.map do |section|
        unless section.start_with?('00')
          raise IncorrectBlobEncoding, "Expected the first byte to be zero"
        end

        section.delete_prefix("00")
      end

      non_empty_sections.join
    end.join

    [concatenated_hex].pack("H*")
  end
end
```

---

<a id="page-15-protocol-handlers"></a>
# PAGE 15: PROTOCOL HANDLERS — https://docs.ethscriptions.com/ethscriptions-appchain/protocol-handlers

## Protocol Handlers

Protocol handlers allow developers to extend ethscription functionality with custom on-chain logic. When an ethscription includes protocol parameters, the Ethscriptions contract routes the call to a registered handler.

> Protocol handlers are an **AppChain-only** feature. They require smart contract execution on the L2.

### How It Works

1. **Registration** - Handler contract registers with main Ethscriptions contract
2. **Creation** - User creates ethscription with protocol parameters in Data URI
3. **Routing** - Ethscriptions contract detects protocol and calls handler
4. **Execution** - Handler performs custom logic (mint tokens, add to collection, etc.)

Flow: User -> L1 Transaction -> Derivation Node -> Ethscriptions Contract -> Protocol Handler

### Built-in Protocols

| Protocol | Purpose | Documentation Link |
|----------|---------|-------------------|
| `erc-721-ethscriptions-collection` | Curated NFT collections with merkle enforcement | Collections |
| `erc-20-fixed-denomination` | Fungible tokens with fixed-denomination notes | Fixed Denomination Tokens |

### Protocol Data URI Format

#### Header-Based (for binary content)

Best for images and other binary data where the content itself is the payload.

```
data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=add_self_to_collection;d=<base64-json>;base64,<image-bytes>
```

| Parameter | Description |
|-----------|-------------|
| `p=<protocol>` | Protocol handler name (lowercase) |
| `op=<operation>` | Operation to invoke on handler |
| `d=<base64>` | Base64-encoded JSON parameters |
| `rule=esip6` | (Optional) Allow duplicate content URIs |

#### JSON Body (for text-based operations)

Best for operations where the parameters ARE the content.

```
data:application/json,{"p":"erc-20-fixed-denomination","op":"deploy","tick":"mytoken","max":"1000000","lim":"1000"}
```

JSON Body Contains:
- `p` - Protocol handler name
- `op` - Operation name
- Additional operation-specific fields

### Example: Creating a Collection Item

```
data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=add_self_to_collection;d=eyJjb2xsZWN0aW9uSWQiOiIweC4uLiIsIml0ZW1JbmRleCI6MX0=;base64,iVBORw0KGgo...
```

JSON Parameters (decoded from d):

```json
{
  "collection_id": "0x...",
  "item": {
    "item_index": "1",
    "name": "Item #2",
    "background_color": "#00FF00",
    "description": "The second item",
    "attributes": [{"trait_type": "Rarity", "value": "Rare"}],
    "merkle_proof": []
  }
}
```

### Example: Deploying a Token

```
data:application/json,{"p":"erc-20-fixed-denomination","op":"deploy","tick":"mytoken","max":"1000000","lim":"1000"}
```

### Protocol Handler Contract Interface

```solidity
interface IProtocolHandler {
    function onTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) external;

    function protocolName() external pure returns (string memory);
}
```

Operation functions (prefixed with `op_`) are called dynamically based on the `op` parameter in the data URI.

Collections Manager Operations:
- `op_create_collection_and_add_self(...)`
- `op_add_self_to_collection(...)`
- `op_edit_collection(...)`

Note: These are not part of the interface - the Ethscriptions contract uses dynamic dispatch to call them.

### Events

```solidity
event ProtocolHandlerSuccess(
    bytes32 indexed ethscriptionId,
    string protocol,
    bytes returnData
);

event ProtocolHandlerFailed(
    bytes32 indexed ethscriptionId,
    string protocol,
    bytes revertData
);
```

### Registration

Protocols are registered at genesis or through governance. The main contract maintains a mapping:

```solidity
mapping(string => address) public protocolHandlers;
```

When an ethscription with protocol params is created, the contract looks up the handler and calls the appropriate `op_*` function.

### Security Considerations

- Protocol handlers run within Ethscriptions contract's context
- Handlers cannot modify ethscription ownership directly
- All state changes are atomic with ethscription creation
- Failed handler calls emit `ProtocolHandlerFailed` but don't revert the ethscription creation

---

<a id="page-16-collections"></a>
# PAGE 16: COLLECTIONS — https://docs.ethscriptions.com/ethscriptions-appchain/collections

## Collections

The ERC-721 Ethscriptions Collections protocol allows creators to build curated collections of ethscriptions with rich metadata and optional access control.

> Collections are an AppChain-only feature. They require smart contract execution on the L2.

A **Collection** is a named set of ethscriptions with metadata (name, symbol, description, max supply). **Items** are individual ethscriptions added to a collection. **Merkle Enforcement** provides optional cryptographic restriction on which items can be added.

### Creating a Collection

Use the `create_collection_and_add_self` operation to create a collection and add the first item in one transaction:

```
data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=create_collection_and_add_self;d=<base64-json>;base64,<image-bytes>
```

The `rule=esip6` parameter allows duplicate content. Without it, if the same data URI (including headers) was used in a previous ethscription, the new ethscription would be rejected as a duplicate. Uniqueness is based on SHA256 of the full data URI, not just the payload.

Where the base64-decoded `d` parameter contains:

```json
{
  "metadata": {
    "name": "My Collection",
    "symbol": "MYC",
    "max_supply": "100",
    "description": "A curated collection of digital artifacts",
    "logo_image_uri": "",
    "banner_image_uri": "",
    "background_color": "",
    "website_link": "https://example.com",
    "twitter_link": "myhandle",
    "discord_link": "https://discord.gg/...",
    "merkle_root": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "initial_owner": "0x1234567890abcdef1234567890abcdef12345678"
  },
  "item": {
    "item_index": "0",
    "name": "Item #1",
    "background_color": "#FF0000",
    "description": "The first item in the collection",
    "attributes": [
      { "trait_type": "Rarity", "value": "Legendary" },
      { "trait_type": "Color", "value": "Red" }
    ],
    "merkle_proof": []
  }
}
```

All fields must be present in exact order. Use empty strings for optional values.

### Metadata Object Fields

| Field | Description |
|-------|-------------|
| name | Collection name |
| symbol | Short symbol (e.g., "MYC") |
| max_supply | Maximum number of items (as string) |
| description | Collection description (can be empty) |
| logo_image_uri | Logo image as Data URI (can be empty) |
| banner_image_uri | Banner image as Data URI (can be empty) |
| background_color | Default background color (can be empty) |
| website_link | Project website URL (can be empty) |
| twitter_link | Twitter/X handle (can be empty) |
| discord_link | Discord invite URL (can be empty) |
| merkle_root | Merkle root for access control (use zero bytes32 for owner-only) |
| initial_owner | Address that will own the collection (lowercase) |

### Item Object Fields

| Field | Description |
|-------|-------------|
| item_index | Position in collection (0-indexed, as string) |
| name | Item name |
| background_color | Item-specific background color |
| description | Item description |
| attributes | Array of { trait_type, value } objects |
| merkle_proof | Array of proof hashes (for non-owner adds) |

> **Strict Key Order:** For JSON-based operations, keys must appear in exactly the order shown in the tables above. Attribute objects must use { "trait_type": "...", "value": "..." } key order.

### Adding Items to a Collection

After creating a collection, add items with `add_self_to_collection`:

```
data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=add_self_to_collection;d=<base64-json>;base64,<image-bytes>
```

Where the `d` parameter contains:

```json
{
  "collection_id": "0x...",
  "item": {
    "item_index": "1",
    "name": "Item #2",
    "background_color": "#00FF00",
    "description": "The second item",
    "attributes": [
      { "trait_type": "Rarity", "value": "Rare" },
      { "trait_type": "Color", "value": "Green" }
    ],
    "merkle_proof": []
  }
}
```

The `collection_id` is the L1 transaction hash of the collection creation.

### Merkle Proof Enforcement

When a collection has a non-zero `merkle_root`, non-owners must provide a merkle proof to add items. This ensures only pre-approved items with exact metadata can be added.

#### How It Works

1. Creator generates merkle tree from approved items
2. Each leaf is computed from item metadata
3. Creator sets merkle root when creating collection
4. Non-owners provide proofs when adding items

#### Merkle Leaf Computation

Each leaf is computed as:

```solidity
keccak256(abi.encode(
    contentHash,      // keccak256 of content bytes (bytes32)
    itemIndex,        // uint256
    name,             // string
    backgroundColor,  // string
    description,      // string
    attributes        // (string,string)[] - array of (trait_type, value) tuples
))
```

#### Merkle Tree Structure

For a 3-item collection, the tree looks like:

```
        root
       /    \
    H(0,1)   leaf2
    /    \
 leaf0  leaf1
```

Where:
- Proof for leaf0: [leaf1, leaf2]
- Proof for leaf1: [leaf0, leaf2]
- Proof for leaf2: [H(leaf0, leaf1)]

#### Pair Hashing

The merkle tree uses byte-wise ordering (same as OpenZeppelin):

```typescript
function hashPair(a: Hex, b: Hex): Hex {
  // Compare bytes, not strings
  const aBytes = hexToBytes(a);
  const bBytes = hexToBytes(b);
  let aLessThanB = false;
  for (let i = 0; i < 32; i++) {
    if (aBytes[i] !== bBytes[i]) {
      aLessThanB = aBytes[i] < bBytes[i];
      break;
    }
  }
  return keccak256(concat(aLessThanB ? [a, b] : [b, a]));
}
```

This ensures consistent proof verification regardless of sibling order.

#### Adding Items with Proofs

Non-owners include the merkle proof in the item object:

```json
{
  "collection_id": "0x...",
  "item": {
    "item_index": "1",
    "name": "Item #2",
    "background_color": "#00FF00",
    "description": "The second item",
    "attributes": [
      { "trait_type": "Rarity", "value": "Rare" }
    ],
    "merkle_proof": ["0xaab5a305...", "0x58672b0c..."]
  }
}
```

#### Owner Bypass

Collection owners can always add items without providing merkle proofs. This allows adding items not in the original tree, making corrections, and flexibility for collection management.

### Example: Creating a Merkle-Enforced Collection

This walkthrough creates a 3-item collection where:

| Item | Index | Added By | Merkle Proof Required? |
|------|-------|----------|----------------------|
| Item 1 (Red) | 0 | Owner | No (owner bypass) |
| Item 2 (Green) | 1 | Non-owner | Yes |
| Item 3 (Blue) | 2 | Non-owner | Yes |

#### Step 1: Compute Content Hashes

For each image, compute the keccak256 hash of the raw bytes:

```
Item 0 content hash: 0x666af27e...
Item 1 content hash: 0x06e51d26...
Item 2 content hash: 0x09ecc1a2...
```

#### Step 2: Build Merkle Leaves

Compute each leaf from the item metadata:

```
Leaf 0: keccak256(abi.encode(0x666af27e..., 0, "Item #1", "#FF0000", "First item", [("Rarity", "Common")]))
        = 0xd9b535b9...

Leaf 1: keccak256(abi.encode(0x06e51d26..., 1, "Item #2", "#00FF00", "Second item", [("Rarity", "Rare")]))
        = 0xaab5a305...

Leaf 2: keccak256(abi.encode(0x09ecc1a2..., 2, "Item #3", "#0000FF", "Third item", [("Rarity", "Epic")]))
        = 0x58672b0c...
```

#### Step 3: Compute Merkle Root

```
H(leaf0, leaf1) = 0x659a61c9...
Merkle Root = H(H(leaf0, leaf1), leaf2) = 0x06fbc22a...
```

#### Step 4: Create Collection (Owner)

The owner creates the collection with the merkle root and adds the first item:

1. Send a 0 ETH transaction to any address
2. Include the hex-encoded Data URI with op=create_collection_and_add_self
3. The merkle_root is set to 0x06fbc22a...
4. Save the transaction hash as collection_id

The owner doesn't need a merkle proof for their own item.

#### Step 5: Add Items (Non-Owner)

A different address adds items 2 and 3 with merkle proofs:

For Item 2 (index 1):

```json
{
  "collection_id": "0x<tx-hash-from-step-4>",
  "item": {
    "item_index": "1",
    "name": "Item #2",
    "background_color": "#00FF00",
    "description": "Second item",
    "attributes": [
      { "trait_type": "Rarity", "value": "Rare" }
    ],
    "merkle_proof": ["0xd9b535b9...", "0x58672b0c..."]
  }
}
```

The proof must match exactly, and the metadata must match what was used to compute the leaf.

### Operations Reference

| Operation | Description |
|-----------|-------------|
| create_collection_and_add_self | Create collection and add first item |
| add_self_to_collection | Add item to existing collection |
| edit_collection | Update collection metadata |
| edit_collection_item | Update item metadata |
| transfer_ownership | Transfer collection ownership |
| renounce_ownership | Surrender ownership (to zero address) |
| remove_items | Delete items from collection |
| lock_collection | Prevent further additions |

> **ESIP-6 is optional.** Add `rule=esip6` to your data URI only if you need to allow duplicate content (e.g., sending the same JSON command multiple times). Without it, an ethscription with identical content to an existing one will not be created. For image-based operations, add it to the header: `data:image/png;rule=esip6;p=...`. For text-based operations: `data:;rule=esip6,{...json...}`.

### Editing Collections

Update collection metadata with `edit_collection`. Send as a data URI:

```
data:;rule=esip6,{"p":"erc-721-ethscriptions-collection","op":"edit_collection",...}
```

JSON payload (all fields required; pass current values to keep them, empty strings will clear fields):

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "edit_collection",
  "collection_id": "0x...",
  "description": "Updated description",
  "logo_image_uri": "",
  "banner_image_uri": "",
  "background_color": "",
  "website_link": "",
  "twitter_link": "",
  "discord_link": "",
  "merkle_root": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

Only the collection owner can edit.

### Editing Items

Update item metadata with `edit_collection_item` (all fields required):

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "edit_collection_item",
  "collection_id": "0x...",
  "item_index": "0",
  "name": "New Item Name",
  "background_color": "#FF0000",
  "description": "Updated description",
  "attributes": [
    { "trait_type": "Rarity", "value": "Legendary" }
  ]
}
```

Only the collection owner can edit items.

### Removing Items

Remove items with `remove_items` using ethscription IDs (transaction hashes):

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "remove_items",
  "collection_id": "0x...",
  "ethscription_ids": [
    "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
    "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
  ]
}
```

Only the collection owner can remove items.

### Transferring Ownership

Transfer collection ownership with `transfer_ownership`:

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "transfer_ownership",
  "collection_id": "0x...",
  "new_owner": "0x..."
}
```

Only the current owner can transfer ownership.

### Renouncing Ownership

Permanently surrender ownership with `renounce_ownership`:

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "renounce_ownership",
  "collection_id": "0x..."
}
```

After renouncing, no one can edit the collection or add items (unless they have valid merkle proofs for a non-zero merkle root collection).

### Locking Collections

Once locked, no more items can be added:

```json
{
  "p": "erc-721-ethscriptions-collection",
  "op": "lock_collection",
  "collection_id": "0x..."
}
```

This is irreversible. Only the collection owner can lock.

### Error Handling

| Error | Cause |
|-------|-------|
| Invalid Merkle proof | Proof doesn't match root, or metadata differs from what was used to compute the leaf |
| Merkle proof required | Non-owner tried to add to a collection with zero merkle root (owner-only mode) |
| Item slot taken | Index already has an item |
| Collection locked | Cannot add to locked collection |
| Exceeds max supply | Collection is full |
| Not collection owner | Only owner can perform this operation |

### Security Considerations

1. **Content Hash Verification** - The merkle leaf includes the content hash, ensuring exact image content is verified
2. **Metadata Binding** - All metadata is bound to the merkle proof and cannot be changed after the tree is computed
3. **Owner Bypass** - Collection owners can always add items, useful for corrections
4. **Locking** - Once locked, no more items can be added even with valid proofs
5. **Zero Merkle Root** - When merkle_root is zero, only the owner can add items

### Generating Merkle Trees (TypeScript)

#### Dependencies

```bash
npm install viem
```

#### Helper Functions

```typescript
import {
  keccak256,
  encodeAbiParameters,
  stringToHex,
  concat,
  hexToBytes,
  type Hex,
} from 'viem';

/**
 * Compare two bytes32 values byte-by-byte (matches OpenZeppelin)
 */
function lt32(a: Hex, b: Hex): boolean {
  const aBytes = hexToBytes(a);
  const bBytes = hexToBytes(b);
  for (let i = 0; i < 32; i++) {
    if (aBytes[i] !== bBytes[i]) return aBytes[i] < bBytes[i];
  }
  return false;
}

/**
 * Hash pair with byte-wise ordering (matches OpenZeppelin MerkleProof)
 */
function hashPair(a: Hex, b: Hex): Hex {
  return keccak256(concat(lt32(a, b) ? [a, b] : [b, a]));
}

/**
 * Compute content hash from image bytes
 */
function computeContentHash(imageBase64: string): Hex {
  const imageBytes = Uint8Array.from(Buffer.from(imageBase64, 'base64'));
  return keccak256(imageBytes);
}

/**
 * Compute merkle leaf hash matching the Solidity contract
 */
function computeLeafHash(
  contentHash: Hex,
  itemIndex: bigint,
  name: string,
  backgroundColor: string,
  description: string,
  attributes: { traitType: string; value: string }[]
): Hex {
  const encoded = encodeAbiParameters(
    [
      { name: 'contentHash', type: 'bytes32' },
      { name: 'itemIndex', type: 'uint256' },
      { name: 'name', type: 'string' },
      { name: 'backgroundColor', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'attributes', type: 'tuple[]', components: [
        { name: 'traitType', type: 'string' },
        { name: 'value', type: 'string' },
      ]},
    ],
    [
      contentHash,
      itemIndex,
      name,
      backgroundColor,
      description,
      attributes.map(a => ({ traitType: a.traitType, value: a.value })),
    ]
  );
  return keccak256(encoded);
}

/**
 * Build merkle tree from 3 leaves
 *
 * Tree structure:
 *         root
 *        /    \
 *     H(0,1)   leaf2
 *    /    \
 * leaf0  leaf1
 */
function buildMerkleTree(leaves: [Hex, Hex, Hex]): {
  root: Hex;
  proofs: [Hex[], Hex[], Hex[]];
} {
  const [leaf0, leaf1, leaf2] = leaves;
  const h01 = hashPair(leaf0, leaf1);
  const root = hashPair(h01, leaf2);

  return {
    root,
    proofs: [
      [leaf1, leaf2],  // Proof for leaf0
      [leaf0, leaf2],  // Proof for leaf1
      [h01],           // Proof for leaf2
    ],
  };
}

/**
 * Generate data URI for collection operations
 */
function generateCollectionDataUri(
  operation: string,
  params: object,
  imageBase64: string
): string {
  const jsonBase64 = Buffer.from(JSON.stringify(params)).toString('base64');
  return `data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=${operation};d=${jsonBase64};base64,${imageBase64}`;
}

/**
 * Convert data URI to hex calldata for transaction
 */
function dataUriToHex(dataUri: string): Hex {
  return stringToHex(dataUri);
}
```

#### Complete Example

```typescript
// Sample 1x1 pixel PNGs (red, green, blue)
const IMAGES = [
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEBgIApD5fRAAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBgIA/JDm2AAAAABJRU5ErkJggg==',
];

const ITEMS = [
  { name: 'Item #1', bg: '#FF0000', desc: 'First item', attrs: [{ traitType: 'Color', value: 'Red' }] },
  { name: 'Item #2', bg: '#00FF00', desc: 'Second item', attrs: [{ traitType: 'Color', value: 'Green' }] },
  { name: 'Item #3', bg: '#0000FF', desc: 'Third item', attrs: [{ traitType: 'Color', value: 'Blue' }] },
];

const OWNER_ADDRESS = '0xYourAddressHere';

// Step 1: Compute content hashes
const contentHashes = IMAGES.map(img => computeContentHash(img));
console.log('Content hashes:', contentHashes);

// Step 2: Compute merkle leaves
const leaves = ITEMS.map((item, i) => computeLeafHash(
  contentHashes[i],
  BigInt(i),
  item.name,
  item.bg,
  item.desc,
  item.attrs
)) as [Hex, Hex, Hex];
console.log('Leaves:', leaves);

// Step 3: Build merkle tree
const { root: merkleRoot, proofs } = buildMerkleTree(leaves);
console.log('Merkle root:', merkleRoot);
console.log('Proofs:', proofs);

// Step 4: Generate create collection calldata
const createParams = {
  metadata: {
    name: 'My Collection',
    symbol: 'MYC',
    max_supply: '3',
    description: 'A merkle-enforced collection',
    logo_image_uri: '',
    banner_image_uri: '',
    background_color: '',
    website_link: '',
    twitter_link: '',
    discord_link: '',
    merkle_root: merkleRoot,
    initial_owner: OWNER_ADDRESS.toLowerCase(),
  },
  item: {
    item_index: '0',
    name: ITEMS[0].name,
    background_color: ITEMS[0].bg,
    description: ITEMS[0].desc,
    attributes: ITEMS[0].attrs.map(a => ({ trait_type: a.traitType, value: a.value })),
    merkle_proof: [],  // Owner bypasses merkle check
  },
};

const createDataUri = generateCollectionDataUri(
  'create_collection_and_add_self',
  createParams,
  IMAGES[0]
);

console.log('Create collection data URI:', createDataUri);
console.log('Create collection hex:', dataUriToHex(createDataUri));

// Step 5: Generate add item calldata (for non-owner)
// Replace with actual collection_id after creating collection
const COLLECTION_ID = '0x<tx-hash-from-create>';

const addItemParams = {
  collection_id: COLLECTION_ID,
  item: {
    item_index: '1',
    name: ITEMS[1].name,
    background_color: ITEMS[1].bg,
    description: ITEMS[1].desc,
    attributes: ITEMS[1].attrs.map(a => ({ trait_type: a.traitType, value: a.value })),
    merkle_proof: proofs[1],  // Include proof for non-owner
  },
};

const addDataUri = generateCollectionDataUri(
  'add_self_to_collection',
  addItemParams,
  IMAGES[1]
);

console.log('Add item data URI:', addDataUri);
console.log('Add item hex:', dataUriToHex(addDataUri));
```

### Sending Transactions

To create an ethscription, send a 0 ETH transaction with the hex calldata:

```typescript
import { createWalletClient, http } from 'viem';
import { mainnet } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

const account = privateKeyToAccount('0xYourPrivateKey');
const client = createWalletClient({
  account,
  chain: mainnet,
  transport: http('https://your-rpc-url'),
});

// Self-ethscription (send to yourself)
const txHash = await client.sendTransaction({
  to: account.address,
  data: dataUriToHex(createDataUri),
  value: 0n,
});

console.log('Transaction hash (this is the collection_id):', txHash);
```

---

<a id="page-17-fixed-denomination-tokens"></a>
# PAGE 17: FIXED DENOMINATION TOKENS — https://docs.ethscriptions.com/ethscriptions-appchain/fixed-denomination-tokens

## Fixed Denomination Tokens

### Overview

Unlike standard ERC-20 tokens where users can transfer arbitrary amounts, fixed denomination tokens:
- Move in fixed batches (the denomination)
- Are tied to NFT notes that represent the token amount
- Transfer automatically when the note transfers

### How It Differs from Standard ERC-20

| Feature | Standard ERC-20 | Fixed Denomination |
|---------|----------------|-------------------|
| Transfer amount | Arbitrary via `transfer()` | Fixed denomination only |
| Transfer method | Function call | NFT note transfer |
| Divisibility | Yes | No (whole notes only) |
| Balance tracking | Single balance | Sum of owned notes |

### Deploy a Token

```
data:application/json,{"p":"erc-20-fixed-denomination","op":"deploy","tick":"mytoken","max":"1000000","lim":"1000"}
```

### Deploy Parameters

| Parameter | Description |
|-----------|-------------|
| `tick` | Token symbol (lowercase alphanumeric, max 28 characters) |
| `max` | Maximum supply (uint256, must be divisible by `lim`) |
| `lim` | Denomination amount (uint256, must divide evenly into `max`) |

**Critical Constraint:** `max` must be evenly divisible by `lim`.

### Mint Notes

```
data:application/json,{"p":"erc-20-fixed-denomination","op":"mint","tick":"mytoken","id":"1","amt":"1000"}
```

### Mint Parameters

| Parameter | Description |
|-----------|-------------|
| `tick` | Matching deployed token symbol |
| `id` | Unique identifier (>= 1) |
| `amt` | Must exactly equal the token's `lim` value |

### Transfer Mechanics

Transfer the ethscription (the mint inscription) to move tokens. When the ethscription transfers:
- The inscription moves to the new owner
- The NFT note automatically transfers
- The ERC-20 balance automatically moves

All three are synchronized atomically.

#### Standard ERC-20 (disabled)

Direct ERC-20 transfers via `transfer()` are disabled.

#### Fixed Denomination (how it works)

Users transfer the ethscription (mint inscription) to move tokens.

### Example Flow

1. **Deploy Token:** Alice deploys "mytoken" (max 10,000, denomination 100)
2. **Mint Notes:** Alice mints note #1 (receiving 100 tokens, 1 ethscription, 1 NFT)
3. **Transfer:** Alice transfers the mint inscription to Bob, who receives all three synchronized assets

### Querying Balances

#### ERC-20 Balance

```
balanceOf(address)
```

#### Note Ownership

```
ownerOf(noteId)
```

### Use Cases

- **Collectible Tokens** - tokens with NFT-like properties
- **Batch Transfers** - move fixed amounts efficiently
- **Marketplace Trading** - trade token notes on NFT marketplaces
- **Fair Distribution** - fixed denomination ensures equal minting

### Technical Details

#### Contract Architecture

The system uses `ERC20FixedDenominationManager` and `ERC20FixedDenomination` contracts with atomic transfer enforcement, on-chain ownership verification, and immutable denomination parameters.

---

<a id="page-18-running-a-node"></a>
# PAGE 18: RUNNING A NODE — https://docs.ethscriptions.com/ethscriptions-appchain/running-a-node

## Running a Node

### Prerequisites

- Docker Desktop (includes the Compose plugin)
- L1 RPC endpoint - Archive-quality recommended for historical sync

### Quick Start

```bash
git clone https://github.com/ethscriptions-protocol/ethscriptions-node.git
cd ethscriptions-node
cp docker-compose/.env.example docker-compose/.env
cd docker-compose
docker compose --env-file .env up -d
docker compose logs -f node
curl -X POST http://localhost:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
docker compose down
```

### Services

| Service | Description |
|---------|-------------|
| geth | Ethscriptions-customized Ethereum execution client (L2) |
| node | Ruby derivation app that processes L1 data into L2 blocks |

The node waits for geth to be healthy before starting. Both services communicate via a shared IPC socket.

### Environment Reference

#### Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| COMPOSE_PROJECT_NAME | Docker resource naming prefix | ethscriptions-evm |
| JWT_SECRET | 32-byte hex for Engine API auth | - |
| L1_NETWORK | Ethereum network | mainnet |
| L1_RPC_URL | Archive-quality L1 RPC endpoint | - |
| L1_GENESIS_BLOCK | L1 block where rollup anchors | 17478949 |
| GENESIS_FILE | Genesis snapshot filename | ethscriptions-mainnet.json |
| GETH_EXTERNAL_PORT | Host port for L2 RPC | 8545 |

#### Performance Tuning

| Variable | Description | Default |
|----------|-------------|---------|
| L1_PREFETCH_FORWARD | Blocks to prefetch ahead | 200 |
| L1_PREFETCH_THREADS | Prefetch worker threads | 10 |
| JOB_CONCURRENCY | SolidQueue worker concurrency | 6 |
| JOB_THREADS | Job worker threads | 3 |

#### Geth Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| GC_MODE | full or archive | full |
| STATE_HISTORY | State trie history depth | 100000 |
| TX_HISTORY | Transaction history depth | 100000 |
| ENABLE_PREIMAGES | Retain preimages | true |
| CACHE_SIZE | State cache size | 25000 |

#### Validation (Optional)

| Variable | Description | Default |
|----------|-------------|---------|
| VALIDATION_ENABLED | Enable validator against reference API | false |
| ETHSCRIPTIONS_API_BASE_URL | Reference API endpoint | - |
| ETHSCRIPTIONS_API_KEY | API authentication key | - |

### Monitoring

#### View Logs

```bash
docker compose logs -f
docker compose logs -f node
docker compose logs -f geth
```

#### Check Block Height

```bash
curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n"
```

#### Check Sync Status

The derivation node logs show the current L1 block being processed. Compare this to the current L1 head to gauge sync progress.

### Validator (Optional)

The validator compares L2 state against a reference Ethscriptions API to verify derivation correctness. It pauses the importer when discrepancies appear so you can investigate.

```
VALIDATION_ENABLED=true
ETHSCRIPTIONS_API_BASE_URL=https://your-api-endpoint.com
ETHSCRIPTIONS_API_KEY=your-api-key
```

The temporary SQLite databases in storage/ and the SolidQueue worker pool support this reconciliation. Once historical import is verified, the derivation app remains stateless.

### Local Development

```bash
ruby --version
bundle install
bin/setup
```

The Docker Compose stack is recommended for production-like runs.

### Troubleshooting

#### Node won't start
- Check geth health: `docker compose ps`
- Verify L1_RPC_URL accessibility
- Ensure JWT_SECRET matches between services

#### Slow sync
- Increase L1_PREFETCH_FORWARD and L1_PREFETCH_THREADS
- Use faster L1 RPC endpoint
- Consider archive mode only if needed

#### Out of disk space
- Pruned mode uses less space
- Reduce STATE_HISTORY and TX_HISTORY

### Resources

- [ethscriptions-node GitHub](https://github.com/ethscriptions-protocol/ethscriptions-node)
- [ethscriptions-geth GitHub](https://github.com/ethscriptions-protocol/ethscriptions-geth)
