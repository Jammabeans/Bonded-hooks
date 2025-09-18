DEGEN Integration README

Overview

This document explains how the three core contracts interact in the “degen” system, how state flows between them, and a set of explicit rules (invariants and operational constraints) derived directly from the code so you can confirm the behaviour matches what you want.

Quick references
- Degen pool: [`points-hook/src/DegenPool.sol`](points-hook/src/DegenPool.sol:1)
- Gas rebate manager: [`points-hook/src/GasRebateManager.sol`](points-hook/src/GasRebateManager.sol:1)
- Bid manager: [`points-hook/src/BidManager.sol`](points-hook/src/BidManager.sol:1)
- Integration test (end-to-end): [`points-hook/test/DegenIntegration.t.sol`](points-hook/test/DegenIntegration.t.sol:116)

Purpose summary
- DegenPool: points-based reward pool that accepts ETH deposits, converts deposits to per-point rewards using a scaled cumulative accumulator, and allows users to withdraw their pending + owed rewards. On withdraw the user loses half their points (burned).
- GasRebateManager: trusted off-chain operator(s) push per-epoch rebate credits to user balances; users withdraw ETH from the contract.
- BidManager: stores one active bid per address, supports top-ups and pending rushFactor updates; settlement role consumes bid balances per epoch. Owner may recover funds from bids or withdraw contract ETH.

Detailed behavior (by contract)

DegenPool — key pieces and flows
- SCALE = 1e18 is used to represent fractional reward-per-point values.
- Points & checkpoints:
  - Active points: mapping(address => uint256) public points
  - Per-user checkpoint: mapping(address => uint256) public userCumPerPoint stores last cumulative value when user’s points were last checkpointed.
- Deposits:
  - Accepts ETH via receive(). If totalPoints > 0 it computes delta = (msg.value * SCALE) / totalPoints and adds to cumulativeRewardPerPoint.
  - If totalPoints == 0, ETH remains in contract balance (unallocated) and is not added to cumulative per-point.
- Minting points:
  - mintPoints() and batchMintPoints() are settlement-only.
  - When minting additional points to an account that already has points, owed rewards = existingPts * (cumulativeRewardPerPoint - lastCum) / SCALE are moved into pendingRewards before adding the new points.
  - userCumPerPoint is then checkpointed to current cumulativeRewardPerPoint so new points do not retroactively claim past deposits.
- Withdraw (withdrawRewards):
  - Payout = pendingRewards + owedActive (owedActive computed against current cumulativeRewardPerPoint).
  - Preconditions: payout > 0 and contract must have sufficient ETH; otherwise revert ("Payout zero" / "Insufficient contract balance").
  - Effects:
    - pendingRewards[user] = 0
    - userCumPerPoint[user] = cumulativeRewardPerPoint
    - burned = floor(points[user] / 2); points[user] -= burned; totalPoints -= burned
    - transfer payout to caller and emit RewardsWithdrawn
  - Protected by nonReentrant.
- Rounding/leftovers:
  - Integer division with SCALE causes rounding down; leftover wei remain in contract balance until future deposits or withdrawals can absorb them.
- Events: DepositReceived, RewardsMovedToPending, RewardsWithdrawn, PointsMinted, PointsBatchMinted.

GasRebateManager — key pieces and flows
- Operators:
  - Mapping operators[] tracks authorized off-chain operators.
  - Owner sets operators via setOperator().
- pushGasPoints(epoch, users[], amounts[]) (onlyOperator):
  - Requires arrays match, non-empty, and epoch not already processed.
  - Marks epochProcessed[epoch] = true and increments per-user rebateBalance[user] += amount.
  - Emits GasPointsPushed.
- withdrawGasRebate():
  - Transfers rebateBalance[msg.sender] to caller, sets rebateBalance[msg.sender] = 0, then emits RebateWithdrawn.
  - Contract must hold ETH to satisfy withdraw — owner/operator must fund contract ahead of withdrawals.
  - This function does not currently use nonReentrant (consider adding if logic grows).
- receive():
  - Accepts ETH and emits Received.

BidManager — key pieces and flows
- Single bid per address: mapping(address => Bid) public bids; createBid requires no existing bid for msg.sender.
- MIN_BID_WEI and MAX_RUSH enforce minimums and rush bounds.
- createBid(rushFactor) payable:
  - Stores bid with amountWei = msg.value.
  - Emits BidCreated.
- topUpBid() payable:
  - Adds msg.value to bids[msg.sender].amountWei.
  - Emits BidToppedUp.
- updateRushFactor(newRush, effectiveEpoch):
  - Sets pendingRushFactor and lastUpdatedEpoch for msg.sender.
  - pendingRushFactor becomes active only if lastUpdatedEpoch < epoch at finalize.
- finalizeEpochConsumeBids(epoch, address[] bidders, uint256[] consumedAmounts) (onlySettlement):
  - epoch must be unprocessed; arrays must match.
  - For each bidder: apply pendingRushFactor if b.pendingRushFactor != 0 and b.lastUpdatedEpoch < epoch; if consume > 0 require b.amountWei >= consume and subtract consume; emit BidConsumed.
  - Marks epochProcessed[epoch] = true and emits EpochFinalized.
- ownerRecoverBid(bidderAddr, to, amount): owner withdraws amount from a specific bid (requires bid.amountWei >= amount) and transfers ETH to to.
- ownerWithdraw(to, amount): owner may withdraw ETH from contract balance.

Integration flows (how the pieces work together)
- Off-chain operator calls pushGasPoints to credit users per-epoch.
- Users withdraw from GasRebateManager, receiving ETH into their accounts.
- Users deposit ETH into DegenPool; if totalPoints > 0 the deposit immediately increases cumulativeRewardPerPoint.
- Settlement mints points to users (mintPoints / batchMintPoints) so those points participate in future deposits.
- Users create bids in BidManager and top them up.
- Settlement finalizes and consumes bids (finalizeEpochConsumeBids) decrementing bid.amountWei.
- Owner transfers consumed ETH from BidManager into DegenPool (ownerWithdraw or ownerRecoverBid) to convert consumed bid funds into pool rewards.
- Points holders withdraw from DegenPool, receiving pending + owed; half their points burn on withdraw.

Rules & invariants (explicit)
- Role rules:
  - Only owner may set settlement/operator roles.
  - onlySettlement modifier restricts minting and finalization to settlementRole addresses.
- Epoch rules:
  - Each epoch may be processed only once in both GasRebateManager and BidManager.
- Bid rules:
  - One active bid per address.
  - createBid enforces MIN_BID_WEI and MAX_RUSH.
  - topUpBid only affects msg.sender's bid.
  - finalizeEpochConsumeBids requires sufficient bid balance for each consumed amount.
- Rush factor timing:
  - pendingRushFactor is applied when lastUpdatedEpoch < epoch (strict inequality).
- Pool reward math:
  - All per-point accrual uses SCALE (1e18); integer division truncates fractional wei.
  - When minting to an address with existing points, owed is moved to pendingRewards before adding new points.
- Safety:
  - DegenPool.withdrawRewards is nonReentrant.
  - Consider adding nonReentrant to GasRebateManager.withdrawGasRebate if logic grows.
- ETH custody:
  - GasRebateManager must be funded before users withdraw.
  - finalizeEpochConsumeBids only updates accounting; owner actions are required to move ETH between contracts.
- Rounding:
  - Small deposits can leave remainders less than totalPoints; tests should allow small wei remainders.

Failure modes
- Withdrawals revert if contract lacks ETH even when internal accounting lists a balance.
- Attempting to consume more than bid.amountWei reverts.
- Processing the same epoch twice reverts.
- Creating a second bid for the same address reverts.

Operational / testing checklist
- Confirm owner and settlement/operator assignments for production.
- Ensure GasRebateManager is funded by owner/operator before operator pushes rebates and users withdraw.
- Validate owner process for moving consumed bid funds into DegenPool (ownerWithdraw vs ownerRecoverBid).
- Account for rounding/truncation in tests (allow small residual wei).

Suggested minor improvements
- Add nonReentrant to GasRebateManager.withdrawGasRebate.
- Add explicit "unallocated" balance tracking in DegenPool for clarity.
- Expose a view to report unallocated contract ETH vs allocated cumulative rewards for easier off-chain audit.

Concrete end-to-end sequence (example)
1. Owner/operator funds GasRebateManager.
2. Operator calls pushGasPoints(epoch, users, amounts).
3. Users call withdrawGasRebate() to receive ETH.
4. Settlement mints points using mintPoints/batchMintPoints.
5. Users deposit ETH into DegenPool (receive) which updates cumulativeRewardPerPoint if totalPoints > 0.
6. Users create/top up bids in BidManager.
7. Settlement calls finalizeEpochConsumeBids to decrement bid balances.
8. Owner transfers consumed ETH from BidManager to DegenPool (ownerWithdraw or ownerRecoverBid).
9. DegenPool distributes rewards to points; users withdraw via withdrawRewards and half their points burn.

Where to look in code
- Pool cumulative math, receive, mint, withdraw: [`points-hook/src/DegenPool.sol`](points-hook/src/DegenPool.sol:1)
- Rebate push and withdraw: [`points-hook/src/GasRebateManager.sol`](points-hook/src/GasRebateManager.sol:1)
- Bid lifecycle and finalization: [`points-hook/src/BidManager.sol`](points-hook/src/BidManager.sol:1)
- Integration test example: [`points-hook/test/DegenIntegration.t.sol`](points-hook/test/DegenIntegration.t.sol:116)

If you want this expanded into additional documentation, or converted to a markdown file with diagrams or code snippets, I can produce that next.