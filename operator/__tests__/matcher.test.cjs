const { matchBiddersFromInfos } = require("../matcher.cjs");

function make(addr, total, maxEpoch = BigInt(0), rush = 0) {
  return {
    bidder: addr,
    totalBidAmount: total,
    maxSpendPerEpoch: maxEpoch,
    minMintingRate: BigInt(0),
    rushFactor: rush,
    createdEpoch: 0,
    lastUpdatedEpoch: 0
  };
}

describe("matchBiddersFromInfos", () => {
  test("single bidder covers full amount", () => {
    const infos = [make("A", BigInt(1000))];
    const res = matchBiddersFromInfos(infos, BigInt(500));
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
    const res = matchBiddersFromInfos(infos, BigInt(250));
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
      make("B", BigInt(1000), BigInt(0))    // uncapped
    ];
    const res = matchBiddersFromInfos(infos, BigInt(250));
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
    const res = matchBiddersFromInfos(infos, BigInt(200));
    // Should assign A=50, B=25 and then stop
    expect(res.length).toBe(2);
    expect(res[0].assigned).toBe(BigInt(50));
    expect(res[1].assigned).toBe(BigInt(25));
    const totalAssigned = res.reduce((acc, r) => acc + r.assigned, BigInt(0));
    expect(totalAssigned).toBe(BigInt(75));
  });

  test("zero amount returns empty", () => {
    const infos = [make("A", BigInt(100))];
    const res = matchBiddersFromInfos(infos, BigInt(0));
    expect(res.length).toBe(0);
  });
});