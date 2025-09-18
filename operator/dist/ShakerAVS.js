"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const ethers_1 = require("ethers");
const dotenv = __importStar(require("dotenv"));
const shakerProcessor_1 = require("./shakerProcessor");
dotenv.config();
if (!process.env.RPC_URL || !process.env.PRIVATE_KEY) {
    console.error("Set RPC_URL and PRIVATE_KEY in .env");
    process.exit(1);
}
const provider = new ethers_1.ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers_1.ethers.Wallet(process.env.PRIVATE_KEY, provider);
const shakerAddr = process.env.SHAKER_ADDRESS;
const prizeBoxAddr = process.env.PRIZEBOX_ADDRESS;
if (!shakerAddr) {
    console.error("Set SHAKER_ADDRESS in .env");
    process.exit(1);
}
const SHAKER_ABI = [
    "event RoundStarted(uint256 indexed roundId, uint256 indexed poolId, uint256 startTs, uint256 deadline, uint256 ticketPrice)",
    "function startRound(uint256 poolId) returns (uint256)",
    "function finalizeRound(uint256 roundId, uint256[] calldata boxIds, uint256 seed) external",
    "function awardWinnerBox(uint256 roundId, uint256 boxId) external",
    "function rounds(uint256) view returns (uint256 roundId,uint256 poolId,uint256 startTs,uint256 deadline,address leader,uint256 pot,uint256 ticketCount,uint256 ticketPrice,bool finalized)"
];
const PRIZEBOX_ABI = [
    "function boxes(uint256) view returns (bool opened, uint256 ethBalance)",
    "function ownerOf(uint256) view returns (address)"
];
const shaker = new ethers_1.ethers.Contract(shakerAddr, SHAKER_ABI, wallet);
const prizeBox = prizeBoxAddr ? new ethers_1.ethers.Contract(prizeBoxAddr, PRIZEBOX_ABI, wallet) : null;
// env lists converted to bigint arrays
const candidatePools = (process.env.CANDIDATE_POOLS || "")
    .split(",")
    .map(s => s.trim())
    .filter(Boolean)
    .map(s => BigInt(s));
const candidateBoxIds = (process.env.CANDIDATE_BOXES || "")
    .split(",")
    .map(s => s.trim())
    .filter(Boolean)
    .map(s => BigInt(s));
const minInterval = Number(process.env.MIN_INTERVAL_SECONDS || "30");
const maxInterval = Number(process.env.MAX_INTERVAL_SECONDS || "120");
const dryRun = !!process.env.DRY_RUN;
const boxCountPerRound = Number(process.env.BOXES_PER_ROUND || "1");
const bufferSeconds = Number(process.env.FINALIZE_BUFFER_SECONDS || "5");
if (candidatePools.length === 0) {
    console.warn("No CANDIDATE_POOLS configured; operator will not start rounds automatically");
}
function randomInterval() {
    if (minInterval >= maxInterval)
        return minInterval;
    return Math.floor(Math.random() * (maxInterval - minInterval + 1)) + minInterval;
}
async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
async function startRoundOnPool(poolId) {
    console.log("Starting round for pool", poolId.toString());
    if (dryRun) {
        try {
            const rid = await shaker.callStatic.startRound(poolId);
            console.log("[dry-run] would start roundId", BigInt(rid.toString()).toString());
            return BigInt(rid.toString());
        }
        catch (err) {
            console.error("[dry-run] callStatic.startRound failed:", err);
            return BigInt(0);
        }
    }
    try {
        const tx = await shaker.startRound(poolId);
        const rcpt = await tx.wait();
        // Try parse RoundStarted event from receipt
        const iface = new ethers_1.ethers.Interface(SHAKER_ABI);
        for (const log of rcpt.logs) {
            try {
                const parsed = iface.parseLog(log);
                if (parsed && parsed.name === "RoundStarted") {
                    const rid = BigInt(parsed.args.roundId.toString());
                    console.log("RoundStarted event rid=", rid.toString());
                    return rid;
                }
            }
            catch {
                // ignore non-matching logs
            }
        }
        // Fallback: callStatic
        const rid2 = await shaker.callStatic.startRound(poolId);
        return BigInt(rid2.toString());
    }
    catch (err) {
        console.error("startRound tx failed:", err);
        return BigInt(0);
    }
}
async function getRoundDeadline(roundId) {
    try {
        const r = await shaker.rounds(roundId);
        return Number(r.deadline.toString());
    }
    catch (err) {
        console.error("failed to read round:", err);
        return null;
    }
}
async function finalizeRound(roundId, boxIds, seed) {
    console.log("Finalizing round", roundId.toString(), "with boxes", boxIds.map(b => b.toString()), "seed", seed.toString());
    if (dryRun) {
        console.log("[dry-run] would call finalizeRound");
        return;
    }
    try {
        const tx = await shaker.finalizeRound(roundId, boxIds, seed);
        await tx.wait();
        console.log("finalizeRound tx sent");
    }
    catch (err) {
        console.error("finalizeRound failed:", err);
    }
}
async function queryBoxBalances(boxIds) {
    if (!prizeBox)
        return boxIds.map(_ => BigInt(0));
    const balances = [];
    for (const id of boxIds) {
        try {
            const b = await prizeBox.boxes(id);
            balances.push(BigInt(b.ethBalance.toString()));
        }
        catch (err) {
            console.error("failed to read box", id.toString(), err);
            balances.push(BigInt(0));
        }
    }
    return balances;
}
async function awardBox(shakerRoundId, boxId) {
    console.log("Awarding box", boxId.toString(), "for round", shakerRoundId.toString());
    if (dryRun) {
        console.log("[dry-run] would call awardWinnerBox");
        return;
    }
    try {
        const tx = await shaker.awardWinnerBox(shakerRoundId, boxId);
        await tx.wait();
        console.log("awardWinnerBox tx sent");
    }
    catch (err) {
        console.error("awardWinnerBox failed:", err);
    }
}
async function runLoop() {
    console.log("ShakerAVS starting loop. dryRun=", dryRun);
    while (true) {
        try {
            const interval = randomInterval();
            console.log("Sleeping", interval, "seconds before next round");
            await sleep(interval * 1000);
            if (candidatePools.length === 0)
                continue;
            // choose pool (deterministic-ish using timestamp seed)
            const pool = (0, shakerProcessor_1.choosePool)(candidatePools, Date.now().toString());
            const rid = await startRoundOnPool(pool);
            if (!rid || rid === BigInt(0))
                continue;
            const deadline = await getRoundDeadline(rid);
            if (!deadline)
                continue;
            const now = Math.floor(Date.now() / 1000);
            let waitSecs = deadline - now + bufferSeconds;
            if (waitSecs < 0)
                waitSecs = bufferSeconds;
            console.log("Round", rid.toString(), "deadline at", deadline, "waiting", waitSecs, "seconds");
            await sleep(waitSecs * 1000);
            // choose boxes to send to finalize
            const chosenBoxesRaw = (0, shakerProcessor_1.chooseBoxIds)(candidateBoxIds.map(b => b), { seed: Date.now().toString(), count: boxCountPerRound });
            const chosenBoxes = chosenBoxesRaw.map((b) => BigInt(b));
            const seed = (0, shakerProcessor_1.seedToBigInt)(Date.now().toString());
            await finalizeRound(rid, chosenBoxes, seed);
            // small delay for on-chain deposits to be registered
            await sleep(2000);
            // query balances
            const balances = await queryBoxBalances(chosenBoxes);
            const boxToAward = (0, shakerProcessor_1.pickBoxToAward)(chosenBoxes.map(b => b), balances.map(b => b), seed.toString());
            if (boxToAward === null) {
                console.log("No box chosen to award");
                continue;
            }
            await awardBox(rid, BigInt(boxToAward));
        }
        catch (err) {
            console.error("loop error:", err);
        }
    }
}
process.on("SIGINT", () => {
    console.log("Shutting down ShakerAVS...");
    process.exit(0);
});
runLoop().catch((e) => {
    console.error("fatal:", e);
    process.exit(1);
});
