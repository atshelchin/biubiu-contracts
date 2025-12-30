# BiuBiu Contracts

A collection of smart contracts for token creation, NFT minting, token distribution, and utility functions.

## Contracts

- **WETH** - Wrapped ETH with `depositAndApprove` functionality
- **TokenFactory** - CREATE2 deterministic ERC20 token deployment
- **NFTFactory** - ERC721 with stake-to-mint mechanism
- **TokenDistribution** - Batch distribute ETH/ERC20/ERC721/ERC1155 to multiple recipients
- **TokenSweep** - Sweep tokens from multiple wallets
- **BiuBiuPremium** - Premium membership subscription

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
| WETH | `0xe3E75C1fe9AE82993FEb6F9CA2e9627aaE1e3d18` |
| TokenDistribution | `0xD35cE8751e46D518D4bb650e271696903BaFF70C` |
| TokenFactory | `0xd53219D61e6F7305d5D6e23F29197F3AD58521E1` |
| NFTFactory | `0xB003AdCD063aAAe88A634aC65257820c1322751D` |
| TokenSweep | `0x28ab612a3a871EA203aDff9a7b0846C395529239` |
| BiuBiuPremium | `0x61Ae52Bb677847853DB30091ccc32d9b68878B71` |

## Documentation

https://book.getfoundry.sh/
