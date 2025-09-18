import * as dotenv from "dotenv";
dotenv.config();

// Dynamically require `ethers` so Jest module mocks (jest.doMock('ethers', ...))
// can correctly intercept the module during tests. Using runtime require also
// avoids issues when TypeScript can't resolve the module in test runners.
const ethers = (() => {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require("ethers");
  } catch (e) {
    return undefined;
  }
})();

// Load cofhejs at runtime using require so TypeScript/ts-jest won't error on missing typings.
// This also makes Jest module mocks (in __mocks__/cofhejs.js) work correctly.
let cofhejs: any = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  cofhejs = require("cofhejs");
} catch (e) {
  // If cofhejs is not installed in the environment, leave cofhejs=null.
  // Tests using mocks will still work because Jest will mock the module path.
  cofhejs = null;
}

const fs = require("fs");

 // In test environments we allow missing RPC_URL/PRIVATE_KEY; create provider/wallet lazily if available.
let provider: any = null;
let wallet: any = null;
if (process.env.RPC_URL && process.env.PRIVATE_KEY && ethers && ethers.JsonRpcProvider && ethers.Wallet) {
  provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
  wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
} else {
  // don't exit here — tests will mock ethers.Contract or set env vars as needed
  console.warn("RPC_URL/PRIVATE_KEY not set or ethers unavailable — running in limited/dry-run mode");
}

// ABI for COFHE-enabled BidManager (getBidEncrypted) and optional finalize call
const BidManagerCofheABI = [
  "function getBidEncrypted(address) view returns (tuple(eaddress bidderEnc, euint256 totalBidAmountEnc, euint256 maxSpendPerEpochEnc, euint256 minMintingRateEnc, euint32 rushFactorEnc, uint64 createdEpoch, uint64 lastUpdatedEpoch))",
  "function finalizeEpochConsumeBids(uint256 epoch, address[] calldata biddersPlain, uint256[] calldata consumedAmountsPlain) external"
];

// Minimal DegenPool ABI used by operator
const DegenPoolABI = [
  "function batchMintPoints(address[] calldata accounts, uint256[] calldata pts, uint256 epoch) external"
];

const bidManagerAddr = process.env.BID_MANAGER_COFHE_ADDRESS;
// Lazy contract instance — construct when needed to allow tests to mock ethers.Contract before instantiation
let bidManager: any = null;
function getBidManager() {
  if (bidManager) return bidManager;
  if (!bidManagerAddr) return null;
  try {
    const providerOrSigner = wallet || provider || undefined;
    bidManager = new ethers.Contract(bidManagerAddr, BidManagerCofheABI, providerOrSigner);
    return bidManager;
  } catch {
    return null;
  }
}

// DegenPool lazy helper (batch mint points)
const degenPoolAddr = process.env.DEGEN_POOL_ADDRESS;
let degenPool: any = null;
function getDegenPool() {
  if (degenPool) return degenPool;
  if (!degenPoolAddr || !ethers || !ethers.Contract) return null;
  try {
    const providerOrSigner = wallet || provider || undefined;
    degenPool = new ethers.Contract(degenPoolAddr, DegenPoolABI, providerOrSigner);
    return degenPool;
  } catch {
    return null;
  }
}

// GasRebate lazy helper (pushGasPoints)
const gasRebateAddr = process.env.GAS_REBATE_ADDRESS;
const GasRebateABI = [
  "function pushGasPoints(uint256 epoch, address[] calldata users, uint256[] calldata amounts) external"
];
let gasRebate: any = null;
function getGasRebate() {
  if (gasRebate) return gasRebate;
  if (!gasRebateAddr || !ethers || !ethers.Contract) return null;
  try {
    const providerOrSigner = wallet || provider || undefined;
    gasRebate = new ethers.Contract(gasRebateAddr, GasRebateABI, providerOrSigner);
    return gasRebate;
  } catch {
    return null;
  }
}

// Candidate bidders: read from env at runtime so tests can set env before calling handlers
function getCandidateBidders(): string[] {
  return (process.env.CANDIDATE_BIDDERS || "").split(",").map((s) => s.trim()).filter(Boolean);
}

// Points conversion (default same as original operator)
const DEFAULT_POINTS_PER_WEI = BigInt(1_000_000_000_000n);

// Minimal Settings ABI (used to resolve refunds)
const SettingsABI = [
  "function getUint(bytes32) view returns (uint256)",
  "function getHookRefundFor(uint256,address) view returns (uint256)"
];

// Settings contract instance (lazy/optional)
const settingsAddr = process.env.SETTINGS_ADDRESS;
const settings = (settingsAddr && ethers && ethers.Contract) ? new ethers.Contract(settingsAddr, SettingsABI, wallet) : null;

// Settings keys (keccak of names) — compute only if ethers available
const KEY_DEFAULT_REFUND = (ethers && typeof ethers.keccak256 === "function") ? ethers.keccak256(ethers.toUtf8Bytes("defaultRefundWei")) : null;
const KEY_EPOCH_SECONDS = (ethers && typeof ethers.keccak256 === "function") ? ethers.keccak256(ethers.toUtf8Bytes("epochSeconds")) : null;
const KEY_POINTS_PER_WEI = (ethers && typeof ethers.keccak256 === "function") ? ethers.keccak256(ethers.toUtf8Bytes("pointsPerWei")) : null;

// Whether to perform on-chain settlement (finalizeEpochConsumeBids)
const LIVE = (process.env.LIVE || "false").toLowerCase() === "true";

// Resolve refund for a pool using Settings (per-hook override then default)
async function resolveRefundForPool(poolId: bigint, hookAddress?: string): Promise<bigint> {
  if (settings && hookAddress) {
    try {
      const v = await settings.getHookRefundFor(poolId, hookAddress);
      if (v && v.toString() !== "0") return BigInt(v.toString());
    } catch {
      // ignore
    }
  }
  if (settings && KEY_DEFAULT_REFUND) {
    try {
      const v = await settings.getUint(KEY_DEFAULT_REFUND);
      if (v && v.toString() !== "0") return BigInt(v.toString());
    } catch {
      // ignore
    }
  }
  return BigInt(0);
}

function computeEpoch(epochSeconds: number): number {
  const now = Math.floor(Date.now() / 1000);
  return Math.floor(now / epochSeconds);
}

// Helper: safe call to getBidEncrypted and unseal ciphertext fields using cofhejs.unseal
async function readEncryptedBidPlain(bidder: string): Promise<{
  bidderPlain?: string;
  totalBidAmount: bigint;
  maxSpendPerEpoch: bigint;
  minMintingRate: bigint;
  rushFactor: number;
  createdEpoch: number;
  lastUpdatedEpoch: number;
} | null> {
  const bm = getBidManager();
  if (!bm) return null;
  try {
    const res: any = await bm.getBidEncrypted(bidder);
    if (!res) return null;

    // res returns a tuple of ciphertext types; we will attempt to unseal them with cofhejs.unseal
    // Cofhejs API varies; this example uses cofhejs.unseal(value, type) where type is a string
    // In tests with mocks you may use cofhejs.unseal to synchronously reveal values.
    const totalEnc = res.totalBidAmountEnc;
    const maxEnc = res.maxSpendPerEpochEnc;
    const minEnc = res.minMintingRateEnc;
    const rushEnc = res.rushFactorEnc;
    const bidderEnc = res.bidderEnc;

    // Unseal helpers - try/catch each to avoid failing the whole call
    let totalPlain = BigInt(0);
    let maxPlain = BigInt(0);
    let minPlain = BigInt(0);
    let rushPlain = 0;
    let bidderPlainAddr = undefined;

    try {
      // cofhejs.unseal usually returns a JS native value, possibly BigInt for integers
      // Adjust the FheTypes/constants according to your cofhejs setup.
      const t = await cofhejs.unseal(totalEnc, "euint256");
      totalPlain = BigInt(t.toString());
    } catch (err) {
      console.warn(`unseal total for ${bidder} failed:`, err);
      return null;
    }

    try {
      const m = await cofhejs.unseal(maxEnc, "euint256");
      maxPlain = BigInt(m.toString());
    } catch {
      maxPlain = BigInt(0);
    }

    try {
      const mm = await cofhejs.unseal(minEnc, "euint256");
      minPlain = BigInt(mm.toString());
    } catch {
      minPlain = BigInt(0);
    }

    try {
      const r = await cofhejs.unseal(rushEnc, "euint32");
      rushPlain = Number(r);
    } catch {
      rushPlain = 0;
    }

    try {
      const baddr = await cofhejs.unseal(bidderEnc, "eaddress");
      bidderPlainAddr = String(baddr);
    } catch {
      bidderPlainAddr = undefined;
    }

    const createdEpoch = Number(res.createdEpoch ?? 0);
    const lastUpdatedEpoch = Number(res.lastUpdatedEpoch ?? 0);

    return {
      bidderPlain: bidderPlainAddr,
      totalBidAmount: totalPlain,
      maxSpendPerEpoch: maxPlain,
      minMintingRate: minPlain,
      rushFactor: rushPlain,
      createdEpoch,
      lastUpdatedEpoch
    };
  } catch (err) {
    console.error("readEncryptedBidPlain error:", err);
    return null;
  }
}

// Matching algorithm (same semantics as original DegenAVS.ts)
// - Filters zero totalBidAmount
// - Sorts by (rushFactor desc, totalBidAmount desc)
// - For each bidder assign assignable = min(totalBidAmount, maxSpendPerEpoch || totalBidAmount, remaining)
// - Stop when remaining covered
export function matchBiddersFromInfos(
  infosInput: {
    bidder: string;
    totalBidAmount: bigint;
    maxSpendPerEpoch: bigint;
    minMintingRate: bigint;
    rushFactor: number;
    createdEpoch: number;
    lastUpdatedEpoch: number;
  }[],
  amountWei: bigint
): { bidder: string; assigned: bigint }[] {
  const infos = [...infosInput];

  // Sort by rushFactor desc then totalBidAmount desc
  infos.sort((a: any, b: any) => {
    if (b.rushFactor !== a.rushFactor) return b.rushFactor - a.rushFactor;
    if (b.totalBidAmount !== a.totalBidAmount) return (b.totalBidAmount > a.totalBidAmount) ? 1 : -1;
    return 0;
  });

  let remaining = amountWei;
  const result: { bidder: string; assigned: bigint }[] = [];

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
}

async function matchBiddersForAmount(amountWei: bigint): Promise<{ bidder: string; assigned: bigint }[]> {
  const candidates = getCandidateBidders();
  if (candidates.length === 0) return [];

  const infos: {
    bidder: string;
    totalBidAmount: bigint;
    maxSpendPerEpoch: bigint;
    minMintingRate: bigint;
    rushFactor: number;
    createdEpoch: number;
    lastUpdatedEpoch: number;
  }[] = [];

  for (const addr of candidates) {
    const info = await readEncryptedBidPlain(addr);
    if (info && info.totalBidAmount > BigInt(0)) {
      infos.push({
        bidder: addr,
        totalBidAmount: info.totalBidAmount,
        maxSpendPerEpoch: info.maxSpendPerEpoch,
        minMintingRate: info.minMintingRate,
        rushFactor: info.rushFactor,
        createdEpoch: info.createdEpoch,
        lastUpdatedEpoch: info.lastUpdatedEpoch
      });
    } else {
      // skip bidders we couldn't read/unseal or zero bids
    }
  }

  return matchBiddersFromInfos(infos, amountWei);
}

// Convert assigned Wei -> points using pointsPerWei (default fallback)
async function readPointsPerWei(): Promise<bigint> {
  // This operator does not rely on on-chain Settings for COFHE example.
  // Use env override POINTS_PER_WEI (in wei units) or default.
  if (process.env.POINTS_PER_WEI) {
    try {
      return BigInt(process.env.POINTS_PER_WEI);
    } catch {
      return DEFAULT_POINTS_PER_WEI;
    }
  }
  return DEFAULT_POINTS_PER_WEI;
}

// Primary handler: given an event-like payload (poolId, trader, refundWei) compute bidder matches and (optionally) call finalize
export async function handlePoolRebateReady(payload: {
  poolId: bigint;
  trader: string;
  refundWei: bigint;
  baseGasPrice?: string | number;
}) {
  try {
    console.log("COFHE AVS handling PoolRebateReady:", payload);

    // Determine refund: prefer payload.refundWei if provided, otherwise resolve via Settings
    let refundWei: bigint = BigInt(0);
    if (payload.refundWei !== undefined && payload.refundWei !== null) {
      refundWei = BigInt(payload.refundWei);
    } else {
      const pid = BigInt(payload.poolId);
      refundWei = await resolveRefundForPool(pid, undefined);
    }
    if (refundWei === BigInt(0)) {
      console.log("No refund configured; skipping");
      return;
    }

    // compute epoch (use env override or Settings)
    let epochSeconds = 600;
    if (settings && KEY_EPOCH_SECONDS) {
      try {
        const es = await settings.getUint(KEY_EPOCH_SECONDS);
        if (es && es.toString() !== "0") epochSeconds = Number(es.toString());
      } catch {
        // ignore
      }
    } else if (process.env.EPOCH_SECONDS) {
      epochSeconds = Number(process.env.EPOCH_SECONDS);
    }
    const epoch = computeEpoch(epochSeconds);

    // push gas points to trader (preserve original AVS behavior)
    // Prefer the lazy helper, but fall back to constructing a contract instance if needed.
    let gr: any = null;
    try {
      gr = getGasRebate();
    } catch {
      gr = null;
    }
    if (!gr && process.env.GAS_REBATE_ADDRESS && ethers && ethers.Contract) {
      try {
        gr = new ethers.Contract(process.env.GAS_REBATE_ADDRESS, GasRebateABI, wallet || provider);
      } catch {
        gr = null;
      }
    }

    if (gr) {
      try {
        console.log(`pushGasPoints epoch=${epoch}, trader=${payload.trader}, amount=${refundWei.toString()}`);
        const tx = await gr.pushGasPoints(epoch, [payload.trader], [refundWei.toString()]);
        await tx.wait();
        console.log("pushGasPoints tx:", tx.hash);
      } catch (err) {
        console.error("pushGasPoints failed:", err);
      }
    } else {
      console.warn("GasRebateManager not configured");
    }

    // match bidders with encrypted data
    const matches = await matchBiddersForAmount(refundWei);
    if (!matches || matches.length === 0) {
      console.log("No bidders matched for refund; skipping bidder rewards");
      return;
    }

    const pointsPerWei = await readPointsPerWei();
    const accounts: string[] = [];
    const ptsArray: string[] = [];
    const biddersPlain: string[] = [];
    const consumedAmounts: string[] = [];

    for (const m of matches) {
      const pts = (m.assigned * pointsPerWei);
      if (pts > BigInt(0)) {
        accounts.push(m.bidder);
        ptsArray.push(pts.toString());
      }
      // For settlement: we report consumedAmounts equal to assigned wei
      biddersPlain.push(m.bidder);
      consumedAmounts.push(m.assigned.toString());
    }

    // Dry-run logging for minting points
    console.log("Planned bidder minting:", { accounts, ptsArray });

    // Attempt to mint points to matched bidders (if degenPool configured)
    const dp = getDegenPool();
    if (accounts.length > 0 && dp) {
      try {
        console.log("batchMintPoints to bidders:", accounts, "pts:", ptsArray, "epoch:", epoch);
        const tx = await dp.batchMintPoints(accounts, ptsArray, epoch);
        await tx.wait();
        console.log("batchMintPoints tx:", tx.hash);
      } catch (err) {
        console.error("batchMintPoints failed:", err);
      }
    } else {
      console.log("No bidders to mint or degenPool not configured");
    }

    if (LIVE) {
      const bm = getBidManager();
      if (!bm) {
        console.error("LIVE mode enabled but BID_MANAGER_COFHE_ADDRESS or provider not configured");
      } else {
        try {
          console.log("Calling finalizeEpochConsumeBids on chain:", { epoch, biddersPlain, consumedAmounts });
          const tx = await bm.finalizeEpochConsumeBids(
            epoch,
            biddersPlain,
            consumedAmounts.map((s) => BigInt(s).toString())
          );
          await tx.wait();
          console.log("finalizeEpochConsumeBids tx:", tx.hash);
        } catch (err) {
          console.error("finalizeEpochConsumeBids failed:", err);
        }
      }
    } else {
      console.log("Not in LIVE mode; skipping on-chain finalize. Set LIVE=true to enable.");
    }

    // The AVS could also call a minting contract (DegenPool) if available — left as an exercise and kept dry by default.
  } catch (err) {
    console.error("Error in handlePoolRebateReady:", err);
  }
}

// Simple CLI runner to process a single synthetic event (useful for local testing)
async function main() {
  // initialize cofhejs if available (real runtime or Jest mock)
  try {
    if (cofhejs && typeof cofhejs.init === "function") {
      await cofhejs.init();
    }
  } catch (err) {
    console.warn("cofhejs.init warning:", err);
  }

  // Example: accept a JSON payload file path via env or default to a sample
  const inputPath = process.env.EVENT_JSON || "";
  if (inputPath) {
    try {
      const raw = fs.readFileSync(inputPath, "utf8");
      const payload = JSON.parse(raw);
      // Expect payload.refundWei to be a decimal string or number
      payload.refundWei = BigInt(payload.refundWei || 0);
      await handlePoolRebateReady(payload);
      process.exit(0);
    } catch (err) {
      console.error("Failed to run from EVENT_JSON:", err);
      process.exit(1);
    }
  } else {
    // Interactive dry-run example: consume 0.01 ether as refund and run matching
    const sampleRefund = BigInt(10 ** 16); // 0.01 ETH in wei
    await handlePoolRebateReady({ poolId: BigInt(1), trader: "0x0000000000000000000000000000000000000000", refundWei: sampleRefund });
    process.exit(0);
  }
}

if (require.main === module) {
  main();
}