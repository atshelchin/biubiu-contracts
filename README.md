# BiuBiu Contracts

A collection of Solidity smart contracts for token creation, NFT minting, batch distribution, and utility functions.

## Architecture

```
src/
├── core/                    # Core protocol contracts
│   ├── BiuBiuPremium.sol   # Premium membership subscription NFT
│   └── WETH.sol            # Wrapped ETH with depositAndApprove
├── tools/                   # Tool contracts
│   ├── TokenFactory.sol    # CREATE2 ERC20 token deployment
│   ├── NFTFactory.sol      # ERC721 NFT collection factory
│   ├── NFTMetadata.sol     # On-chain SVG metadata generator
│   ├── TokenDistribution.sol # Batch token distribution
│   └── TokenSweep.sol      # Multi-wallet token sweep
└── interfaces/              # Stable API interfaces
    ├── IBiuBiuPremium.sol
    ├── IWETH.sol
    ├── ITokenFactory.sol
    ├── INFTFactory.sol
    ├── INFTMetadata.sol
    ├── ITokenDistribution.sol
    └── ITokenSweep.sol
```

## Contracts

### Core Contracts

| Contract | Description |
|----------|-------------|
| **BiuBiuPremium** | Premium membership subscription NFT (Monthly/Yearly tiers) with referral system |
| **WETH** | Wrapped ETH with `depositAndApprove` functionality |

**Revenue Vault:** `0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA` (Safe Wallet)

### Tool Contracts

| Contract | Description |
|----------|-------------|
| **TokenFactory** | CREATE2 deterministic ERC20 token deployment with referral system |
| **NFTFactory** | ERC721 NFT collection factory with social drift features |
| **NFTMetadata** | On-chain SVG metadata generator for NFTs |
| **TokenDistribution** | Batch distribute ETH/WETH/ERC20/ERC721/ERC1155 with EIP-712 signatures |
| **TokenSweep** | Sweep tokens from multiple wallets with EIP-7702 signature authorization |

## CREATE2 Deterministic Addresses

All contracts use CREATE2 for deterministic deployment addresses across any EVM chain.

**Proxy:** `0x4e59b44847b379578588920cA78FbF26c0B4956C`
**Salt:** `0`

| Contract | Address | Note |
|----------|---------|------|
| WETH | `0x82f4998846624B464e0974306dE744dA50D93320` | |
| BiuBiuPremium | `0xc44461c1e8124D314A651172a5bdC594deb28052` | |
| NFTMetadata | `0x728978f21C90Ac522F872CF95B54fc59E4066c10` | |
| TokenFactory | `0x9076A37E7b6f0874A6a0CC5061bc7312Dd2d1dF8` | |
| NFTFactory | `0x59c7468015BDD7E0cB2cdD148bA410ea29abf2Fd` | |
| TokenDistribution | `0x7Ea0e2e85Ff168Cdc401Fd92933c271a798DdA08` | |
| TokenSweep | `0x9Fe32035f1bC78cC578eF3f4513932bd2a92863F` | |

**Safe Wallet (Vault):** `0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA`

## Interfaces

All contracts implement stable interfaces for frontend integration:

```solidity
import {IBiuBiuPremium} from "src/interfaces/IBiuBiuPremium.sol";
import {ITokenDistribution, Recipient} from "src/interfaces/ITokenDistribution.sol";
import {ITokenSweep, Wallet} from "src/interfaces/ITokenSweep.sol";
```

## Development

```bash
# Setup (enable frozen file protection)
git config core.hooksPath .githooks

# Build
forge build

# Test
forge test

# Test with verbosity
forge test -vvv

# Compute addresses
forge script script/ComputeAllAddresses.s.sol

# Print specific contract address
forge script script/WETH.s.sol:WETHScript --sig "printAddress()"
```

## Security

All contracts have been audited. See [audits/](audits/) for detailed reports.

| Contract | Risk Level |
|----------|------------|
| WETH | LOW |
| BiuBiuPremium | LOW |
| TokenFactory | LOW |
| NFTFactory | LOW |
| NFTMetadata | MINIMAL |
| TokenDistribution | LOW |
| TokenSweep | LOW |

## License

MIT
