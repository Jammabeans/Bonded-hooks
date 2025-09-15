#!/usr/bin/env bash
# Convenience helper to run a local anvil + (manual) deploy + operator workflow.
# Usage:
#   1) Ensure PRIVATE_KEY and other env vars are exported, OR edit the script.
#   2) ./run-integration.sh
#
# The script will:
# - attempt to install Foundry (foundryup) if missing
# - start anvil on 127.0.0.1:8545 in the background
# - print suggested forge commands to deploy contracts
# - print how to start the operator against the local RPC

set -e

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "Root: $ROOT_DIR"

# Install foundry if not present
if ! command -v forge >/dev/null 2>&1; then
  echo "Foundry (forge/anvil) not found. Installing foundryup..."
  curl -L https://foundry.paradigm.xyz | bash
  source ~/.bashrc || true
  foundryup
fi

if ! command -v anvil >/dev/null 2>&1; then
  echo "anvil still not available after foundryup. Please ensure foundryup completed successfully."
  exit 1
fi

# Start anvil in the background
ANVIL_PID_FILE="./anvil.pid"
if [ -f "$ANVIL_PID_FILE" ]; then
  PID=$(cat "$ANVIL_PID_FILE")
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "Anvil already running (PID $PID)"
  else
    echo "Stale PID file found. Removing."
    rm -f "$ANVIL_PID_FILE"
  fi
fi

echo "Starting anvil on http://127.0.0.1:8545 ..."
nohup anvil -p 8545 > anvil.log 2>&1 &
ANVIL_PID=$!
echo $ANVIL_PID > "$ANVIL_PID_FILE"
sleep 1
echo "Anvil started (PID $ANVIL_PID). Logs: anvil.log"

# Next steps (manual)
cat <<EOF

Next steps (manual):
1) Deploy contracts to the local anvil node. Example (from repository root - Bonded-hooks):
   cd $ROOT_DIR
   # Use a forge script or your deploy helper. Example pattern:
   forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast -vvvv

   If your repo has a specific deploy script, run that. Alternatively you can run:
   forge test -vv

2) After deploying, set the following environment variables for the operator:
   export RPC_URL=http://127.0.0.1:8545
   export PRIVATE_KEY=<operator-private-key>        # use a key present in anvil's accounts
   export MASTER_CONTROL_ADDRESS=<deployed-master-control-address>
   export SETTINGS_ADDRESS=<deployed-settings-address>
   export GAS_REBATE_ADDRESS=<deployed-gas-rebate-address>
   export BID_MANAGER_ADDRESS=<deployed-bid-manager-address>
   export DEGEN_POOL_ADDRESS=<deployed-degen-pool-address>
   export CANDIDATE_BIDDERS="0xabc...,0xdef..."

3) Start the operator (from this directory):
   cd $ROOT_DIR/operator
   # Run with ts-node:
   npx ts-node DegenAVS.ts
   # or compile & run:
   npm run build && node dist/DegenAVS.js

Notes:
- The helper intentionally does not attempt to broadcast transactions without a valid PRIVATE_KEY.
- Tweak the deploy invocation to match your project's deploy scripts.
- When finished, stop anvil:
   kill $ANVIL_PID
   rm -f $ANVIL_PID_FILE

EOF