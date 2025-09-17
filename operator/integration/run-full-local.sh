 #!/usr/bin/env bash
# Convenience end-to-end local helper:
# - starts Anvil (if not already running)
# - deploys Uniswap mocks + project contracts (DeployForLocal)
# - builds and starts the DegenAVS operator
# - triggers a PoolRebateReady event on MasterControl to exercise the operator
#
# Requirements:
# - foundryup / anvil / forge / cast installed and on PATH (https://book.getfoundry.sh/)
# - jq (for parsing JSON) OR Node.js (node is used as fallback)
# - npm (for operator build)
#
# Usage:
#   export ANVIL_PRIVATE_KEY="<private-key-for-anvil-account-0>"
#   chmod +x Bonded-hooks/operator/integration/run-full-local.sh
#   ./Bonded-hooks/operator/integration/run-full-local.sh
#
# Notes:
# - The script will use ANVIL_PRIVATE_KEY for forge/cast calls. If not set it will exit.
# - The script prints operator logs to Bonded-hooks/operator/operator.log

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ANVIL_RPC="http://127.0.0.1:8545"
ANVIL_PORT=8545
ANVIL_PID_FILE="$ROOT_DIR/operator/anvil.pid"
DEPLOY_OUTPUT="/tmp/forge-deploy-output.txt"
OPERATOR_LOG="$ROOT_DIR/operator/operator.log"

if [ -z "${ANVIL_PRIVATE_KEY:-}" ]; then
  echo "Please export ANVIL_PRIVATE_KEY (private key for anvil account 0)."
  exit 1
fi

# Ensure foundry tools exist
if ! command -v anvil >/dev/null 2>&1; then
  echo "anvil not found. Please install Foundry (foundryup)."
  echo "https://book.getfoundry.sh/getting-started/installation"
  exit 1
fi
if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Please install Foundry (foundryup)."
  exit 1
fi
if ! command -v cast >/dev/null 2>&1; then
  echo "cast not found. Please install Foundry (foundryup)."
  exit 1
fi

# Start anvil if not running
if [ -f "$ANVIL_PID_FILE" ]; then
  PID=$(cat "$ANVIL_PID_FILE")
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "Anvil already running (PID $PID)"
  else
    rm -f "$ANVIL_PID_FILE"
  fi
fi

if ! nc -z 127.0.0.1 $ANVIL_PORT >/dev/null 2>&1; then
  echo "Starting anvil on $ANVIL_RPC (with raised block gas limit)..."
  # Increase Anvil's block gas limit so large multi-contract deploy scripts succeed locally.
  nohup anvil -p $ANVIL_PORT --block-gas-limit 120000000 > "$ROOT_DIR/anvil.log" 2>&1 &
  ANVIL_PID=$!
  echo $ANVIL_PID > "$ANVIL_PID_FILE"
  sleep 1
  echo "Anvil started (PID $ANVIL_PID). Logs: $ROOT_DIR/anvil.log"
else
  echo "Anvil appears to be listening on $ANVIL_RPC"
  echo "Restarting anvil to ensure fresh nonce state (clears pending nonces)..."
  # Try to stop the previous anvil process cleanly if PID file exists, otherwise pkill.
  if [ -f "$ANVIL_PID_FILE" ]; then
    OLD_PID=$(cat "$ANVIL_PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && ps -p "$OLD_PID" > /dev/null 2>&1; then
      kill "$OLD_PID" || true
      sleep 1
    fi
    rm -f "$ANVIL_PID_FILE"
  else
    pkill -f anvil || true
  fi
  # Start a fresh anvil to reset nonces and state
  nohup anvil -p $ANVIL_PORT --block-gas-limit 120000000 > "$ROOT_DIR/anvil.log" 2>&1 &
  ANVIL_PID=$!
  echo $ANVIL_PID > "$ANVIL_PID_FILE"
  sleep 1
  echo "Anvil restarted (PID $ANVIL_PID). Logs: $ROOT_DIR/anvil.log"
fi

# --------------- New staged deploy flow ---------------
cd "$ROOT_DIR"

echo "Step 1: Deploy Uniswap v4 mocks (manager + routers)..."
forge script script/DeployUniswapMocks.s.sol:DeployUniswapMocks --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv | tee /tmp/uniswap-mocks.txt
UNISWAP_JSON=$(grep -o '{.*' /tmp/uniswap-mocks.txt | sed -n '$p' || true)
if [ -z "$UNISWAP_JSON" ]; then
  echo "Failed to extract JSON from /tmp/uniswap-mocks.txt; printing tail for debugging:"
  tail -n 200 /tmp/uniswap-mocks.txt
  exit 1
fi
echo "$UNISWAP_JSON" > /tmp/uniswap-mocks.json

if command -v jq >/dev/null 2>&1; then
  MANAGER_ADDR=$(jq -r '.PoolManager' /tmp/uniswap-mocks.json)
else
  MANAGER_ADDR=$(node -e "console.log(JSON.parse(process.argv[1]).PoolManager)" "$UNISWAP_JSON")
fi
echo "Manager deployed at: $MANAGER_ADDR"
export MANAGER="$MANAGER_ADDR"

echo "Step 2: Deploy core contracts (AccessControl, PoolLaunchPad, MasterControl) using MANAGER..."
forge script script/DeployCore.s.sol:DeployCore --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv | tee /tmp/core-deploy.txt
CORE_JSON=$(grep -o '{.*' /tmp/core-deploy.txt | sed -n '$p' || true)
if [ -z "$CORE_JSON" ]; then
  echo "Failed to extract JSON from /tmp/core-deploy.txt; printing tail for debugging:"
  tail -n 200 /tmp/core-deploy.txt
  exit 1
fi
echo "$CORE_JSON" > /tmp/core-deploy.json

if command -v jq >/dev/null 2>&1; then
  ACCESS_CONTROL_ADDRESS=$(jq -r '.AccessControl' /tmp/core-deploy.json)
  POOL_LAUNCHPAD_ADDRESS=$(jq -r '.PoolLaunchPad' /tmp/core-deploy.json)
  MASTER_CONTROL_ADDRESS=$(jq -r '.MasterControl' /tmp/core-deploy.json)
else
  ACCESS_CONTROL_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).AccessControl)" "$CORE_JSON")
  POOL_LAUNCHPAD_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).PoolLaunchPad)" "$CORE_JSON")
  MASTER_CONTROL_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).MasterControl)" "$CORE_JSON")
fi

echo "Core deployed: MANAGER=$MANAGER_ADDR, ACCESS_CONTROL=$ACCESS_CONTROL_ADDRESS, POOL_LAUNCHPAD=$POOL_LAUNCHPAD_ADDRESS, MASTER_CONTROL=$MASTER_CONTROL_ADDRESS"
export ACCESS_CONTROL="$ACCESS_CONTROL_ADDRESS"
export POOL_LAUNCHPAD="$POOL_LAUNCHPAD_ADDRESS"
export MASTER_CONTROL="$MASTER_CONTROL_ADDRESS"

echo "Step 3: Deploy platform contracts (split into two batches to avoid big single transactions)..."
# Deploy main platform batch
forge script script/DeployPlatform.s.sol:DeployPlatform --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv | tee /tmp/platform-deploy.txt
PLAT_JSON=$(grep -o '{.*' /tmp/platform-deploy.txt | sed -n '$p' || true)
if [ -z "$PLAT_JSON" ]; then
  echo "Failed to extract JSON from /tmp/platform-deploy.txt; printing tail for debugging:"
  tail -n 200 /tmp/platform-deploy.txt
  exit 1
fi
echo "$PLAT_JSON" > /tmp/platform-deploy.json

# Deploy final small batch (heavy or separate contracts)
forge script script/DeployPlatformFinish.s.sol:DeployPlatformFinish --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv | tee /tmp/platform-finish.txt
PLAT_FIN_JSON=$(grep -o '{.*' /tmp/platform-finish.txt | sed -n '$p' || true)
if [ -z "$PLAT_FIN_JSON" ]; then
  echo "Failed to extract JSON from /tmp/platform-finish.txt; printing tail for debugging:"
  tail -n 200 /tmp/platform-finish.txt
  exit 1
fi
echo "$PLAT_FIN_JSON" > /tmp/platform-finish.json

# Merge core + platform + finish JSON into one canonical JSON
if command -v jq >/dev/null 2>&1; then
  FULL_JSON=$(jq -s '.[0] + .[1] + .[2]' /tmp/core-deploy.json /tmp/platform-deploy.json /tmp/platform-finish.json)
else
  FULL_JSON=$(node -e "const a=JSON.parse(process.argv[1]); const b=JSON.parse(process.argv[2]); const c=JSON.parse(process.argv[3]); console.log(JSON.stringify(Object.assign({}, a, b, c)))" "$CORE_JSON" "$PLAT_JSON" "$PLAT_FIN_JSON")
fi

echo "$FULL_JSON" > /tmp/full-deploy.json

# Use jq if available, otherwise fall back to node for parsing JSON
if command -v jq >/dev/null 2>&1; then
  MANAGER_ADDR=$(jq -r '.PoolManager' /tmp/full-deploy.json)
  ACCESS_CONTROL_ADDRESS=$(jq -r '.AccessControl' /tmp/full-deploy.json)
  POOL_LAUNCHPAD_ADDRESS=$(jq -r '.PoolLaunchPad' /tmp/full-deploy.json)
  MASTER_CONTROL_ADDRESS=$(jq -r '.MasterControl' /tmp/full-deploy.json)
  FEE_COLLECTOR_ADDRESS=$(jq -r '.FeeCollector' /tmp/full-deploy.json)
  GAS_BANK_ADDRESS=$(jq -r '.GasBank' /tmp/full-deploy.json)
  DEGEN_POOL_ADDRESS=$(jq -r '.DegenPool' /tmp/full-deploy.json)
  SETTINGS_ADDRESS=$(jq -r '.Settings' /tmp/full-deploy.json)
  SHARE_SPLITTER_ADDRESS=$(jq -r '.ShareSplitter' /tmp/full-deploy.json)
  BONDING_ADDRESS=$(jq -r '.Bonding' /tmp/full-deploy.json)
  PRIZEBOX_ADDRESS=$(jq -r '.PrizeBox' /tmp/full-deploy.json)
  SHAKER_ADDRESS=$(jq -r '.Shaker' /tmp/full-deploy.json)
  POINTS_COMMAND_ADDRESS=$(jq -r '.PointsCommand' /tmp/full-deploy.json)
  BID_MANAGER_ADDRESS=$(jq -r '.BidManager' /tmp/full-deploy.json)
else
  MANAGER_ADDR=$(node -e "console.log(JSON.parse(process.argv[1]).PoolManager)" "$FULL_JSON")
  ACCESS_CONTROL_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).AccessControl)" "$FULL_JSON")
  POOL_LAUNCHPAD_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).PoolLaunchPad)" "$FULL_JSON")
  MASTER_CONTROL_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).MasterControl)" "$FULL_JSON")
  FEE_COLLECTOR_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).FeeCollector)" "$FULL_JSON")
  GAS_BANK_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).GasBank)" "$FULL_JSON")
  DEGEN_POOL_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).DegenPool)" "$FULL_JSON")
  SETTINGS_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).Settings)" "$FULL_JSON")
  SHARE_SPLITTER_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).ShareSplitter)" "$FULL_JSON")
  BONDING_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).Bonding)" "$FULL_JSON")
  PRIZEBOX_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).PrizeBox)" "$FULL_JSON")
  SHAKER_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).Shaker)" "$FULL_JSON")
  POINTS_COMMAND_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).PointsCommand)" "$FULL_JSON")
  BID_MANAGER_ADDRESS=$(node -e "console.log(JSON.parse(process.argv[1]).BidManager)" "$FULL_JSON")
fi

echo "Deployed addresses (parsed):"
echo "  MANAGER_ADDR=$MANAGER_ADDR"
echo "  ACCESS_CONTROL_ADDRESS=$ACCESS_CONTROL_ADDRESS"
echo "  POOL_LAUNCHPAD_ADDRESS=$POOL_LAUNCHPAD_ADDRESS"
echo "  MASTER_CONTROL_ADDRESS=$MASTER_CONTROL_ADDRESS"
echo "  FEE_COLLECTOR_ADDRESS=$FEE_COLLECTOR_ADDRESS"
echo "  GAS_BANK_ADDRESS=$GAS_BANK_ADDRESS"
echo "  DEGEN_POOL_ADDRESS=$DEGEN_POOL_ADDRESS"
echo "  SETTINGS_ADDRESS=$SETTINGS_ADDRESS"
echo "  SHARE_SPLITTER_ADDRESS=$SHARE_SPLITTER_ADDRESS"
echo "  BONDING_ADDRESS=$BONDING_ADDRESS"
echo "  PRIZEBOX_ADDRESS=$PRIZEBOX_ADDRESS"
echo "  SHAKER_ADDRESS=$SHAKER_ADDRESS"
echo "  POINTS_COMMAND_ADDRESS=$POINTS_COMMAND_ADDRESS"
echo "  BID_MANAGER_ADDRESS=$BID_MANAGER_ADDRESS"

# Export canonical variables for downstream steps
export MANAGER="$MANAGER_ADDR"
DEPLOY_JSON="$(cat /tmp/full-deploy.json)"

echo "Deployed addresses:"
echo "  MASTER_CONTROL_ADDRESS=$MASTER_CONTROL_ADDRESS"
echo "  SETTINGS_ADDRESS=$SETTINGS_ADDRESS"
echo "  GAS_BANK_ADDRESS=$GAS_BANK_ADDRESS"
echo "  BID_MANAGER_ADDRESS=$BID_MANAGER_ADDRESS"
echo "  DEGEN_POOL_ADDRESS=$DEGEN_POOL_ADDRESS"

# extract addresses for next stages (already parsed above; echo for clarity)
echo "Core parsed addresses present in /tmp/core-deploy.json"

echo "Core deployed: MasterControl=$MASTER_CONTROL_ADDRESS, AccessControl=$ACCESS_CONTROL_ADDRESS, PoolLaunchPad=$POOL_LAUNCHPAD_ADDRESS"

# save master control address for operator (keep original aside)
export MASTER_CONTROL_ADDRESS_ORIG="$MASTER_CONTROL_ADDRESS"
# Use the real MasterControl for operator runs; operator will listen for real afterSwap -> PoolRebateReady events.
export MASTER_CONTROL_ADDRESS="$MASTER_CONTROL_ADDRESS_ORIG"

# Build and start operator
# Optional: run granular seed scripts to create pools, bids, and bonds (set RUN_SETUP_DEFAULTS=1 to enable)
if [ "${RUN_SETUP_DEFAULTS:-0}" = "1" ]; then
  echo "Step 4a: Seeding pools..."
  forge script script/SeedPools.s.sol:SeedPools --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv --via-ir | tee /tmp/seed-pools.txt
  echo "Pools seeded. Output -> /tmp/seed-pools.txt"

  echo "Step 4b: Seeding bids..."
  forge script script/SeedBids.s.sol:SeedBids --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv --via-ir | tee /tmp/seed-bids.txt
  echo "Bids seeded. Output -> /tmp/seed-bids.txt"

  echo "Step 4c: Seeding bonds..."
  forge script script/SeedBonds.s.sol:SeedBonds --rpc-url $ANVIL_RPC --private-key "$ANVIL_PRIVATE_KEY" --broadcast -vvvv --via-ir | tee /tmp/seed-bonds.txt
  echo "Bonds seeded. Output -> /tmp/seed-bonds.txt"
else
  echo "Skipping seeded setup (set RUN_SETUP_DEFAULTS=1 to enable)"
fi

cd "$ROOT_DIR/operator"
npm ci
npm run build

# Start operator in background and capture logs
echo "Starting operator (logs -> $OPERATOR_LOG)"
nohup node dist/DegenAVS.js > "$OPERATOR_LOG" 2>&1 &
OP_PID=$!
echo $OP_PID > "$ROOT_DIR/operator/operator.pid"
sleep 2
echo "Operator started (PID $OP_PID). Streaming logs (press Ctrl-C to stop)..."

# Ensure we stop operator and anvil when the user interrupts (Ctrl-C) or the script receives TERM.
trap 'echo "Stopping operator (PID $OP_PID) and anvil..."; kill "$OP_PID" || true; pkill -f anvil || true; exit 0' INT TERM

# Stream the operator logs to the terminal so this script keeps running while you work.
tail -f "$OPERATOR_LOG"