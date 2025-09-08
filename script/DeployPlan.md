Foundry Deploy Plan for Bonded-hooks integration
===============================================

Purpose
-------
This document describes the concrete steps performed by [`Bonded-hooks/script/Deploy.s.sol:1`](Bonded-hooks/script/Deploy.s.sol:1) and the expected post-deploy wiring.

Overview
--------
The deploy script performs a deterministic MasterControl CREATE2 deployment and wires the platform using a central AccessControl registry. The script configures roles and performs the required setup in a single broadcasted transaction.

Deploy steps (actual script)
----------------------------
1. Ensure the test harness or caller sets IPoolManager via DeployScript.setManager(address).
2. Deploy AccessControl.
3. Deploy PoolLaunchPad(manager, accessControl).
4. Deploy MasterControl via an on-chain Create2Factory + HookMiner:
   - The script deploys Create2Factory and uses HookMiner to find a salt such that CREATE2 yields an address encoding required hook flags.
   - The script calls Create2Factory.deployAndCall(..., setAccessControl) so MasterControl.setAccessControl(accessControl) is executed atomically during deployment.
5. Call accessControl.setPoolLaunchPad(poolLaunchPad).
6. Deploy FeeCollector(accessControl), GasBank(accessControl), DegenPool(accessControl).
7. Deploy BidManager(accessControl).
8. Deploy Settings(gasBank, degenPool, feeCollector, accessControl).
9. Deploy ShareSplitter(settings, accessControl).
10. Deploy Bonding(accessControl).
11. Deploy MockAVS (test-only).
12. Grant required ACL roles to the broadcast EOA (tx.origin) so role-protected setup calls can be executed inside the same broadcast:
    - ROLE_GAS_BANK_ADMIN, ROLE_FEE_COLLECTOR_ADMIN, ROLE_DEGEN_ADMIN, ROLE_BID_MANAGER_ADMIN, ROLE_SHARE_ADMIN
    - ROLE_BONDING_ADMIN, ROLE_BONDING_PUBLISHER, ROLE_BONDING_WITHDRAWER
    - ROLE_PRIZEBOX_ADMIN, ROLE_SHAKER_ADMIN, ROLE_MASTER
13. Execute role-protected wiring calls:
    - gasBank.setShareSplitter(shareSplitter)
    - feeCollector.setSettings(settings)
    - bidManager.setSettlementRole(mockAvs, true)
    - degenPool.setSettlementRole(mockAvs, true)
14. Configure Bonding:
    - bonding.setAuthorizedPublisher(masterControl)
    - bonding.setAuthorizedWithdrawer(gasBank)
    - bonding.setAuthorizedWithdrawer(shareSplitter)
15. Deploy PrizeBox(accessControl, mockAvs) and Shaker(accessControl, shareSplitter, prizebox, mockAvs)
    - Grant PrizeBox/Shaker admin roles to tx.origin so setup succeeds
    - prizeBox.setShaker(shaker)
16. Deploy PointsCommand and register it with MasterControl:
    - Grant ROLE_MASTER to tx.origin and call masterControl.approveCommand(hookPath=0, pointsCommand, "PointsCommand")

Post-deploy outputs
-------------------
- The script returns an array of deployed addresses and also writes `script/deployments.json` when run in environments that allow vm.writeFile.
- The JSON contains entries for: PoolManager, AccessControl, PoolLaunchPad, MasterControl, FeeCollector, GasBank, DegenPool, Settings, ShareSplitter, Bonding, PrizeBox, Shaker, PointsCommand, BidManager, MockAVS.

Notes & operational guidance
----------------------------
- MasterControl is ACL-configured at deployment time via the factory to avoid brittle owner-transfer flows.
- The script grants roles to tx.origin so the broadcast EOA can execute role-protected setters in the same transaction. If your operational model prefers a different principal (deployer EOA or the script contract itself), update the grant targets in the script.
- If your test/CI environment forbids vm.writeFile to the workspace path, run the script and read the returned address array rather than relying on on-disk JSON.
- If you encounter "stack too deep" compiler issues in CI, enable the optimizer with viaIR or split large functions. The current script uses address arrays to mitigate stack usage.

Files the script touches
-----------------------
- `script/Deploy.s.sol` — deploy implementation (see above)
- `script/deployments.json` — written by run() when permitted

End of plan