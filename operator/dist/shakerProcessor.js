"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.toHexCanonical = toHexCanonical;
exports.choosePool = choosePool;
exports.chooseBoxIds = chooseBoxIds;
exports.pickBoxToAward = pickBoxToAward;
exports.seedToBigInt = seedToBigInt;
const ethers_1 = require("ethers");
/**
 * Convert a BigLike to a canonical hex string for deterministic hashing.
 */
function toHexCanonical(v) {
    if (typeof v === "bigint")
        return "0x" + v.toString(16);
    if (typeof v === "number")
        return "0x" + BigInt(v).toString(16);
    if (typeof v === "string") {
        if (v.startsWith("0x"))
            return v;
        // try numeric string
        if (/^\d+$/.test(v))
            return "0x" + BigInt(v).toString(16);
        return v;
    }
    return String(v);
}
/**
 * Choose a pool id from the provided list.
 * - If candidates is empty throws.
 * - Uses simple pseudo-random selection based on optional seed; otherwise random from Math.random.
 *
 * Returns the chosen poolId as the same type as the candidate element (string/number/bigint).
 */
function choosePool(candidates, seed) {
    if (!candidates || candidates.length === 0)
        throw new Error("no candidate pools");
    if (candidates.length === 1)
        return candidates[0];
    if (seed) {
        // deterministic choice: hash seed + index and pick highest hash
        const scored = candidates.map((c, i) => {
            const h = ethers_1.ethers.keccak256(ethers_1.ethers.toUtf8Bytes(`${seed}:${i}:${toHexCanonical(c)}`));
            // take first 8 bytes as number for comparison
            const score = BigInt(h.slice(0, 18));
            return { c, score };
        });
        scored.sort((a, b) => (a.score > b.score ? -1 : a.score < b.score ? 1 : 0));
        return scored[0].c;
    }
    else {
        const idx = Math.floor(Math.random() * candidates.length);
        return candidates[idx];
    }
}
/**
 * Deterministically choose up to `count` boxIds from `candidateBoxIds`.
 * - If count >= candidateBoxIds.length, returns a copy of candidateBoxIds.
 * - Selection is deterministic when `seed` is provided.
 *
 * Implementation: compute keccak256(seed + boxId) for each candidate, sort by hash desc, take top `count`.
 */
function chooseBoxIds(candidateBoxIds, opts) {
    const count = opts?.count ?? 1;
    if (!candidateBoxIds || candidateBoxIds.length === 0)
        return [];
    if (count >= candidateBoxIds.length)
        return candidateBoxIds.slice();
    const seed = opts?.seed ?? Math.random().toString(36);
    const scored = candidateBoxIds.map((b, i) => {
        const h = ethers_1.ethers.keccak256(ethers_1.ethers.toUtf8Bytes(`${seed}:${i}:${toHexCanonical(b)}`));
        // Convert first 16 hex chars to bigint for sorting (avoid full bigint from 0x...)
        const score = BigInt(h.slice(0, 18));
        return { b, score };
    });
    scored.sort((a, b) => (a.score > b.score ? -1 : a.score < b.score ? 1 : 0));
    return scored.slice(0, count).map((s) => s.b);
}
/**
 * Given the data returned by an on-chain finalize (or by recomputing the on-chain pseudo-random split),
 * choose a single boxId to award to the winner. Strategy:
 * - Prefer boxes that received a non-zero ETH deposit (if that info is provided)
 * - Otherwise pick one of the provided boxIds deterministically via seed
 *
 * The runtime AVS will usually call Shaker.finalizeRound with boxIds+seed, then query PrizeBox box balances
 * and pass that info into this helper to pick a box that actually received funds.
 */
function pickBoxToAward(boxIds, boxEthBalances, seed) {
    if (!boxIds || boxIds.length === 0)
        return null;
    // Prefer an index with balance > 0 (first such). If multiple, pick deterministic by hashing.
    if (boxEthBalances && boxEthBalances.length === boxIds.length) {
        const nonZero = [];
        for (let i = 0; i < boxIds.length; i++) {
            const bal = BigInt(boxEthBalances[i] ? boxEthBalances[i] : 0);
            if (bal > BigInt(0))
                nonZero.push({ idx: i, b: boxIds[i] });
        }
        if (nonZero.length === 1)
            return nonZero[0].b;
        if (nonZero.length > 1) {
            // deterministically choose among nonZero using seed
            const s = seed ?? "pick:" + nonZero.map((n) => toHexCanonical(n.b)).join(",");
            const scored = nonZero.map((n, i) => {
                const h = ethers_1.ethers.keccak256(ethers_1.ethers.toUtf8Bytes(`${s}:${i}:${toHexCanonical(n.b)}`));
                const score = BigInt(h.slice(0, 18));
                return { n, score };
            });
            scored.sort((a, b) => (a.score > b.score ? -1 : a.score < b.score ? 1 : 0));
            return scored[0].n.b;
        }
    }
    // Fallback: deterministic pick from boxIds using seed
    const chosen = chooseBoxIds(boxIds, { seed, count: 1 });
    return chosen.length > 0 ? chosen[0] : null;
}
/**
 * Utility: deterministic numeric seed from string (returns bigint).
 */
function seedToBigInt(seed) {
    const s = seed ?? Math.random().toString(36);
    const h = ethers_1.ethers.keccak256(ethers_1.ethers.toUtf8Bytes(s));
    // use first 8 bytes
    return BigInt(h.slice(0, 18));
}
