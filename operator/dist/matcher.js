"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.matchBiddersFromInfos = matchBiddersFromInfos;
/**
 * Pure bidder matching function.
 * - infos: array of BidInfo (candidate bidders)
 * - amount: total wei to cover
 * Returns list of { bidder, assigned } in priority order.
 */
function matchBiddersFromInfos(infosInput, amount, opts) {
    if (amount <= BigInt(0))
        return [];
    const now = opts?.nowSeconds ?? Math.floor(Date.now() / 1000);
    // Copy and filter positive balances and enforce optional constraints
    const infos = infosInput
        .filter((i) => i.totalBidAmount > BigInt(0))
        .filter((i) => {
        if (opts?.pointsPerWei && i.minMintingRate > BigInt(0)) {
            // Exclude bidder if required min minting rate exceeds available points per wei
            if (opts.pointsPerWei < i.minMintingRate)
                return false;
        }
        if (opts?.cooldownSeconds && i.lastUpdatedEpoch > 0) {
            const elapsed = now - i.lastUpdatedEpoch;
            if (elapsed < opts.cooldownSeconds)
                return false;
        }
        return true;
    })
        .slice();
    // Sort by rushFactor desc, then maxSpendPerEpoch desc, then totalBidAmount desc
    infos.sort((a, b) => {
        if (b.rushFactor !== a.rushFactor)
            return b.rushFactor - a.rushFactor;
        if (b.maxSpendPerEpoch !== a.maxSpendPerEpoch)
            return b.maxSpendPerEpoch > a.maxSpendPerEpoch ? 1 : -1;
        if (b.totalBidAmount > a.totalBidAmount)
            return 1;
        if (b.totalBidAmount < a.totalBidAmount)
            return -1;
        return 0;
    });
    let remaining = amount;
    const result = [];
    for (const inf of infos) {
        if (remaining <= BigInt(0))
            break;
        const cap = inf.maxSpendPerEpoch > BigInt(0) ? inf.maxSpendPerEpoch : inf.totalBidAmount;
        const available = inf.totalBidAmount < cap ? inf.totalBidAmount : cap;
        if (available <= BigInt(0))
            continue;
        const take = available >= remaining ? remaining : available;
        result.push({ bidder: inf.bidder, assigned: take });
        remaining -= take;
    }
    return result;
}
