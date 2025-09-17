# DegenAVS operator (README)

This directory contains a small TypeScript operator (DegenAVS) that listens for MasterControl's
PoolRebateReady events and performs AVS actions (push gas points and mint bidder points).

Overview

The operator is intentionally small and testable. Two modes are provided:
- Full mode: operator will perform on-chain writes (pushGasPoints, batchMintPoints).
- Dry-run mode: operator only logs intended actions without sending transactions (set AVS_DRY_RUN=1).

Key files
- [`Bonded-hooks/operator/DegenAVS.ts`](Bonded-hooks/operator/DegenAVS.ts:1) - runtime event listener
- [`Bonded-hooks/operator/processor.ts`](Bonded-hooks/operator/processor.ts:1) - pure processing function used by runtime/tests
- [`Bonded-hooks/operator/matcher.ts`](Bonded-hooks/operator/matcher.ts:1) - bidder matching logic
- [`Bonded-hooks/operator/package.json`](Bonded-hooks/operator/package.json:1) - npm scripts
- [`Bonded-hooks/operator/tsconfig.json`](Bonded-hooks/operator/tsconfig.json:1) - TypeScript compile settings
- [`Bonded-hooks/operator/integration/run-full-local.sh`](Bonded-hooks/operator/integration/run-full-local.sh:1) - full local helper
- [`Bonded-hooks/script/DeployForLocal.s.sol`](Bonded-hooks/script/DeployForLocal.s.sol:1) - forge script that deploys Uniswap mocks + project stack
- [`Bonded-hooks/script/Deploy.s.sol`](Bonded-hooks/script/Deploy.s.sol:1) - project's original deploy script (used by DeployForLocal)
- [`Bonded-hooks/test/mocks/MockMasterControl.sol`](Bonded-hooks/test/mocks/MockMasterControl.sol:1) - small helper contract used in tests
- [`.github/workflows/operator-integration.yml`](.github/workflows/operator-integration.yml:1) - optional CI workflow that runs anvil + deploys + operator

Prerequisites
- Foundry (forge/cast/anvil). Install:
  curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup
- Node 18+ and npm
- jq (optional) for JSON parsing in helpers

Quick one-command local flow (recommended)
1) Ensure you have an Anvil account private key and export it:
   - Start anvil manually or let the helper start it.
   - If starting manually: anvil -p 8545  (copy account 0 private key shown in the output)
   - export ANVIL_PRIVATE_KEY="0x..."

2) Make the helper executable and run it:
   chmod +x Bonded-hooks/operator/integration/run-full-local.sh
   ./Bonded-hooks/operator/integration/run-full-local.sh

What the helper does
- Starts anvil (if not already running)
- Runs [`DeployForLocal.s.sol`](Bonded-hooks/script/DeployForLocal.s.sol:1) which:
  - deploys Uniswap v4 test manager & routers (deployFreshManagerAndRouters())
  - runs the project's [`Deploy.s.sol`](Bonded-hooks/script/Deploy.s.sol:1) so MasterControl is deployed at the required CREATE2 address
  - prints a single-line JSON with important deployed addresses (MasterControl, Settings, GasBank, BidManager, DegenPool)
- Builds the operator and starts it (writes logs to Bonded-hooks/operator/operator.log)
- Triggers a test PoolRebateReady event via cast to exercise the operator

Manual step-by-step (if you prefer control)
1) Start anvil:
   anvil -p 8545

2) Deploy manager + project contracts:
   cd Bonded-hooks
   forge script script/DeployForLocal.s.sol:DeployForLocal --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_PRIVATE_KEY> --broadcast -vvvv
   The script prints a single-line JSON (last printed line). Note the MasterControl and other addresses.

3) Build the operator:
   cd Bonded-hooks/operator
   npm ci
   npm run build

4) Start the operator:
   export RPC_URL=http://127.0.0.1:8545
   export PRIVATE_KEY=<ANVIL_PRIVATE_KEY>
   export MASTER_CONTROL_ADDRESS=<MasterControl address from step 2>
   export SETTINGS_ADDRESS=<Settings address from step 2>
   export GAS_REBATE_ADDRESS=<GasBank or GasRebate address from step 2>
   export BID_MANAGER_ADDRESS=<BidManager address from step 2>
   export DEGEN_POOL_ADDRESS=<DegenPool address from step 2>
   node dist/DegenAVS.js

5) Tail operator logs:
   tail -f Bonded-hooks/operator/operator.log

Trigger a sample PoolRebateReady event manually
- Example using cast:
  cast send --private-key <ANVIL_PRIVATE_KEY> <MASTER_CONTROL_ADDRESS> "emitPoolRebateReady(address,address,uint256,uint256,uint256)" "0x0000000000000000000000000000000000000001" "0x0000000000000000000000000000000000000002" 1 100 1000000000 --rpc-url http://127.0.0.1:8545

