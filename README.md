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
| **BiuBiuPremium** | Premium membership subscription NFT (Monthly/Yearly tiers) with referral system |
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

| Contract | Address | Note |
|----------|---------|------|
| WETH | `0x8c818450FD5C285923e76Be0dd0160Ad83dF396C` | |
| BiuBiuPremium | `0xa25033300e8e886E3e503eaa0dfB05D8b90D6F7E` | |
| BiuBiuVault | `0x6233BE8a53D878B8cCbDA35692Ee901C3201032C` | |
| BiuBiuShare | `0x58CF0902133F6965f3E28FB4BD54AdfcA9295806` | Deployed by BiuBiuVault |
| NFTMetadata | `0x4380Ccb96103bDcA6839be9710c997C59f9b8954` | |
| TokenFactory | `0x0a1f50ccc66d0688e1353F1581F31d03F8C7A1e3` | |
| NFTFactory | `0xDe9245EC38A3Ae0028a8E4CfBA5825eDee1270F0` | |
| TokenDistribution | `0x6CB341DC6cb7da4Ae9b2B2aE15Ad97a1c74c3c07` | |
| TokenSweep | `0x0385D461BC94b60C791951242Df148033E641b27` | |

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
