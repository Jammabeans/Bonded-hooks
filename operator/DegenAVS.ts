import { ethers } from "ethers";
import * as dotenv from "dotenv";
const fs = require("fs");
const path = require("path");
dotenv.config();

if (!process.env.RPC_URL || !process.env.PRIVATE_KEY) {
  console.error("Set RPC_URL and PRIVATE_KEY in .env");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

// Minimal ABIs for on-chain calls we need
const MasterControlABI = [
  "event PoolRebateReady(address indexed txOrigin, address indexed trader, uint256 indexed poolId, uint256 poolTotalFeeBips, uint256 baseGasPrice)"
];

const SettingsABI = [
  "function getUint(bytes32) view returns (uint256)",
  "function getHookRefundFor(uint256,address) view returns (uint256)"
];

const GasRebateABI = [
  "function pushGasPoints(uint256 epoch, address[] calldata users, uint256[] calldata amounts) external"
];

const BidManagerABI = [
  "function getBid(address bidder) view returns (tuple(address bidder, uint256 totalBidAmount, uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor, uint64 createdEpoch, uint64 lastUpdatedEpoch))"
];

const DegenPoolABI = [
  "function batchMintPoints(address[] calldata accounts, uint256[] calldata pts, uint256 epoch) external"
];

const masterAddr = process.env.MASTER_CONTROL_ADDRESS;
if (!masterAddr) {
  console.error("Set MASTER_CONTROL_ADDRESS in .env or env");
  process.exit(1);
}
const master = new ethers.Contract(masterAddr, MasterControlABI, wallet);

const settingsAddr = process.env.SETTINGS_ADDRESS;
const settings = settingsAddr ? new ethers.Contract(settingsAddr, SettingsABI, wallet) : null;

const gasRebateAddr = process.env.GAS_REBATE_ADDRESS;
const gasRebate = gasRebateAddr ? new ethers.Contract(gasRebateAddr, GasRebateABI, wallet) : null;

const bidManagerAddr = process.env.BID_MANAGER_ADDRESS;
const bidManager = bidManagerAddr ? new ethers.Contract(bidManagerAddr, BidManagerABI, wallet) : null;

const degenPoolAddr = process.env.DEGEN_POOL_ADDRESS;
const degenPool = degenPoolAddr ? new ethers.Contract(degenPoolAddr, DegenPoolABI, wallet) : null;

// Candidate bidders: comma-separated env var of addresses
const candidateBidders = (process.env.CANDIDATE_BIDDERS || "").split(",").map((s) => s.trim()).filter(Boolean);

// Settings keys
const KEY_DEFAULT_REFUND = ethers.keccak256(ethers.toUtf8Bytes("defaultRefundWei"));
const KEY_EPOCH_SECONDS = ethers.keccak256(ethers.toUtf8Bytes("epochSeconds"));
const KEY_POINTS_PER_WEI = ethers.keccak256(ethers.toUtf8Bytes("pointsPerWei"));

// Helpers
async function resolveRefundForPool(poolId: bigint, hookAddress?: string): Promise<bigint> {
  if (settings && hookAddress) {
    try {
      const v = await settings.getHookRefundFor(poolId, hookAddress);
      if (v && v.toString() !== "0") return BigInt(v.toString());
    } catch {
      // ignore
    }
  }
  if (settings) {
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

// Read bidder info from BidManager
async function readBidInfo(bidder: string) {
  if (!bidManager) return null;
  try {
    const bid: any = await bidManager.getBid(bidder);
    // Normalize to BigInt / numbers
    return {
      bidder: bid.bidder,
      totalBidAmount: BigInt(bid.totalBidAmount.toString()),
      maxSpendPerEpoch: BigInt(bid.maxSpendPerEpoch.toString()),
      minMintingRate: BigInt(bid.minMintingRate.toString()),
      rushFactor: Number(bid.rushFactor),
      createdEpoch: Number(bid.createdEpoch),
      lastUpdatedEpoch: Number(bid.lastUpdatedEpoch)
    };
  } catch (err) {
    return null;
  }
}

// Smarter matching algorithm:
// - Query candidate bidders
// - Filter out bidders with zero totalBidAmount
// - Sort by (rushFactor desc, totalBidAmount desc)
// - For each bidder assign assignable = min(totalBidAmount, maxSpendPerEpoch, remaining)
// - Stop when remaining covered
async function matchBiddersForAmount(amountWei: bigint): Promise<{ bidder: string; assigned: bigint }[]> {
  if (!bidManager || candidateBidders.length === 0) return [];

  const infos: {
    bidder: string;
    totalBidAmount: bigint;
    maxSpendPerEpoch: bigint;
    minMintingRate: bigint;
    rushFactor: number;
    createdEpoch: number;
    lastUpdatedEpoch: number;
  }[] = [];
  for (const addr of candidateBidders) {
    const info = await readBidInfo(addr);
    if (info && info.totalBidAmount > BigInt(0)) infos.push(info);
  }

  // Sort
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

// Read pointsPerWei from settings or fallback default
async function readPointsPerWei(): Promise<bigint> {
  if (settings) {
    try {
      const v = await settings.getUint(KEY_POINTS_PER_WEI);
      if (v && v.toString() !== "0") return BigInt(v.toString());
    } catch {
      // ignore
    }
  }
  // default conversion: 1 point per 1e12 wei (same as earlier)
  return BigInt(1_000_000_000_000n);
}

master.on("PoolRebateReady", async (txOrigin: string, trader: string, poolId: ethers.BigNumberish, poolTotalFeeBips: ethers.BigNumberish, baseGasPrice: ethers.BigNumberish, event: any) => {
  try {
    const pid = BigInt(poolId.toString());
    console.log("PoolRebateReady:", { txOrigin, trader, poolId: pid.toString(), poolTotalFeeBips: poolTotalFeeBips.toString(), baseGasPrice: baseGasPrice.toString() });

    const refundWei = await resolveRefundForPool(pid, undefined);
    if (refundWei === BigInt(0)) {
      console.log("No refund configured; skipping");
      return;
    }

    // epoch
    let epochSeconds = 600;
    if (settings) {
      try {
        const es = await settings.getUint(KEY_EPOCH_SECONDS);
        if (es && es.toString() !== "0") epochSeconds = Number(es.toString());
      } catch {
        // ignore
      }
    }
    const epoch = computeEpoch(epochSeconds);

    // push gas points to trader
    if (gasRebate) {
      try {
        console.log(`pushGasPoints epoch=${epoch}, trader=${trader}, amount=${refundWei.toString()}`);
        const tx = await gasRebate.pushGasPoints(epoch, [trader], [refundWei.toString()]);
        await tx.wait();
        console.log("pushGasPoints tx:", tx.hash);
      } catch (err) {
        console.error("pushGasPoints failed:", err);
      }
    } else {
      console.warn("GasRebateManager not configured");
    }

    // Smart bidder matching
    const matches = await matchBiddersForAmount(refundWei);
    if (matches.length === 0) {
      console.log("No bidders matched for refund; skipping bidder rewards");
      return;
    }

    // Compute pointsPerWei and mint to matched bidders proportional to assigned amounts
    const pointsPerWei = await readPointsPerWei(); // bigint
    const accounts: string[] = [];
    const ptsArray: string[] = [];
    for (const m of matches) {
      const pts = (m.assigned * pointsPerWei);
      // Only mint non-zero points
      if (pts > BigInt(0)) {
        accounts.push(m.bidder);
        ptsArray.push(pts.toString());
      }
    }

    if (accounts.length > 0 && degenPool) {
      try {
        console.log("batchMintPoints to bidders:", accounts, "pts:", ptsArray, "epoch:", epoch);
        const tx = await degenPool.batchMintPoints(accounts, ptsArray, epoch);
        await tx.wait();
        console.log("batchMintPoints tx:", tx.hash);
      } catch (err) {
        console.error("batchMintPoints failed:", err);
      }
    } else {
      console.log("No bidders to mint or degenPool not configured");
    }
  } catch (err) {
    console.error("Error processing PoolRebateReady:", err);
  }
});

process.on("SIGINT", () => {
  console.log("Shutting down DegenAVS...");
  process.exit(0);
});

console.log("DegenAVS operator running and listening for PoolRebateReady events");