# Token Address Prediction (CREATE2)

## How It Works

The TokenFactory uses CREATE2 to deploy tokens at deterministic addresses:

```
Token Address = keccak256(
  0xff,
  factoryAddress,
  salt,
  keccak256(initCode)
)

Where:
  salt = keccak256(creator, name, symbol, decimals, initialSupply, mintable)
```

## Usage

### On-Chain (Solidity)

```solidity
address predicted = factory.predictTokenAddress(
  "Bitcoin",           // name
  "BTC",              // symbol
  18,                 // decimals
  21000000 ether,     // initialSupply
  false,              // mintable
  msg.sender          // creator
);

// Deploy and verify
address actual = factory.createToken("Bitcoin", "BTC", 18, 21000000 ether, false);
assert(predicted == actual);
```

### Off-Chain (JavaScript/TypeScript)

Use ethers.js to calculate the same address:

```javascript
const { ethers } = require('ethers');

// 1. Calculate salt
const salt = ethers.keccak256(
  ethers.solidityPacked(
    ['address', 'string', 'string', 'uint8', 'uint256', 'bool'],
    [creator, name, symbol, decimals, initialSupply, mintable]
  )
);

// 2. Get bytecode (run: forge inspect SimpleToken bytecode)
const bytecode = '0x...';

// 3. Encode constructor args
const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
  ['string', 'string', 'uint8', 'uint256', 'bool', 'address'],
  [name, symbol, decimals, initialSupply, mintable, creator]
);

// 4. Calculate address
const initCode = ethers.concat([bytecode, constructorArgs]);
const initCodeHash = ethers.keccak256(initCode);
const predicted = ethers.getCreate2Address(factoryAddress, salt, initCodeHash);
```

## Cross-Chain Deployment

**Key Insight**: Same parameters + same factory address = same token address across all chains!

```javascript
// Deploy on Ethereum
const ethTx = await ethFactory.createToken("Universal", "UNI", 18, 1000000, false);
// → 0x1234...5678

// Deploy on Base (same factory address)
const baseTx = await baseFactory.createToken("Universal", "UNI", 18, 1000000, false);
// → 0x1234...5678 ✅ SAME ADDRESS!
```

## Important Notes

1. **All parameters must match** for same address
2. **Factory address must be same** across chains
3. **Creator (msg.sender) must be same** wallet
4. **No uniqueness restrictions** - anyone can create any name/symbol
5. **Same creator + same params** on same chain will revert
