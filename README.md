# SCR Licence Pass

On-chain licence passes for the [Strategic Crypto Reserve AI Build Configurator](https://strategiccryptoreserve.ca/ai-build-configurator.html).

One **non-transferable ERC-721 pass (ERC-5192 locked)** per licensed domain on Polygon PoS. Each pass records:

| Field | Meaning |
|---|---|
| `tier` | 1 Standard · 2 Pro · 3 Enterprise |
| `domainHash` | `keccak256(lowercase hostname, no "www.")` |
| `expiry` | Unix time the annual term ends (exclusive) |
| `revoked` | Set after a refund or a terms breach |

Anyone can verify a licence by calling `check(domainHash)`, which returns `(valid, tier, expiry, tokenId)`.

## Deployments
| Network | Address | Source |
|---|---|---|
| Polygon PoS (mainnet) | [`0x93ef5A4b199bdBa8bf552aB30B17F5767c05B145`](https://polygonscan.com/address/0x93ef5A4b199bdBa8bf552aB30B17F5767c05B145#code) | Verified (Polygonscan, Sourcify exact match) |
| Polygon Amoy (testnet) | [`0x93ef5A4b199bdBa8bf552aB30B17F5767c05B145`](https://amoy.polygonscan.com/address/0x93ef5A4b199bdBa8bf552aB30B17F5767c05B145#code) | Verified (Polygonscan, Sourcify exact match) |

Same address on both networks (same deployer, first transaction). USDC prices on mainnet: Standard 2,850 USDC, Pro 7,100 USDC, Enterprise quoted (not sold for USDC). USDC is optional: card checkout is the default and **no crypto wallet is ever required**. Passes for card buyers are minted to, and held by, the operator wallet on the buyer's behalf.

## Widget integration
The configurator widget (v1.8.1+) computes `keccak256(hostname)` for the embedding page (and its parent domains, `www.` ignored), calls `check()` through a public Polygon RPC, and:
- renders a domain with a valid pass at the pass tier, with no key needed;
- switches off a domain whose pass is revoked or expired on that page load;
- keeps the existing hashed-key licences working unchanged for domains with no pass;
- caches the last answer in `localStorage` for up to 7 days so an RPC outage never breaks a licensed embed.

## Payments
- **Card checkout** (existing): a paid checkout triggers `mint()` by the minter key.
- **USDC on Polygon** (optional): `buyWithUSDC(domainHash, tier, to)` pulls USDC from the payer **straight to the treasury** and mints or renews. The contract never holds funds. A tier with price 0 is not sold for USDC (Enterprise is quoted).

## Roles
- `DEFAULT_ADMIN_ROLE`: deployer key and the owner's wallet. Sets prices and treasury, moves or burns passes.
- `MINTER_ROLE`: mints, renews, changes tier, revokes.

## Build & test
```
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 foundry-rs/forge-std
forge build
forge test
forge coverage --no-match-coverage 'test|script'
slither . --filter-paths "lib/|test/"
```
Current results: 28 tests passing (incl. fuzz), 100% line/statement/branch/function coverage, Slither 0.11.6: 0 high / 0 medium / 4 low (timestamp comparisons, expected for annual licence terms; see `audit/`).

## Deploy
```
forge script script/Deploy.s.sol --rpc-url amoy    --private-key <key> --broadcast --verify
forge script script/Deploy.s.sol --rpc-url polygon --private-key <key> --broadcast --verify
```

## Licence
Apache 2.0. Built under a Compound Grants (Questbook) proposal, Milestone 1.
