"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processRebateEvent = processRebateEvent;
const matcher_1 = require("./matcher");
const KEY_DEFAULT_REFUND = (s) => s; // placeholder, settings keys should be keccak256 in real usage
async function processRebateEvent(txOrigin, trader, poolId, poolTotalFeeBips, baseGasPrice, deps) {
    const { settings, gasRebate, bidManager, degenPool, candidateBidders = [], nowSeconds } = deps;
    // Resolve refund (try hook-level then default)
    let refundWei = BigInt(0);
    if (settings && typeof settings.getHookRefundFor === "function") {
        try {
            const v = await settings.getHookRefundFor(poolId, undefined);
            if (v && v.toString() !== "0")
                refundWei = BigInt(v.toString());
        }
        catch {
            // ignore
        }
    }
    if (refundWei === BigInt(0) && settings && typeof settings.getUint === "function") {
        try {
            const v = await settings.getUint(KEY_DEFAULT_REFUND("defaultRefundWei"));
            if (v && v.toString() !== "0")
                refundWei = BigInt(v.toString());
        }
        catch {
            // ignore
        }
    }
    if (refundWei === BigInt(0)) {
        return { pushed: false, minted: false, reason: "no-refund" };
    }
    // epochSeconds
    let epochSeconds = 600;
    if (settings && typeof settings.getUint === "function") {
        try {
            const es = await settings.getUint(KEY_DEFAULT_REFUND("epochSeconds"));
            if (es && es.toString() !== "0")
                epochSeconds = Number(es.toString());
        }
        catch {
            // ignore
        }
    }
    const now = nowSeconds ?? Math.floor(Date.now() / 1000);
    const epoch = Math.floor(now / epochSeconds);
    // push gas points
    let pushed = false;
    if (gasRebate && typeof gasRebate.pushGasPoints === "function") {
        try {
            await gasRebate.pushGasPoints(epoch, [trader], [refundWei.toString()]);
            pushed = true;
        }
        catch (err) {
            pushed = false;
        }
    }
    // Read bidder infos
    const infos = [];
    for (const b of candidateBidders) {
        if (!bidManager || typeof bidManager.getBid !== "function")
            break;
        try {
            const bid = await bidManager.getBid(b);
            if (!bid)
                continue;
            infos.push({
                bidder: bid.bidder,
                totalBidAmount: BigInt(bid.totalBidAmount?.toString ? bid.totalBidAmount.toString() : bid.totalBidAmount || "0"),
                maxSpendPerEpoch: BigInt(bid.maxSpendPerEpoch?.toString ? bid.maxSpendPerEpoch.toString() : bid.maxSpendPerEpoch || "0"),
                minMintingRate: BigInt(bid.minMintingRate?.toString ? bid.minMintingRate.toString() : bid.minMintingRate || "0"),
                rushFactor: Number(bid.rushFactor || 0),
                createdEpoch: Number(bid.createdEpoch || 0),
                lastUpdatedEpoch: Number(bid.lastUpdatedEpoch || 0)
            });
        }
        catch {
            // ignore individual bidder failures
        }
    }
    // Read pointsPerWei and cooldown from settings
    let pointsPerWei = BigInt(1000000000000n);
    let cooldownSeconds = 0;
    if (settings && typeof settings.getUint === "function") {
        try {
            const p = await settings.getUint(KEY_DEFAULT_REFUND("pointsPerWei"));
            if (p && p.toString() !== "0")
                pointsPerWei = BigInt(p.toString());
        }
        catch { }
        try {
            const c = await settings.getUint(KEY_DEFAULT_REFUND("bidderCooldownSeconds"));
            if (c && c.toString() !== "0")
                cooldownSeconds = Number(c.toString());
        }
        catch { }
    }
    // Match bidders
    const matches = (0, matcher_1.matchBiddersFromInfos)(infos, refundWei, { pointsPerWei, cooldownSeconds, nowSeconds: now });
    // Mint points to matched bidders proportionally
    let minted = false;
    if (matches.length > 0 && degenPool && typeof degenPool.batchMintPoints === "function") {
        const accounts = [];
        const pts = [];
        for (const m of matches) {
            const ptsAmount = (m.assigned * pointsPerWei).toString();
            if (BigInt(ptsAmount) > BigInt(0)) {
                accounts.push(m.bidder);
                pts.push(ptsAmount);
            }
        }
        if (accounts.length > 0) {
            try {
                await degenPool.batchMintPoints(accounts, pts, epoch);
                minted = true;
            }
            catch {
                minted = false;
            }
        }
    }
    return { pushed, minted, matches };
}
