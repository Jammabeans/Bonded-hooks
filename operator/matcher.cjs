exports.matchBiddersFromInfos = function(infosInput, amount) {
  if (amount <= BigInt(0)) return [];

  const infos = infosInput.filter((i) => i.totalBidAmount > BigInt(0)).slice();

  infos.sort((a, b) => {
    if (b.rushFactor !== a.rushFactor) return b.rushFactor - a.rushFactor;
    if (b.totalBidAmount > a.totalBidAmount) return 1;
    if (b.totalBidAmount < a.totalBidAmount) return -1;
    return 0;
  });

  let remaining = amount;
  const result = [];

  for (const inf of infos) {
    if (remaining <= BigInt(0)) break;
    const cap = inf.maxSpendPerEpoch > BigInt(0) ? inf.maxSpendPerEpoch : inf.totalBidAmount;
    const available = inf.totalBidAmount < cap ? inf.totalBidAmount : cap;
    if (available <= BigInt(0)) continue;
    const take = available >= remaining ? remaining : available;
    result.push({ bidder: inf.bidder, assigned: take });
    remaining -= take;
  }

  return result;
};