# Bonded Hooks — Uniswap v4 Hook Composition and Funding Infrastructure

Bonded Hooks is experimental infrastructure for composing, funding, and operating Uniswap v4 hook behavior. It began as a UHI6 Hookathon project and won a $1,000 award. The project is now being revived with a focus on repo cleanup, safer hook composition, deployment repair, documentation, and grant/audit readiness.

## One-Line Summary

Bonded Hooks helps pool creators assemble reusable hook behaviors from approved command modules while creating incentive rails for hook developers, bonders, LPs, and traders.

## Current Revival Status

Technical baseline:

- `forge test --skip script -vvv` passes with **117 Solidity tests**.
- `cd operator && npm run build` passes.
- `cd operator && npm test` passes with **21 TypeScript/Jest tests**.
- Full `forge build` is currently blocked by deployment-script/compiler stack-depth issues.
- The project is experimental, unaudited, and **not mainnet-ready**.

Current focus:

1. Repository hardening and CI.
2. Deployment script repair.
3. Safer hook composition MVP.
4. Bonding/reward accounting MVP.
5. Testnet or Unichain demo.
6. Audit-readiness and Uniswap Foundation Security Fund preparation.

See:

- [GRANT_PLAN.md](GRANT_PLAN.md)
- [ROADMAP.md](ROADMAP.md)
- [THREAT_MODEL.md](THREAT_MODEL.md)

## What Bonded Hooks Does

Bonded Hooks explores a modular model for Uniswap v4 hooks:

- **Pool admins** compose behavior from approved command blocks instead of writing custom Solidity.
- **Hook developers** publish focused command modules.
- **Bonders** support hook development and may earn a share of future fees.
- **Traders** can receive points, rewards, or gas rebates when pools enable those flows.
- **Operators / AVS-style services** can process off-chain reward or rebate logic and push results on-chain.

The long-term vision is a marketplace and lifecycle layer for reusable Uniswap v4 hook behavior. The near-term MVP is narrower: safe hook composition, bonding/reward accounting, and a reproducible demo.

## Core Components

| Component | Purpose |
|---|---|
| [`MasterControl`](src/MasterControl.sol) | Central Uniswap v4 hook dispatcher and command manager |
| [`PointsCommand`](src/PointsCommand.sol) | Example command module for points/reward behavior |
| [`Bonding`](src/Bonding.sol) | Bond funding and rewards-per-share accounting |
| [`DegenPool`](src/DegenPool.sol) | Points-based reward distribution |
| [`GasBank`](src/GasBank.sol) | ETH vault for gas rebate funding |
| [`GasRebateManager`](src/GasRebateManager.sol) | Epoch-based rebate accounting |
| [`ShareSplitter`](src/ShareSplitter.sol) | Fee/reward splitting rail |
| [`FeeCollector`](src/FeeCollector.sol) | Platform fee vault placeholder |
| [`MemoryCard`](src/MemoryCard.sol) | Per-caller key/value and ROM-style storage |
| [`PoolLaunchPad`](src/PoolLaunchPad.sol) | Pool/token launch helper |
| [`AccessControl`](src/AccessControl.sol) | Central role and pool-admin registry |
| [`BidManager`](src/BidManager.sol) | Bid/epoch support for operator workflows |
| [`BidManagerCofhe`](src/BidManagerCofhe.sol) | COFHE/Fhenix encrypted bid prototype |

## Operator Components

The TypeScript operator code lives in [`operator/`](operator/).

Key files:

- [`operator/DegenAVS.ts`](operator/DegenAVS.ts)
- [`operator/DegenAVS_COFHE.ts`](operator/DegenAVS_COFHE.ts)
- [`operator/ShakerAVS.ts`](operator/ShakerAVS.ts)
- [`operator/processor.ts`](operator/processor.ts)
- [`operator/shakerProcessor.ts`](operator/shakerProcessor.ts)
- [`operator/README.md`](operator/README.md)

The operator code is currently best understood as an AVS-style/off-chain automation prototype, not a production decentralized operator network.

## How It Works

### 1. Hook composition

`MasterControl` receives Uniswap v4 hook callbacks and dispatches configured command modules for a pool. Commands can represent small behaviors such as minting points, forwarding fees, or integrating with reward systems.

### 2. Blocks and provenance

Commands can be grouped into approved blocks. Blocks may include immutability and conflict-group rules so pool admins can apply curated behavior while preserving provenance and safety constraints.

### 3. Bonding and incentives

The bonding system allows supporters to back hook work. The current prototype explores non-withdrawable bonded principal with rewards-per-share accounting for future fee distribution.

### 4. Rewards and rebates

`DegenPool`, `GasBank`, `GasRebateManager`, and the operator scripts provide rails for points, rewards, and gas rebate accounting.

## Quickstart

Install Foundry and Node.js, then run:

```bash
forge test --skip script -vvv
```

Operator:

```bash
cd operator
npm install
npm run build
npm test
```

Known current issue:

```bash
forge build
```

May fail because deployment scripts currently trigger compiler stack-depth issues. Repairing or isolating those scripts is part of the current revival roadmap.

## Security Status

This project is experimental research software.

Do not use on mainnet.

Known areas requiring review:

- Delegatecall-based command execution.
- Command approval and revocation lifecycle.
- Centralized/off-chain operator trust.
- Bonding principal and authorized withdrawal assumptions.
- Admin/emergency withdrawal powers.
- Gas rebate abuse and Sybil resistance.
- `tx.origin` limitations in router/account-abstraction contexts.

See [THREAT_MODEL.md](THREAT_MODEL.md).

## Grant Plan

Bonded Hooks is seeking milestone-based funding to turn the dormant award-winning prototype into a clean, testable, documented, deployable Uniswap v4 hook infrastructure MVP.

Requested grant plan:

- Repository hardening, CI, and deployment repair.
- Safe hook composition MVP.
- Bonding and reward accounting MVP.
- Testnet / Unichain demo package.
- Audit-readiness and UFSF submission package.

See [GRANT_PLAN.md](GRANT_PLAN.md).

## License and Disclaimer

This repository is experimental, unaudited research software. It is not intended for production or mainnet use without substantial security review and formal audits.
