module.exports = {
  init: async () => {
    // no-op for tests
  },
  unseal: async (val, _type) => {
    // Support test ciphertext shape { _plain: ... }
    if (val && typeof val === "object" && Object.prototype.hasOwnProperty.call(val, "_plain")) {
      return val._plain;
    }
    if (typeof val === "string") return val;
    if (val && typeof val.toString === "function") {
      const s = val.toString();
      if (/^\d+$/.test(s)) return BigInt(s);
      return s;
    }
    return val;
  }
};