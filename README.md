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
| WETH | `0x8c818450FD5C285923e76Be0dd0160Ad83dF396C` | |
| BiuBiuPremium | `0x0aCDaae6b87c30306f70f3936B4eac3D0073C6Eb` | |
| NFTMetadata | `0x4380Ccb96103bDcA6839be9710c997C59f9b8954` | |
| TokenFactory | `0xf821f1ea1cEc1b2f6e805a011BB22034936e5982` | |
| NFTFactory | `0xc0Be3ABa94d02bB392FB9dc257049e9240F09060` | |
| TokenDistribution | `0x4477f1E6A48453Dc9ceCa95297A2DF7257F4E524` | |
| TokenSweep | `0x2e35A3B353B54ce95Fe37FDDBe93C1cE4064c832` | |

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
