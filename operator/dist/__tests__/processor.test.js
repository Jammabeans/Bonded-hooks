"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const processor_1 = require("../processor");
function makeSettings(hookRefundWei, defaultRefundWei, pointsPerWei, cooldownSeconds) {
    return {
        getHookRefundFor: async (poolId, hook) => {
            if (hookRefundWei)
                return hookRefundWei;
            return BigInt(0);
        },
        getUint: async (key) => {
            // naive key mapping for tests
            if (String(key).includes("defaultRefundWei"))
                return defaultRefundWei ?? BigInt(0);
            if (String(key).includes("pointsPerWei"))
                return pointsPerWei ?? BigInt(0);
            if (String(key).includes("bidderCooldownSeconds"))
                return BigInt(cooldownSeconds ?? 0);
            if (String(key).includes("epochSeconds"))
                return BigInt(600);
            return BigInt(0);
        }
    };
}
function makeGasRebate() {
    return {
        pushGasPoints: jest.fn(async (epoch, users, amounts) => {
            return { hash: "0xdeadbeef", wait: async () => ({}) };
        })
    };
}
function makeBidManager(bids) {
    return {
        getBid: jest.fn(async (addr) => bids[addr])
    };
}
function makeDegenPool() {
    return {
        batchMintPoints: jest.fn(async (accounts, pts, epoch) => ({ hash: "0xmint" }))
    };
}
test("full AVS flow: pushes gas points and mints points to matched bidder", async () => {
    const settings = makeSettings(undefined, BigInt(1000), BigInt(1000000000000n), 0);
    const gasRebate = makeGasRebate();
    const bidderAddr = "0xB1";
    const bids = {};
    bids[bidderAddr] = {
        bidder: bidderAddr,
        totalBidAmount: BigInt(1000000000000000000).toString(), // 1 ETH
        maxSpendPerEpoch: BigInt(1000000000000000000).toString(),
        minMintingRate: BigInt(0).toString(),
        rushFactor: 1,
        createdEpoch: 0,
        lastUpdatedEpoch: 0
    };
    const bidManager = makeBidManager(bids);
    const degenPool = makeDegenPool();
    const deps = {
        settings,
        gasRebate,
        bidManager,
        degenPool,
        candidateBidders: [bidderAddr],
        nowSeconds: Math.floor(Date.now() / 1000)
    };
    const res = await (0, processor_1.processRebateEvent)("0xorigin", "0xTrader", BigInt(1), BigInt(0), BigInt(100), deps);
    expect(res.pushed).toBe(true);
    expect(gasRebate.pushGasPoints).toHaveBeenCalled();
    // degenPool should have been called to mint points to bidder
    expect(degenPool.batchMintPoints).toHaveBeenCalled();
});
test("insufficient bidders: still pushes gas points but mints nothing", async () => {
    const settings = makeSettings(undefined, BigInt(1000), BigInt(1000000000000n), 0);
    const gasRebate = makeGasRebate();
    const bidManager = makeBidManager({}); // no bidders
    const degenPool = makeDegenPool();
    const deps = {
        settings,
        gasRebate,
        bidManager,
        degenPool,
        candidateBidders: [],
        nowSeconds: Math.floor(Date.now() / 1000)
    };
    const res = await (0, processor_1.processRebateEvent)("0xorigin", "0xTrader", BigInt(2), BigInt(0), BigInt(100), deps);
    expect(res.pushed).toBe(true);
    // no bidders => no mint
    expect(degenPool.batchMintPoints).not.toHaveBeenCalled();
});
test("no refund configured: skips processing", async () => {
    const settings = makeSettings(undefined, BigInt(0), BigInt(0), 0); // no refund
    const gasRebate = makeGasRebate();
    const bidderAddr = "0xB1";
    const bids = {};
    bids[bidderAddr] = {
        bidder: bidderAddr,
        totalBidAmount: BigInt(1000).toString(),
        maxSpendPerEpoch: BigInt(1000).toString(),
        minMintingRate: BigInt(0).toString(),
        rushFactor: 1,
        createdEpoch: 0,
        lastUpdatedEpoch: 0
    };
    const bidManager = makeBidManager(bids);
    const degenPool = makeDegenPool();
    const deps = {
        settings,
        gasRebate,
        bidManager,
        degenPool,
        candidateBidders: [bidderAddr],
        nowSeconds: Math.floor(Date.now() / 1000)
    };
    const res = await (0, processor_1.processRebateEvent)("0xorigin", "0xTrader", BigInt(3), BigInt(0), BigInt(100), deps);
    expect(res.pushed).toBe(false);
    expect(gasRebate.pushGasPoints).not.toHaveBeenCalled();
    expect(degenPool.batchMintPoints).not.toHaveBeenCalled();
});
test("multiple bidders split refund", async () => {
    const settings = makeSettings(undefined, BigInt(1000), BigInt(1000000000000n), 0);
    const gasRebate = makeGasRebate();
    const bidderA = "0xA";
    const bidderB = "0xB";
    const bids = {};
    bids[bidderA] = {
        bidder: bidderA,
        totalBidAmount: BigInt(50).toString(),
        maxSpendPerEpoch: BigInt(50).toString(),
        minMintingRate: BigInt(0).toString(),
        rushFactor: 1,
        createdEpoch: 0,
        lastUpdatedEpoch: 0
    };
    bids[bidderB] = {
        bidder: bidderB,
        totalBidAmount: BigInt(100).toString(),
        maxSpendPerEpoch: BigInt(100).toString(),
        minMintingRate: BigInt(0).toString(),
        rushFactor: 0,
        createdEpoch: 0,
        lastUpdatedEpoch: 0
    };
    const bidManager = makeBidManager(bids);
    const degenPool = makeDegenPool();
    const deps = {
        settings,
        gasRebate,
        bidManager,
        degenPool,
        candidateBidders: [bidderA, bidderB],
        nowSeconds: Math.floor(Date.now() / 1000)
    };
    // refund requires 120 wei (greater than A's 50 -> A+B split)
    const refundAmount = BigInt(120);
    const res = await (0, processor_1.processRebateEvent)("0xorigin", "0xTrader", BigInt(4), BigInt(0), BigInt(100), deps);
    expect(res.pushed).toBe(true);
    // minted to bidders (sum of assigned > 0)
    expect(degenPool.batchMintPoints).toHaveBeenCalled();
});
