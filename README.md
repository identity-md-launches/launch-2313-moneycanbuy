# moneycanbuy (YOLO)

An immutable ERC-20 token. The constructor mints **1,000,000,000 YOLO** with
**18 decimals** to its immediate caller once. Transfers and approvals use the
vendored OpenZeppelin Contracts v5.0.2 implementation.

| Deployment parameter | Value |
| --- | --- |
| Solidity artifact | `src/MoneyCanBuy.sol:MoneyCanBuy` |
| Solidity contract identifier | `MoneyCanBuy` |
| Token name | `moneycanbuy` |
| Token symbol | `YOLO` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | `msg.sender`, the immediate deployer |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | None |
| Intended launch chain | Ethereum, chain ID 1 |

## Behavior and assumptions

The description supplies branding and a fixed supply, with no additional transfer
rules. The implementation therefore provides ordinary ERC-20 transfers and
allowances. `INITIAL_SUPPLY` is the only token-specific numeric constant.

- No further minting, burning, fees, rebasing, transfer limits, or special address exemptions.
- No owner, admin, pause, blocklist, seizure, upgrade, initializer, oracle, or external service.
- Transfers deliver the exact amount. Zero-value transfers are supported and emit
  `Transfer`. Sending to the zero address reverts, including for zero amounts.
- `approve` replaces the caller's allowance and emits `Approval`. Approvals may be
  revoked with `approve(spender, 0)`. Approving the zero address reverts.
- `transferFrom` needs the holder's allowance even if the spender is also the holder.
  Finite allowances decrease; `type(uint256).max` is an unlimited allowance and does
  not decrease. Failed operations roll back all balance and allowance changes.
- OpenZeppelin v5 does not emit `Approval` for allowance consumption during
  `transferFrom`; integrations should query `allowance()` for current values.
- There are no recipient callbacks or external calls in token operations.
- Native ETH payments and unknown function calls revert. There is no asset recovery
  function: tokens sent to this token contract, or ETH forcibly delivered to it, cannot
  be recovered through it.

## Build and check

Foundry and the pinned compiler must be installed on the checking machine. All
Solidity dependencies and their licenses are included as ordinary files in `lib/`.
No package installation, RPC, fork, environment secrets, FFI, or filesystem
cheatcode permission is needed. The compiler is selected by version, not a local path.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xb5eba3f0167d5669b13f4d50071d8595d4288fda8d8b82d7eaaec58dd8ed1412 forge test
forge fmt --check
```

Tests do not read or change environment variables. The seed above is a runner option.
The default configuration runs each fuzz test 512 times and each stateful invariant
128 times at depth 64.

`test/MoneyCanBuy.t.sol` checks metadata, minting, events, transfers, allowances,
boundary values, exact revert reasons, rollback on failure, unsupported administrative
calls, deployment size, and forbidden opcodes. Fuzz tests cover conservation and
invalid balance/allowance amounts. `test/MoneyCanBuyInvariant.t.sol` compares repeated
successful and rejected transfers and approvals against an independent accounting model.
`test/LaunchFlow.t.sol` checks CREATE2 deployment, minting to the factory instead of the
transaction origin, and exact forwarding/claim/pool transfer amounts.

The launch-flow tests exercise token movements, not a Uniswap pool. The supplied
protected tests belong to the separate launch harness: its factory, pool manager,
launch libraries, manifest, and deployment configuration are not part of this token
project. Full pool initialization and swaps are checked by that harness.

## Deployment and responsibilities

Deploy the `MoneyCanBuy` creation bytecode with no constructor arguments and no ETH.
There are no linked libraries or initialization calls. The constructor does not call
other contracts and needs no pre-existing contract on the chain. A deployment through
a factory gives **all** tokens to that factory; a direct deployment gives them to the
deploying account. The transaction origin never determines the recipient.

For the IdentityMD launch, the platform deployer supplies the factory transaction and
the separately generated manifest. No manifest, broadcast script, key, signer, or
production transaction is included here. There are no application contracts to deploy.
The token itself neither creates a pool nor allocates supply among recipients.

The specified launch factory distributes 10% (100,000,000 YOLO) through the launch
MerkleDistributor, uses 50% (500,000,000 YOLO) for liquidity, and forwards the remaining
40% (400,000,000 YOLO) to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.
These are launch responsibilities, not constructor parameters or hardcoded token
destinations. The platform's manifest step carries the supplied IMD pairing,
pool parameters, and initial market capitalization.

Before release, the deployer checks the artifact/settings and constructor arguments,
verifies the deployed source and metadata, and confirms the factory's allocation and
pool settlement using the launch harness. No on-chain deployment was performed for this
assignment. Local tests and source review are not an independent security audit.

## After launch

There are no settings, setters, admin keys, or maintenance transactions for this token.
No operator can mint more supply, recover a holder's tokens, or repair an accidental
transfer. Holders control transfers and allowances; integrations should request bounded
approvals and account for the ERC-20 approval replacement race (revoke an existing
allowance and confirm before granting a new one). The token does not execute swaps,
set market prices, or impose slippage protection.

The launch operator remains responsible for the separate distributor and pool.
Any future change to token behavior would require deploying a different token; this
deployed contract cannot be upgraded.
