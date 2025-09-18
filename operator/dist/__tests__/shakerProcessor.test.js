"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const shakerProcessor_1 = require("../shakerProcessor");
describe("shakerProcessor helpers", () => {
    test("chooseBoxIds is deterministic with seed", () => {
        const boxes = [1, 2, 3, 4, 5];
        const seed = "myseed";
        const a = (0, shakerProcessor_1.chooseBoxIds)(boxes, { seed, count: 2 });
        const b = (0, shakerProcessor_1.chooseBoxIds)(boxes, { seed, count: 2 });
        expect(a).toEqual(b);
        expect(a.length).toBe(2);
        expect(a[0]).not.toBeUndefined();
    });
    test("choosePool is deterministic with seed", () => {
        const pools = [10, 20, 30];
        const seed = "poolseed";
        const p1 = (0, shakerProcessor_1.choosePool)(pools, seed);
        const p2 = (0, shakerProcessor_1.choosePool)(pools, seed);
        expect(p1).toBe(p2);
    });
    test("pickBoxToAward prefers non-zero balances", () => {
        const boxes = [1, 2, 3];
        const balances = [BigInt(0), BigInt(100), BigInt(0)];
        const picked = (0, shakerProcessor_1.pickBoxToAward)(boxes, balances, "s");
        expect(picked).toBe(2);
    });
    test("pickBoxToAward deterministic among non-zero", () => {
        const boxes = [1, 2, 3, 4];
        const balances = [BigInt(50), BigInt(50), BigInt(0), BigInt(50)];
        const seed = "tie-seed";
        const first = (0, shakerProcessor_1.pickBoxToAward)(boxes, balances, seed);
        const second = (0, shakerProcessor_1.pickBoxToAward)(boxes, balances, seed);
        expect(first).toBe(second);
    });
    test("seedToBigInt is stable", () => {
        const s = "abc-123";
        const v1 = (0, shakerProcessor_1.seedToBigInt)(s);
        const v2 = (0, shakerProcessor_1.seedToBigInt)(s);
        expect(v1).toBe(v2);
        expect(typeof v1 === "bigint" || typeof v1 === "number").toBe(true);
    });
});
