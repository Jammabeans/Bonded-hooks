"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const matcher_1 = require("../matcher");
function make(addr, total, maxEpoch = BigInt(0), rush = 0, minMint = BigInt(0), lastUpdated = 0) {
    return {
        bidder: addr,
        totalBidAmount: total,
        maxSpendPerEpoch: maxEpoch,
        minMintingRate: minMint,
        rushFactor: rush,
        createdEpoch: 0,
        lastUpdatedEpoch: lastUpdated
    };
}
describe("matchBiddersFromInfos", () => {
    test("single bidder covers full amount", () => {
        const infos = [make("A", BigInt(1000))];
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(500));
        expect(res.length).toBe(1);
        expect(res[0].bidder).toBe("A");
        expect(res[0].assigned).toBe(BigInt(500));
    });
    test("multiple bidders sorted by rush factor then total amount", () => {
        const infos = [
            make("A", BigInt(100), BigInt(0), 1),
            make("B", BigInt(1000), BigInt(0), 0),
            make("C", BigInt(200), BigInt(0), 2)
        ];
        // Order by rush desc: C (2), A (1), B (0)
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(250));
        expect(res.length).toBeGreaterThanOrEqual(2);
        expect(res[0].bidder).toBe("C");
        // C has 200, so should take 200, remaining 50 -> next A takes 50
        expect(res[0].assigned).toBe(BigInt(200));
        expect(res[1].bidder).toBe("A");
        expect(res[1].assigned).toBe(BigInt(50));
    });
    test("respects maxSpendPerEpoch cap", () => {
        const infos = [
            make("A", BigInt(1000), BigInt(100)), // capped at 100
            make("B", BigInt(1000), BigInt(0)) // uncapped
        ];
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(250));
        // A should provide 100 (cap), B should provide 150
        expect(res.length).toBe(2);
        expect(res[0].bidder).toBe("A");
        expect(res[0].assigned).toBe(BigInt(100));
        expect(res[1].bidder).toBe("B");
        expect(res[1].assigned).toBe(BigInt(150));
    });
    test("partial coverage when bidders insufficient", () => {
        const infos = [
            make("A", BigInt(50)),
            make("B", BigInt(25))
        ];
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(200));
        // Should assign A=50, B=25 and then stop
        expect(res.length).toBe(2);
        expect(res[0].assigned).toBe(BigInt(50));
        expect(res[1].assigned).toBe(BigInt(25));
        const totalAssigned = res.reduce((acc, r) => acc + r.assigned, BigInt(0));
        expect(totalAssigned).toBe(BigInt(75));
    });
    test("zero amount returns empty", () => {
        const infos = [make("A", BigInt(100))];
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(0));
        expect(res.length).toBe(0);
    });
    test("filters by minMintingRate (pointsPerWei)", () => {
        // bidder A requires high minMintingRate and should be excluded when pointsPerWei is low
        const infos = [
            make("A", BigInt(1000), BigInt(0), 1, BigInt(1000)), // minMintingRate 1000
            make("B", BigInt(1000), BigInt(0), 0, BigInt(0))
        ];
        // pointsPerWei set to 1 (less than A.minMintingRate), so A excluded
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(100), { pointsPerWei: BigInt(1) });
        expect(res.length).toBeGreaterThan(0);
        expect(res.some(r => r.bidder === "A")).toBe(false);
    });
    test("filters by cooldownSeconds", () => {
        const now = Math.floor(Date.now() / 1000);
        // bidder A lastUpdated very recent, within cooldown
        const infos = [
            make("A", BigInt(1000), BigInt(0), 1, BigInt(0), now - 10),
            make("B", BigInt(1000), BigInt(0), 0, BigInt(0), now - 1000)
        ];
        // cooldownSeconds 60 -> A excluded (lastUpdated 10s ago)
        const res = (0, matcher_1.matchBiddersFromInfos)(infos, BigInt(100), { cooldownSeconds: 60, nowSeconds: now });
        expect(res.some(r => r.bidder === "A")).toBe(false);
        expect(res.some(r => r.bidder === "B")).toBe(true);
    });
});
