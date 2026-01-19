#!/bin/bash
# Universal CREATE2 deployment script for any EVM chain
#
# Usage: ./script/deploy-create2.sh <contract_name> --rpc-url <url> [--chain-id <id>]
# Examples:
#   ./script/deploy-create2.sh WETH --rpc-url https://rpc-endurance.fusionist.io
#   ./script/deploy-create2.sh WETH --rpc-url $SEPOLIA_RPC_URL --chain-id 11155111

set -e

# ============ Configuration ============
CREATE2_PROXY="0x4e59b44847b379578588920cA78FbF26c0B4956C"
SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# ============ Parse Arguments ============
CONTRACT=""
RPC_URL=""
CHAIN_ID=""

print_usage() {
    echo "Universal CREATE2 Deployment Script"
    echo ""
    echo "Usage: $0 <contract_name> --rpc-url <url> [--chain-id <id>] [--salt <salt>]"
    echo ""
    echo "Arguments:"
    echo "  contract_name       Name of the contract to deploy (e.g., WETH)"
    echo "  --rpc-url <url>     RPC endpoint URL (required)"
    echo "  --chain-id <id>     Chain ID (optional, auto-detected if not provided)"
    echo "  --salt <salt>       Custom salt for CREATE2 (optional, default: 0x0...0)"
    echo ""
    echo "Environment variables:"
    echo "  PRIVATE_KEY         Deployer private key (required)"
    echo ""
    echo "Examples:"
    echo "  $0 WETH --rpc-url https://rpc-endurance.fusionist.io"
    echo "  $0 WETH --rpc-url \$SEPOLIA_RPC_URL --chain-id 11155111"
    echo "  $0 BiuBiuPremium --rpc-url https://eth.llamarpc.com"
    echo ""
    echo "For verification, use: ./script/verify-contract.sh"
}

while [ $# -gt 0 ]; do
    case $1 in
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --chain-id)
            CHAIN_ID="$2"
            shift 2
            ;;
        --salt)
            SALT="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1"
            print_usage
            exit 1
            ;;
        *)
            if [ -z "$CONTRACT" ]; then
                CONTRACT="$1"
            else
                echo "Error: Unexpected argument '$1'"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# ============ Validation ============
if [ -z "$CONTRACT" ]; then
    echo "Error: Contract name is required"
    print_usage
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo "Error: --rpc-url is required"
    print_usage
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable not set"
    echo "Run: export PRIVATE_KEY=0x..."
    exit 1
fi

# Auto-detect chain ID if not provided
if [ -z "$CHAIN_ID" ]; then
    echo "Detecting chain ID..."
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -z "$CHAIN_ID" ]; then
        echo "Error: Could not detect chain ID. Please provide --chain-id"
        exit 1
    fi
fi

# ============ Main Deployment ============
echo "============================================"
echo "  CREATE2 Deployment"
echo "============================================"
echo "Contract:     $CONTRACT"
echo "Chain ID:     $CHAIN_ID"
echo "RPC:          ${RPC_URL:0:60}..."
echo "Salt:         ${SALT:0:18}..."
echo "============================================"
echo ""

# Check CREATE2 proxy exists
echo "Checking CREATE2 proxy..."
PROXY_CODE=$(cast code "$CREATE2_PROXY" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x")
if [ "$PROXY_CODE" = "0x" ]; then
    echo "Error: CREATE2 Proxy not deployed on this chain"
    echo "The deterministic deployment proxy ($CREATE2_PROXY) is not available."
    exit 1
fi
echo "CREATE2 proxy found"

# Get bytecode
echo "Getting bytecode for $CONTRACT..."
BYTECODE=$(forge inspect "$CONTRACT" bytecode 2>/dev/null)

if [ -z "$BYTECODE" ] || [ "$BYTECODE" = "0x" ]; then
    echo "Error: Could not get bytecode for $CONTRACT"
    echo "Make sure the contract exists and compiles successfully"
    echo "Try: forge build"
    exit 1
fi

# Compute expected address
echo "Computing deterministic address..."
BYTECODE_HASH=$(cast keccak "$BYTECODE")
EXPECTED_ADDRESS=$(cast compute-address "$CREATE2_PROXY" \
    --salt "$SALT" \
    --init-code-hash "$BYTECODE_HASH" 2>/dev/null | grep -i "address" | awk '{print $NF}')

if [ -z "$EXPECTED_ADDRESS" ]; then
    echo "Error: Could not compute address"
    exit 1
fi

echo "Expected address: $EXPECTED_ADDRESS"

# Check if already deployed
echo "Checking if already deployed..."
EXISTING_CODE=$(cast code "$EXPECTED_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x")
if [ "$EXISTING_CODE" != "0x" ]; then
    echo ""
    echo "============================================"
    echo "  Already Deployed"
    echo "============================================"
    echo "Contract:     $CONTRACT"
    echo "Address:      $EXPECTED_ADDRESS"
    echo "Chain ID:     $CHAIN_ID"
    echo "============================================"
    exit 0
fi

# Construct payload: salt + bytecode (remove 0x prefix from bytecode)
PAYLOAD="${SALT}${BYTECODE:2}"

# Deploy
echo "Deploying via CREATE2 Proxy..."
TX_RESULT=$(cast send "$CREATE2_PROXY" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --gas-limit 5000000 \
    "$PAYLOAD" \
    --json 2>&1)

TX_HASH=$(echo "$TX_RESULT" | jq -r '.transactionHash' 2>/dev/null)

if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
    echo "Error: Deployment failed"
    echo "$TX_RESULT"
    exit 1
fi

echo "Transaction hash: $TX_HASH"

# Wait for confirmation
echo "Waiting for confirmation..."
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json 2>/dev/null)
STATUS=$(echo "$RECEIPT" | jq -r '.status')
GAS_USED=$(echo "$RECEIPT" | jq -r '.gasUsed')

if [ "$STATUS" != "0x1" ] && [ "$STATUS" != "1" ]; then
    echo "Error: Transaction failed"
    echo "$RECEIPT"
    exit 1
fi

echo "Gas used: $GAS_USED"

# Verify deployment
echo "Verifying deployment..."
DEPLOYED_CODE=$(cast code "$EXPECTED_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null)
if [ "$DEPLOYED_CODE" = "0x" ]; then
    echo "Error: Deployment verification failed - no code at expected address"
    exit 1
fi

echo ""
echo "============================================"
echo "  Deployment Successful!"
echo "============================================"
echo "Contract:     $CONTRACT"
echo "Address:      $EXPECTED_ADDRESS"
echo "Chain ID:     $CHAIN_ID"
echo "TX Hash:      $TX_HASH"
echo "Gas Used:     $GAS_USED"
echo "============================================"
echo ""
echo "To verify, run:"
echo "  ./script/verify-contract.sh $CONTRACT $EXPECTED_ADDRESS --rpc-url $RPC_URL"
