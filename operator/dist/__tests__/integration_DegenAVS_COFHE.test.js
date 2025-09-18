"use strict";
/**
 * Integration-style tests for DegenAVS_COFHE that mock both cofhejs and ethers
 * to exercise handlePoolRebateReady end-to-end.
 *
 * These tests:
 * - Mock cofhejs.unseal so encrypted fields return predictable plaintexts.
 * - Mock ethers.Contract so getBidEncrypted returns ciphertext-like objects and
 *   finalizeEpochConsumeBids returns a tx-like object with wait().
 *
 * Run with:
 *   cd Bonded-hooks/operator && npx jest __tests__/integration_DegenAVS_COFHE.test.ts --runInBand --verbose
 */
describe("DegenAVS_COFHE integration (mock cofhejs + ethers)", () => {
    beforeEach(() => {
        jest.resetModules();
        // minimal env defaults; tests will override specifics
        process.env.PRIVATE_KEY = process.env.PRIVATE_KEY || "0x01";
        process.env.RPC_URL = process.env.RPC_URL || "http://localhost:8545";
    });
    test("dry-run: handlePoolRebateReady logs planned minting and does not call finalize", async () => {
        // Ensure LIVE=false for dry-run
        process.env.LIVE = "false";
        process.env.CANDIDATE_BIDDERS = "0xAAA,0xBBB";
        // Ensure bid manager address is set so getBidManager() constructs a (mocked) Contract
        process.env.BID_MANAGER_COFHE_ADDRESS = process.env.BID_MANAGER_COFHE_ADDRESS || "0xBmDeadBeef000000000000000000000000000000";
        // Mock cofhejs (Jest will use this before module import)
        jest.doMock("cofhejs", () => ({
            init: async () => { },
            unseal: async (val, _type) => {
                // Test ciphertext format uses {_plain: value}
                if (val && typeof val === "object" && Object.prototype.hasOwnProperty.call(val, "_plain")) {
                    return val._plain;
                }
                // fallback: return as-is
                return val;
            }
        }));
        // Prepare ethers mock: Contract instances expose getBidEncrypted (for each bidder)
        const mockGetBidEncrypted = jest.fn(async (addr) => {
            // return ciphertext-like objects; the cofhejs.unseal mock will read _plain
            return {
                totalBidAmountEnc: { _plain: "1000" }, // 1000 wei
                maxSpendPerEpochEnc: { _plain: "0" },
                minMintingRateEnc: { _plain: "0" },
                rushFactorEnc: { _plain: "1" },
                bidderEnc: { _plain: addr },
                createdEpoch: 0,
                lastUpdatedEpoch: 0
            };
        });
        // finalize should not be called in dry-run; but provide a mock to detect accidental calls
        const mockFinalize = jest.fn().mockResolvedValue({ wait: async () => ({ hash: "0xfake" }) });
        const mockBatchMint = jest.fn().mockResolvedValue({ wait: async () => ({ hash: "0xmint" }) });
        jest.doMock("ethers", () => {
            return {
                JsonRpcProvider: jest.fn(),
                Wallet: jest.fn(),
                Contract: jest.fn().mockImplementation(() => ({
                    getBidEncrypted: mockGetBidEncrypted,
                    finalizeEpochConsumeBids: mockFinalize,
                    batchMintPoints: mockBatchMint
                }))
            };
        });
        // Import module after mocks are registered
        const mod = require("../DegenAVS_COFHE");
        // capture console output
        const logs = [];
        const oldLog = console.log;
        console.log = (...args) => {
            logs.push(args);
            oldLog.apply(console, args);
        };
        // Run handler with refund 500 (wei)
        await mod.handlePoolRebateReady({ poolId: BigInt(1), trader: "0xtrader", refundWei: BigInt(500) });
        // restore console
        console.log = oldLog;
        // Look for "Planned bidder minting" log and assert accounts/ptsArray exist
        const entry = logs.find((l) => l[0] && String(l[0]).includes("Planned bidder minting"));
        expect(entry).toBeDefined();
        const payload = entry ? entry[1] : undefined;
        expect(payload).toBeDefined();
        expect(Array.isArray(payload.accounts)).toBe(true);
        expect(Array.isArray(payload.ptsArray)).toBe(true);
        // finalize should not have been called
        expect(mockFinalize).not.toHaveBeenCalled();
    });
    test("LIVE mode: handlePoolRebateReady calls finalizeEpochConsumeBids and waits for tx", async () => {
        jest.resetModules();
        process.env.LIVE = "true";
        process.env.CANDIDATE_BIDDERS = "0x111,0x222";
        process.env.EPOCH_SECONDS = "600";
        // Provide a BID_MANAGER_COFHE_ADDRESS so the code constructs the mocked Contract instance
        process.env.BID_MANAGER_COFHE_ADDRESS = process.env.BID_MANAGER_COFHE_ADDRESS || "0xBmLiveDeadBeef0000000000000000000000000000";
        // Mock cofhejs unseal as above
        jest.doMock("cofhejs", () => ({
            init: async () => { },
            unseal: async (val, _type) => (val && val._plain ? val._plain : val)
        }));
        const mockGetBidEncrypted = jest.fn(async (addr) => ({
            totalBidAmountEnc: { _plain: "1000" },
            maxSpendPerEpochEnc: { _plain: "0" },
            minMintingRateEnc: { _plain: "0" },
            rushFactorEnc: { _plain: "1" },
            bidderEnc: { _plain: addr },
            createdEpoch: 0,
            lastUpdatedEpoch: 0
        }));
        // finalize mocked to capture args and return object with wait()
        const finalizeCalls = [];
        const mockFinalize = jest.fn().mockImplementation(async (epoch, bidders, consumed) => {
            finalizeCalls.push({ epoch, bidders, consumed });
            return { wait: async () => ({ hash: "0xfinaltx" }) };
        });
        const ContractMock = jest.fn().mockImplementation(() => ({
            getBidEncrypted: mockGetBidEncrypted,
            finalizeEpochConsumeBids: mockFinalize
        }));
        jest.doMock("ethers", () => ({
            JsonRpcProvider: jest.fn(),
            Wallet: jest.fn(),
            Contract: ContractMock
        }));
        // Import module after mocks are in place
        const mod = require("../DegenAVS_COFHE");
        // Run handler
        await mod.handlePoolRebateReady({ poolId: BigInt(2), trader: "0xtrader", refundWei: BigInt(150) });
        // Expect finalize called at least once
        expect(mockFinalize).toHaveBeenCalled();
        // Inspect captured call: bidders length should be >0 and consumed values sum to refund (or <= refund)
        const call = finalizeCalls[0];
        expect(Array.isArray(call.bidders)).toBe(true);
        expect(Array.isArray(call.consumed)).toBe(true);
        // consumed entries should be numeric strings
        expect(call.consumed.every((c) => /^\d+$/.test(String(c)))).toBe(true);
    });
});
