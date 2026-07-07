# Bonded Hooks — Roadmap

## Phase 0: Repo Cleanup and Deployment Script Repair
- Remove generated/runtime artifacts from tracking and enforce ignore rules
- Fix `forge build` script stack-too-deep blocker in deployment scripts
- Lock in repeatable CI commands for Solidity and operator suites

## Phase 1: Safe Hook Composition MVP
- Harden command routing and approval boundaries
- Add explicit guardrails around privileged execution paths
- Expand tests around failure modes and command misuse

## Phase 2: Bonding/Reward MVP
- Finalize bonding lifecycle and reward accounting flows
- Add edge-case and invariant-focused test coverage
- Validate integration behavior under realistic operator assumptions

## Phase 3: Testnet/Unichain Demo
- Deploy reference stack to testnet/Unichain environment
- Publish deploy/runbook for reproducibility
- Demonstrate end-to-end flows for external reviewers

## Phase 4: Audit-Readiness and UFSF Prep
- Final threat model and control mapping
- Resolve high-priority security findings and harden admin controls
- Prepare grant and ecosystem-facing technical package
