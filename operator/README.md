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


## Shaker AVS (automated Shaker rounds & PrizeBox awarding)

A second AVS is included to automate Shaker rounds and PrizeBox awarding. It runs as a small runtime process that:
- periodically starts a Shaker round on a selected pool,
- waits for the round deadline (plus a small buffer),
- calls `finalizeRound(roundId, boxIds, seed)` to distribute prizeBox funds,
- queries `PrizeBox` balances and deterministically selects a box to award,
- calls `awardWinnerBox(roundId, boxId)`.

Key operator files for the Shaker AVS
- Runtime AVS: [`Bonded-hooks/operator/ShakerAVS.ts:1`](Bonded-hooks/operator/ShakerAVS.ts:1)
- Pure helpers: [`Bonded-hooks/operator/shakerProcessor.ts:1`](Bonded-hooks/operator/shakerProcessor.ts:1)
- Tests: [`Bonded-hooks/operator/__tests__/shakerProcessor.test.ts:1`](Bonded-hooks/operator/__tests__/shakerProcessor.test.ts:1)

Environment variables used by the Shaker AVS
- `RPC_URL` (required) — JSON-RPC endpoint (e.g. http://127.0.0.1:8545)
- `PRIVATE_KEY` (required) — private key of the AVS account (must be authorized in Shaker via `setAVS`)
- `SHAKER_ADDRESS` (required) — deployed Shaker contract address
- `PRIZEBOX_ADDRESS` (optional but recommended) — deployed PrizeBox contract address
- `CANDIDATE_POOLS` (required for auto-start) — comma-separated pool ids (e.g. `1,2,3`)
- `CANDIDATE_BOXES` (required for finalize/award) — comma-separated box ids (e.g. `1,2,3,4`)
- `MIN_INTERVAL_SECONDS` (default 30) — minimum wait between starting rounds
- `MAX_INTERVAL_SECONDS` (default 120) — maximum wait between starting rounds
- `BOXES_PER_ROUND` (default 1) — how many boxIds to include in finalizeRound per round
- `FINALIZE_BUFFER_SECONDS` (default 5) — extra seconds to wait beyond round deadline before finalizing
- `DRY_RUN` (set to `1`) — when present, the runtime will not send on-chain transactions and will only log actions

Example quick dry-run
1) Export env vars (example):
   ```
   export RPC_URL=http://127.0.0.1:8545
   export PRIVATE_KEY=<ANVIL_PRIVATE_KEY>
   export SHAKER_ADDRESS=<Shaker address>
   export PRIZEBOX_ADDRESS=<PrizeBox address>
   export CANDIDATE_POOLS=1,2
   export CANDIDATE_BOXES=1,2,3
   export MIN_INTERVAL_SECONDS=30
   export MAX_INTERVAL_SECONDS=60
   export BOXES_PER_ROUND=1
   export FINALIZE_BUFFER_SECONDS=5
   export DRY_RUN=1
   ```

2) Install/build and run (operator dir):
   - npm ci
   - npm run build
   - node dist/ShakerAVS.js

Notes and recommendations
- Ensure the AVS account (PRIVATE_KEY) is authorized in the on-chain Shaker contract via `setAVS(...)`.
- The Shaker AVS uses deterministic seed-based selection helpers in [`Bonded-hooks/operator/shakerProcessor.ts:1`](Bonded-hooks/operator/shakerProcessor.ts:1) so behavior can be reproduced for testing if a fixed seed is provided.
- For integration testing, run the repository's `integration/run-full-local.sh` helper which deploys the system with anvil and can be used alongside the operator scripts.
- Add or tune candidate pools/boxes and intervals to control frequency and scope of automated rounds.

## COFHE-enabled Degen AVS (prototype)

A COFHE-enabled variant of the Degen AVS has been added as a prototype to demonstrate how encrypted bids can be read by an off-chain AVS and matched without exposing plaintext on-chain.

Key new files (cloned; original code unchanged)
- [`Bonded-hooks/operator/DegenAVS_COFHE.ts`](Bonded-hooks/operator/DegenAVS_COFHE.ts:1) — TypeScript AVS operator adapted for COFHE:
  - Dynamically requires `cofhejs` and `ethers` so Jest mocks work.
  - Exports a pure helper `matchBiddersFromInfos(...)` for unit testing.
  - Implements `readEncryptedBidPlain(...)` to unseal ciphertexts (via `cofhejs.unseal`) and `handlePoolRebateReady(...)` which performs matching and (optionally) calls settlement.
- [`Bonded-hooks/src/BidManagerCofhe.sol`](Bonded-hooks/src/BidManagerCofhe.sol:1) — Solidity prototype showing how to store encrypted bid fields using COFHE types (`euint*`, `eaddress`) and expose `getBidEncrypted(...)`.
- Tests:
  - Unit tests for the pure matcher: [`Bonded-hooks/operator/__tests__/DegenAVS_COFHE.test.ts`](Bonded-hooks/operator/__tests__/DegenAVS_COFHE.test.ts:1)
  - Integration-style tests that mock both cofhejs and ethers: [`Bonded-hooks/operator/__tests__/integration_DegenAVS_COFHE.test.ts`](Bonded-hooks/operator/__tests__/integration_DegenAVS_COFHE.test.ts:1)
  - Jest mock for cofhejs: [`Bonded-hooks/operator/__mocks__/cofhejs.js`](Bonded-hooks/operator/__mocks__/cofhejs.js:1)

How it works (local/dry-run)
- The operator reads encrypted bid ciphertexts from the COFHE BidManager (`getBidEncrypted`) and uses `cofhejs.unseal(...)` (or your runtime) to obtain plaintext values off-chain.
- Matching proceeds the same as the original AVS, then:
  - In dry-run mode the operator logs planned point mints and settlement payloads.
  - In LIVE mode (set `LIVE=true`) the operator will call `finalizeEpochConsumeBids(...)` on the COFHE BidManager (the contract still expects plain consumedAmounts in this prototype).

Environment variables (COFHE prototype)
- `RPC_URL` — JSON-RPC endpoint (optional for dry-run unit tests; required for LIVE on-chain calls)
- `PRIVATE_KEY` — AVS account private key (optional for dry-run)
- `BID_MANAGER_COFHE_ADDRESS` — address of the COFHE BidManager contract (required for LIVE)
- `CANDIDATE_BIDDERS` — comma-separated list of bidder addresses the AVS will consider (plain addresses)
- `LIVE` — set to `true` to perform on-chain finalize; default is dry-run
- `POINTS_PER_WEI` — optional override for points conversion (defaults to 1e12)

Running tests
- Unit tests (matching logic):
  - cd Bonded-hooks/operator && npx jest __tests__/DegenAVS_COFHE.test.ts --runInBand --verbose
- Integration tests (mock cofhejs + mock ethers):
  - cd Bonded-hooks/operator && npx jest __tests__/integration_DegenAVS_COFHE.test.ts --runInBand --verbose

Notes and recommendations
- The Solidity prototype imports COFHE contracts (`@fhenixprotocol/cofhe-contracts`). Install the package in `Bonded-hooks` if you plan to compile the contract:
  - cd Bonded-hooks && npm install @fhenixprotocol/cofhe-contracts cofhe-hardhat-plugin --save-dev
- The operator package can use the real `cofhejs` runtime once installed:
  - cd Bonded-hooks/operator && npm install cofhejs --save
- Tests included use Jest module mocking; the operator loads cofhejs/ethers dynamically so tests can fully mock those modules.
- These files are prototypes for experimentation and do not change the original AVS or BidManager implementations.
