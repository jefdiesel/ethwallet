# Session Notes — 2026-02-02

## Ethscription Lookup on /resolve

Added an "Ethscription Lookup" section to `/resolve` where users enter a mainnet tx hash (ethscription ID) and get appchain explorer links plus collection traits.

**How it works:**
1. User enters mainnet tx hash
2. Frontend chains 3-4 RPC calls to `mainnet.ethscriptions.com` against the appchain manager (`0x3300...0006`):
   - `getEthscriptionTokenId(bytes32)` — gets master token ID
   - `getMembershipOfEthscription(bytes32)` — returns `(collectionId, collectionTokenId)`
   - `getCollectionAddress(collectionId)` — gets collection contract address
   - `tokenURI(tokenId)` on collection — returns base64 JSON with name + traits
3. Displays master token link, collection token link, name, and trait chips

**Key addresses:**
- Appchain RPC: `https://mainnet.ethscriptions.com`
- Appchain Manager: `0x3300000000000000000000000000000000000006`
- Appchain Master Token: `0x3300000000000000000000000000000000000001`
- Explorer: `https://explorer.ethscriptions.com/token/{contract}/instance/{tokenId}`

**Test hash:** `0x663d852b815d38fc0f84ca840e591258974f4f6db1a714eb39247e752c415fcd` — Comrade #1054, 9 traits.

---

## WrappedEthscription Contract v2 — Display Name Support

Redeployed the wrapping contract to support per-token display names (e.g. "Comrade #1054" instead of "Ethscription #663d852b").

**Changes:**
- Added `_namePtrs` mapping — SSTORE2 pointer for display name per token
- `wrap()` now takes 4 params: `(bytes32 ethscriptionId, string contentURI, string attributes, string displayName)`
- `tokenURI()` uses stored display name when available, falls back to `Ethscription #XXXX`
- `unwrap()` clears `_namePtrs`
- New selector: `0xf0dc2674`

**Previous contract:** `0x87D5642B22095c642698E204688377e685Fca7f7`
**New contract:** `0xdd24Df07f9145342Ab3fE652A7920ad212af9D21`
**Deploy tx:** `0xa1232ba75cbfb504ac69be65d3ed37a3171f3251d113608de4cf9a2e6986d842`
**Deployer:** `0x58e244c1FC95f59f9E4b71572C0082148129b8D7`

**Frontend changes (wrap page):**
- `fetchTraits()` now returns `{ name, traits }` separately — name no longer injected as a trait
- `collectionName` state shown above traits in the UI
- `abiEncodeWrap()` updated for 4 dynamic params
- `WRAP_SELECTOR` updated to `0xf0dc2674`
- `handleWrap()` passes collection name as 4th arg

**Important:** Existing wrapped NFTs on the old contract are unaffected but won't have display names. They'd need to be unwrapped from the old contract and re-wrapped on the new one.

---

## OpenSea Metadata

**What tokenURI provides (per-token):**
- `name` — display name (now customizable)
- `description` — "Wrapped ethscription"
- `image` — SVG-wrapped content (black bg, #C3FF00 text for text items; pixelated upscale for images)
- `attributes` — trait array from appchain collection data

**Not yet added but available:**
- `external_url` — link to ethscriptions.com page
- `animation_url` — for HTML ethscriptions (interactive rendering on OpenSea)
- `background_color` — hex color without # (e.g. `"000000"`)

**Collection-level (set via OpenSea UI, not tokenURI):**
- Collection name, banner, logo, description — editable at opensea.io by connecting deployer wallet
- Royalty info — via EIP-2981 `royaltyInfo()` (not implemented yet)

**Key insight:** `contract.name()` sets the default collection name on OpenSea, but it can be overridden in the OpenSea UI without redeploying. Each ERC-721 contract = one OpenSea collection. Multiple collections require multiple contracts (or a factory/clone pattern via EIP-1167).

---

## Multi-Collection Wrapping (Future)

For wrapping multiple collections (e.g. Comrades, Punks, etc.) as separate OpenSea collections:

- Each OpenSea collection = one contract address (no way around this)
- **EIP-1167 minimal proxy (clone) pattern** — deploy one master `WrappedEthscription`, then a factory that creates cheap clones (~45 bytes, ~$2-3 each) with different `name`/`symbol`
- Factory would have `createCollection(name, symbol)` and the UI gets a collection picker dropdown
- Not implemented yet, but the architecture is straightforward

---

## Wrapped Ethscriptions Viewer (HTML Inscription)

Built a self-contained HTML page (`contracts/viewer.html`) for inscribing on-chain as proof of escrow.

**Features:**
- Queries ethscriptions API for all items held by the wrapping contract
- Lazy-loading scroll via IntersectionObserver (20 items at a time)
- `loading="lazy"` on images
- Search by tx hash or token number
- Each item shows: tx hash (Etherscan link), OpenSea link, Ethscriptions link
- Styled: black background, monospace, #C3FF00 accents

**Not yet inscribed.** Ready to be inscribed as `data:text/html;...` ethscription.

---

## Marketplace

**Status:** Back online after Supabase project pause/restore.

**Architecture:**
- Contract addresses: Ethereum `0x7af895301ab8a0ab13fe87819cc6f62f03689988`, Base `0x33796ce232bf02481de14a5e2b8e76d5687cb43f`
- Listings stored in Supabase PostgreSQL (`marketplace_listings`, `marketplace_offers`, `marketplace_sales`)
- API routes at `/api/marketplace/*`
- Platform fee: 2.5%

**Supabase credentials:**
- Project URL: `https://rvmuhstovplabuvnkrpj.supabase.co`
- Schema: `sql/marketplace-schema.sql`
- Free tier pauses after inactivity — need to unpause from dashboard when this happens

**Current listings:** 2 active (`xmas2025` at 0.00111 ETH, `woohoo` at 0.0069 ETH)

---

## SVG Rendering in Contract

Text ethscriptions (`data:,{name}`) are rendered as SVGs in `tokenURI`:
- 500x500 SVG
- Black background (`#000`)
- #C3FF00 monospace text, centered
- XML-escaped for safety

Image ethscriptions are wrapped in SVG with `image-rendering: pixelated` for clean upscaling.

---

## Test Results

Forge tests: 36/38 pass. 2 pre-existing failures in ESIP-2 event `previousOwner` assertion (test expects `alice`, contract emits contract address) — unrelated to current changes.

Next.js build: passes clean.
