# Testing and Setup — Quickstart (for new clones)

This file shows the minimal steps a developer needs after cloning the repository to run the unit/integration tests and the operator runtime locally.

Prerequisites
- Node 18+ and npm (or pnpm) installed.
- Foundry toolchain (forge/cast/anvil) for contract tests. Install:
  curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup

Repository-level install (contracts + JS helpers)
1) Install repo-level Node deps (recommended):
   cd Bonded-hooks && npm ci
   (or use pnpm: cd Bonded-hooks && pnpm install)

2) If you plan to compile and experiment with COFHE-enabled contracts, install the COFHE contracts & plugin:
   cd Bonded-hooks && npm install @fhenixprotocol/cofhe-contracts cofhe-hardhat-plugin --save-dev

Running Solidity tests (Foundry)
- Run all contract tests:
  cd Bonded-hooks && forge test
- If you need anvil locally:
  anvil -p 8545
  then run the same forge test commands or use the scripts in `script/` to deploy for local integration.

Operator (Node) setup and tests
- Operator package location:
  - main operator code: [`Bonded-hooks/operator/DegenAVS.ts`](Bonded-hooks/operator/DegenAVS.ts:1)
  - COFHE prototype operator: [`Bonded-hooks/operator/DegenAVS_COFHE.ts`](Bonded-hooks/operator/DegenAVS_COFHE.ts:1)
  - operator README: [`Bonded-hooks/operator/README.md`](Bonded-hooks/operator/README.md:1)

1) Install operator deps:
   cd Bonded-hooks/operator && npm ci

2) (Optional) If you want the real cofhejs runtime:
   cd Bonded-hooks/operator && npm install cofhejs --save

3) Build (TypeScript -> dist):
   cd Bonded-hooks/operator && npm run build

4) Run the operator (dry-run):
   cd Bonded-hooks/operator
   export RPC_URL=http://127.0.0.1:8545
   export PRIVATE_KEY=<anvil-private-key>
   node dist/DegenAVS.js

Running operator tests
- Run all operator Jest tests:
  cd Bonded-hooks/operator && npm test

- Run all tests with Jest flags:
  cd Bonded-hooks/operator && npx jest --runInBand --colors --verbose

- Run a single focused test (example):
  cd Bonded-hooks/operator && npx jest __tests__/integration_COFHE_basicCalls.test.ts --runInBand --verbose

Quick local integration (helper)
- There's a helper to deploy and run the operator locally:
  chmod +x Bonded-hooks/operator/integration/run-full-local.sh
  ./Bonded-hooks/operator/integration/run-full-local.sh
  This script attempts to start anvil, deploy the system using the repo's `script/DeployForLocal.s.sol`, and start the operator.

Notes and troubleshooting
- If node_modules were already tracked before updating `.gitignore`, remove them from git index:
  git rm -r --cached node_modules operator/node_modules react-frontend/node_modules
  git add .gitignore && git commit -m "Ignore node_modules and pnpm lockfile"

- If Jest complains about missing `cofhejs` types, add a minimal ambient declaration:
  // Bonded-hooks/operator/types/cofhejs.d.ts
  declare module "cofhejs" { const cofhejs: any; export default cofhejs; }

- The COFHE prototype files:
  - Solidity prototype: [`Bonded-hooks/src/BidManagerCofhe.sol`](Bonded-hooks/src/BidManagerCofhe.sol:1)
  - Operator prototype: [`Bonded-hooks/operator/DegenAVS_COFHE.ts`](Bonded-hooks/operator/DegenAVS_COFHE.ts:1)
  Tests for these prototypes are in:
  - [`Bonded-hooks/operator/__tests__/DegenAVS_COFHE.test.ts`](Bonded-hooks/operator/__tests__/DegenAVS_COFHE.test.ts:1)
  - [`Bonded-hooks/operator/__tests__/integration_DegenAVS_COFHE.test.ts`](Bonded-hooks/operator/__tests__/integration_DegenAVS_COFHE.test.ts:1)
  - [`Bonded-hooks/operator/__tests__/integration_COFHE_basicCalls.test.ts`](Bonded-hooks/operator/__tests__/integration_COFHE_basicCalls.test.ts:1)

Best practices
- Use `--runInBand` for Jest when running in constrained CI or WSL environments to avoid flaky parallel issues.
- Keep operator env vars in a `.env` for local testing (do not commit secrets).

