#!/bin/bash
# Deploy contracts to Endurance chain (Chain ID: 648)
# Usage: ./script/deploy-endurance.sh <contract_name>
# Example: ./script/deploy-endurance.sh WETH

set -e

# Configuration
RPC_URL="https://rpc-endurance.fusionist.io"
CREATE2_PROXY="0x4e59b44847b379578588920cA78FbF26c0B4956C"
SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <contract_name>"
    echo "Example: $0 WETH"
    echo ""
    echo "Available contracts:"
    echo "  WETH, BiuBiuPremium, TokenFactory, NFTFactory"
    echo "  NFTMetadata, TokenDistribution, TokenSweep"
    exit 1
fi

CONTRACT=$1

# Check PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable not set"
    echo "Run: export PRIVATE_KEY=0x..."
    exit 1
fi

echo "=== Deploying $CONTRACT to Endurance (Chain ID: 648) ==="

# Get bytecode
echo "Getting bytecode..."
BYTECODE=$(forge inspect $CONTRACT bytecode)

if [ -z "$BYTECODE" ] || [ "$BYTECODE" == "0x" ]; then
    echo "Error: Could not get bytecode for $CONTRACT"
    exit 1
fi

# Compute expected address
echo "Computing deterministic address..."
BYTECODE_HASH=$(cast keccak "$BYTECODE")
EXPECTED_ADDRESS=$(cast compute-address2 --deployer $CREATE2_PROXY --salt $SALT --init-code-hash "$BYTECODE_HASH" | grep "Computed Address" | awk '{print $3}')

echo "Expected address: $EXPECTED_ADDRESS"

# Check if already deployed
EXISTING_CODE=$(cast code $EXPECTED_ADDRESS --rpc-url $RPC_URL 2>/dev/null || echo "0x")
if [ "$EXISTING_CODE" != "0x" ]; then
    echo "Contract already deployed at $EXPECTED_ADDRESS"
    exit 0
fi

# Construct payload: salt + bytecode (remove 0x prefix from bytecode)
PAYLOAD="${SALT}${BYTECODE:2}"

# Deploy
echo "Deploying via CREATE2 Proxy..."
TX_HASH=$(cast send $CREATE2_PROXY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --gas-limit 5000000 \
    "$PAYLOAD" \
    --json | jq -r '.transactionHash')

echo "Transaction hash: $TX_HASH"

# Wait for confirmation
echo "Waiting for confirmation..."
cast receipt $TX_HASH --rpc-url $RPC_URL --json | jq '{status, gasUsed, contractAddress}'

# Verify deployment
DEPLOYED_CODE=$(cast code $EXPECTED_ADDRESS --rpc-url $RPC_URL)
if [ "$DEPLOYED_CODE" != "0x" ]; then
    echo ""
    echo "=== SUCCESS ==="
    echo "$CONTRACT deployed at: $EXPECTED_ADDRESS"
    echo "Explorer: https://explorer-endurance.fusionist.io/address/$EXPECTED_ADDRESS"
else
    echo "Error: Deployment verification failed"
    exit 1
fi
