# Applied Grant Record

**Submission date:** July 7, 2026  
**Project:** Bonded Hooks  
**Program:** Uniswap Foundation Grants  
**Requested amount:** $50,000  
**Timeline:** 10–13 weeks  
**Stage:** Pre-launch  
**Submitted repo:** https://github.com/Jammabeans/Bonded-hooks

## Milestone Summary

1. Repo hardening, CI, deployment repair — $7,500
2. Safe hook composition MVP — $12,500
3. Bonding/reward accounting MVP — $10,000
4. Testnet / Unichain demo — $10,000
5. Audit-readiness and UFSF prep — $10,000

## Current Baseline

- 117 Solidity tests pass with `forge test --skip script -vvv`
- `cd operator && npm run build` passes
- `cd operator && npm test` passes with 21 tests
- Full `forge build` blocked by deployment-script/compiler stack-depth issue

## Follow-up Plan

- Fix or isolate full build issue
- Add/repair CI
- Prepare short demo
- Follow up if no response after 2 weeks
