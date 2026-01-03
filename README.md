# BiuBiu Contracts

A collection of Solidity smart contracts for token creation, NFT minting, batch distribution, and utility functions.

## Architecture

```
src/
├── core/                    # Core protocol contracts
│   ├── BiuBiuPremium.sol   # Premium membership subscription NFT
│   ├── BiuBiuVault.sol     # Epoch-based revenue distribution vault
│   ├── BiuBiuShare.sol     # DAO token for vault rewards
│   └── WETH.sol            # Wrapped ETH with depositAndApprove
├── tools/                   # Tool contracts
│   ├── TokenFactory.sol    # CREATE2 ERC20 token deployment
│   ├── NFTFactory.sol      # ERC721 NFT collection factory
│   ├── NFTMetadata.sol     # On-chain SVG metadata generator
│   ├── TokenDistribution.sol # Batch token distribution
│   └── TokenSweep.sol      # Multi-wallet token sweep
└── interfaces/              # Stable API interfaces
    ├── IBiuBiuPremium.sol
    ├── IBiuBiuVault.sol
    ├── IBiuBiuShare.sol
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
| **BiuBiuPremium** | Premium membership subscription NFT (Daily/Monthly/Yearly tiers) with referral system |
| **BiuBiuVault** | Epoch-based revenue distribution vault for DAO token holders |
| **BiuBiuShare** | ERC20 DAO token with fixed supply for vault rewards |
| **WETH** | Wrapped ETH with `depositAndApprove` functionality |

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

| Contract | Address |
|----------|---------|
| WETH | `0xFe7291380b8Dc405fEf345222f2De2408A6CA18e` |
| BiuBiuPremium | `0x61Ae52Bb677847853DB30091ccc32d9b68878B71` |
| NFTMetadata | `0xF68B52ceEAFb4eDB2320E44Efa0be2EBe7a715A6` |
| TokenFactory | `0xe731602Ff2C355Ca0e6CE68932AFaA6ff973aE79` |
| NFTFactory | `0x917e63eD2FA8BF71d11BAF6cAdcaC65098a68499` |
| TokenDistribution | `0x57A2dB6B6cf17a1b9B7F1B9e269e88A180291221` |
| TokenSweep | `0x34bb5CE9B48bEb31ed3763e80DD0d93cb7C8842b` |

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
| BiuBiuVault | LOW |
| BiuBiuShare | MINIMAL |
| TokenFactory | LOW |
| NFTFactory | LOW |
| NFTMetadata | MINIMAL |
| TokenDistribution | LOW |
| TokenSweep | LOW |

## License

MIT
