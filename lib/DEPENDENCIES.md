# Vendored dependencies

These are ordinary source files, not submodules. No install step is needed to build.
Production dependencies are limited to the ERC-20 import closure below. All other
Solidity files under `lib/forge-std` are test support.

| Package | Pinned release | Upstream |
| --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2 |
| Forge Standard Library | v1.9.7 | https://github.com/foundry-rs/forge-std/tree/v1.9.7 |

OpenZeppelin files included unchanged:

- `contracts/token/ERC20/ERC20.sol`
- `contracts/token/ERC20/IERC20.sol`
- `contracts/token/ERC20/extensions/IERC20Metadata.sol`
- `contracts/utils/Context.sol`
- `contracts/interfaces/draft-IERC6093.sol`
- `LICENSE` (MIT)

Forge Standard Library: the complete `src/` directory plus `LICENSE-MIT` and
`LICENSE-APACHE`, unchanged. No upstream tests, scripts, repository configuration,
or submodules are included.

The release archives downloaded from `https://codeload.github.com/<upstream>/tar.gz/refs/tags/<release>`
had these SHA-256 digests:

```text
openzeppelin-contracts v5.0.2
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a

forge-std v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```
