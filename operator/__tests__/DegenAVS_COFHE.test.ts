import { matchBiddersFromInfos } from "../DegenAVS_COFHE";

describe("matchBiddersFromInfos unit tests", () => {
  test("basic allocation prefers higher rushFactor", () => {
    const infos = [
      { bidder: "A", totalBidAmount: BigInt(1000), maxSpendPerEpoch: BigInt(0), minMintingRate: BigInt(0), rushFactor: 1, createdEpoch: 0, lastUpdatedEpoch: 0 },
      { bidder: "B", totalBidAmount: BigInt(500), maxSpendPerEpoch: BigInt(0), minMintingRate: BigInt(0), rushFactor: 0, createdEpoch: 0, lastUpdatedEpoch: 0 }
    ];
    const res = matchBiddersFromInfos(infos as any, BigInt(600));
    expect(res.length).toBeGreaterThan(0);
    expect(res[0].bidder).toBe("A");
    expect(res[0].assigned).toBe(BigInt(600));
  });

  test("respects per-epoch cap and ordering", () => {
    const infos = [
      { bidder: "A", totalBidAmount: BigInt(1000), maxSpendPerEpoch: BigInt(100), minMintingRate: BigInt(0), rushFactor: 1, createdEpoch: 0, lastUpdatedEpoch: 0 },
      { bidder: "B", totalBidAmount: BigInt(1000), maxSpendPerEpoch: BigInt(0), minMintingRate: BigInt(0), rushFactor: 0, createdEpoch: 0, lastUpdatedEpoch: 0 }
    ];
    const res = matchBiddersFromInfos(infos as any, BigInt(250));
    expect(res.length).toBe(2);
    expect(res[0].bidder).toBe("A");
    expect(res[0].assigned).toBe(BigInt(100));
    expect(res[1].assigned).toBe(BigInt(150));
  });
});