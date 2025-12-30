# BiuBiu Contracts

A collection of smart contracts for token creation, NFT minting, token distribution, and utility functions.

## Contracts

- **WETH** - Wrapped ETH with `depositAndApprove` functionality
- **TokenFactory** - CREATE2 deterministic ERC20 token deployment
- **NFTFactory** - ERC721 NFT collection factory with social features
- **NFTMetadata** - On-chain SVG metadata generator for NFTs
- **TokenDistribution** - Batch distribute ETH/ERC20/ERC721/ERC1155 to multiple recipients
- **TokenSweep** - Sweep tokens from multiple wallets
- **BiuBiuPremium** - Premium membership subscription NFT

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Test with Verbosity

```shell
forge test -vvv
```

### Test Specific Contract

```shell
forge test --match-contract TokenDistributionTest
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Compute CREATE2 Addresses

```shell
forge clean && forge script script/ComputeAllAddresses.s.sol -vvvv
```

### Local Development

```shell
anvil
```

### Deploy

```shell
forge script script/DeployTokenFactory.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Verify Deployment

```shell
forge script script/VerifyDeployment.s.sol --rpc-url <your_rpc_url>
```

## CREATE2 Deterministic Addresses

Using CREATE2 Proxy `0x4e59b44847b379578588920cA78FbF26c0B4956C` with salt `0`:

| Contract | Address |
|----------|---------|
| WETH | `0xFe7291380b8Dc405fEf345222f2De2408A6CA18e` |
| TokenDistribution | `0x57A2dB6B6cf17a1b9B7F1B9e269e88A180291221` |
| TokenFactory | `0xe731602Ff2C355Ca0e6CE68932AFaA6ff973aE79` |
| NFTFactory | `0x917e63eD2FA8BF71d11BAF6cAdcaC65098a68499` |
| NFTMetadata | `0xF68B52ceEAFb4eDB2320E44Efa0be2EBe7a715A6` |
| TokenSweep | `0x34bb5CE9B48bEb31ed3763e80DD0d93cb7C8842b` |
| BiuBiuPremium | `0x61Ae52Bb677847853DB30091ccc32d9b68878B71` |

## Documentation

https://book.getfoundry.sh/
