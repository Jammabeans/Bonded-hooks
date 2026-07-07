# Bonded Hooks — Uniswap Foundation Grant Plan

## One-Line Summary
Bonded Hooks is modular infrastructure for Uniswap v4 hook composition, funding, and lifecycle management, designed to help pool creators safely assemble reusable hook behaviors while creating transparent incentive rails for developers, LPs, and traders.

## Project Background
Bonded Hooks began as a UHI6 Hookathon project and won a $1,000 award. The prototype has been dormant for a period, but the codebase already contains substantial Solidity and TypeScript work:
- Uniswap v4-oriented hook control architecture
- modular command/block model
- bonding and fee/reward accounting primitives
- DegenPool points/reward flows
- gas rebate manager
- pool launch tooling
- TypeScript operator/AVS-style processors
- COFHE/Fhenix experimentation for encrypted bid flows

This grant would fund a focused revival: cleanup, stabilization, narrowing scope, deployment repair, documentation, and an audit-ready MVP.

## Current Technical Baseline
As of the revival pass:
- `forge test --skip script -vvv` passes with **117 Solidity tests**
- `cd operator && npm run build` passes
- `cd operator && npm test` passes with **21 TypeScript/Jest tests**
- The full `forge build` is currently blocked by deployment-script/compiler stack-depth issues
- Generated artifacts have been removed from git tracking and ignore rules have been added

## Problem
Uniswap v4 hooks are powerful, but they are still difficult for most pool creators to safely design, compose, fund, and operate. Today, each serious hook tends to be a custom engineering effort with its own security assumptions, lifecycle management, reward logic, and operational tooling.

This creates friction for:
- pool creators who want hook-enabled pools without writing custom Solidity
- hook developers who want reusable distribution paths
- liquidity providers who need clear incentive and risk models
- traders who may benefit from rebates, points, or other hook-level programs
- reviewers/auditors who need standardized architecture and documentation

## Proposed Solution
Bonded Hooks provides a modular hook-control layer where approved command modules can be composed into pool-level behavior. The long-term vision is a marketplace and lifecycle system for reusable hook blocks. The grant-funded MVP will focus on a narrower, safer foundation:
- hardened `MasterControl` / command approval path
- one or two audited-style example command modules
- bonding and reward accounting MVP
- operator-assisted reward/rebate demo
- reproducible testnet or Unichain deployment path
- security documentation and audit-readiness package

## Why This Benefits Uniswap
Bonded Hooks can help the Uniswap ecosystem by:
- increasing practical adoption of v4 hooks
- reducing duplicated work for hook builders
- providing reusable examples for hook composition and incentive design
- creating a clearer path from hackathon prototypes to deployable hook products
- producing open-source docs, tests, and threat models useful to other builders

## Grant Request
Total requested funding: **$50,000**

The grant is structured as five milestones. Each milestone produces concrete, reviewable deliverables.

## Milestone 1 — Repository Hardening, CI, and Deployment Repair
**Request:** $7,500
**Target duration:** 2 weeks

### Deliverables
- Remove generated/runtime artifacts from git tracking
- Confirm clean clone setup instructions
- Add or repair CI for:
  - Foundry contract tests
  - TypeScript operator build/tests
- Repair deployment scripts or isolate them behind a documented profile
- Resolve current full-build blocker or document a clean CI path while script repair is underway
- Update README with current project status and revival roadmap

### Acceptance Criteria
- Fresh clone can install dependencies and run documented commands
- Core Solidity tests pass in CI
- Operator build/tests pass in CI
- Full build/deployment-script issue is either fixed or clearly isolated with a tracked follow-up

## Milestone 2 — Safe Hook Composition MVP
**Request:** $12,500
**Target duration:** 3 weeks

### Deliverables
- Harden `MasterControl` command approval and execution flows
- Narrow MVP command model to a safer set of approved examples
- Document command lifecycle:
  - approval
  - block creation
  - pool admin configuration
  - execution
  - removal/revocation limitations
- Add tests for unauthorized command execution, malformed command batches, admin misuse, and command revocation behavior
- Reduce or clearly document delegatecall risk

### Acceptance Criteria
- Hook composition MVP has passing unit and integration tests
- Security assumptions are documented in `THREAT_MODEL.md`
- Example pool can run approved command behavior in local tests

## Milestone 3 — Bonding and Reward Accounting MVP
**Request:** $10,000
**Target duration:** 3 weeks

### Deliverables
- Finalize MVP bonding flow
- Finalize reward/fee accounting behavior for bonded participants
- Document non-withdrawable principal assumptions and authorized-withdrawer risks
- Add tests for:
  - multiple bonders
  - zero-bonder fee handling
  - partial reward claims
  - ERC20 and native asset paths
  - admin/withdrawal edge cases
- Produce a short economic design note

### Acceptance Criteria
- Bonding/reward flows pass expanded test coverage
- User-facing bonding risks are documented
- MVP accounting behavior is deterministic and reviewable

## Milestone 4 — Testnet / Unichain Demo Package
**Request:** $10,000
**Target duration:** 3 weeks

### Deliverables
- Deploy MVP contracts to a public testnet or Unichain test environment, if available/suitable
- Provide deployment scripts and addresses
- Demonstrate a full flow:
  - create/configure hook-enabled pool
  - attach approved command module
  - bond/support hook behavior
  - execute swap or simulated hook-triggered action
  - operator processes reward/rebate event
- Publish demo instructions and short walkthrough video or written demo report

### Acceptance Criteria
- Reviewer can reproduce or inspect the demo flow
- Deployment artifacts and addresses are documented
- Demo shows end-to-end behavior beyond local-only tests

## Milestone 5 — Audit-Readiness and UFSF Submission Package
**Request:** $10,000
**Target duration:** 2 weeks

### Deliverables
- Finalize `THREAT_MODEL.md`
- Add audit scope document
- Add invariants checklist
- Add known issues / out-of-scope list
- Run static analysis/pre-audit checks where practical
- Prepare Uniswap Foundation Security Fund / audit subsidy submission materials

### Acceptance Criteria
- Contracts have a frozen audit candidate scope
- Security docs are complete enough for external reviewer onboarding
- Project is ready to pursue audit subsidy or formal review

## Total Timeline
Estimated duration: **10–13 weeks**

## Success Metrics
- Clean CI with Solidity and operator tests
- Deployment scripts repaired or cleanly profiled
- Expanded hook-composition test coverage
- Expanded bonding/reward accounting test coverage
- Public demo deployment or reproducible testnet package
- Complete threat model and audit-readiness package
- Clear path to UFSF/audit subsidy application

## Risks and Mitigations
### Delegatecall / command execution risk
Mitigation: narrow approved command set, document command lifecycle, add approval/revocation tests, avoid delegatecall where practical.

### Centralized operator risk
Mitigation: clearly mark operator as MVP trust assumption, design for future Merkle or proof-based distribution, document failure modes.

### Bonding principal/admin risk
Mitigation: document non-withdrawable principal and authorized withdrawal assumptions, add tests, consider timelock/governance controls in future versions.

### Scope creep
Mitigation: focus grant MVP on hook composition, bonding/rewards, operator demo, and audit readiness. COFHE, full marketplace UI, and production launch remain future work unless explicitly included later.

## Out of Scope for This Grant
- Mainnet launch
- Full production marketplace UI
- Formal audit payment itself
- Fully decentralized AVS/operator network
- Production-grade COFHE encrypted auction system
- Guarantees of liquidity or TVL

## Requested Outcome
The requested grant will convert Bonded Hooks from a dormant award-winning prototype into a clean, testable, documented, deployable Uniswap v4 hook infrastructure MVP ready for external review and follow-on audit support.
