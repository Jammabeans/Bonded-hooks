// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PoolLaunchPad.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/interfaces/IPoolManager.sol";
import "v4-core/interfaces/IHooks.sol";
import "../src/MasterControl.sol";

/// @notice SeedPools script (small, single-purpose) — creates a few pools and seeds small LP.
/// - This script is intentionally small to avoid compiler "stack too deep" issues.
/// - It reads env vars when present; otherwise falls back to demo addresses for student runs.
///
/// Usage:
///   forge script script/SeedPools.s.sol:SeedPools --rpc-url http://127.0.0.1:8545 --private-key $ANVIL_PRIVATE_KEY --broadcast -vvvv
contract SeedPools is Script {
    // Hardcoded demo addresses (used when env vars not present)
    address internal constant DEMO_MANAGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address internal constant DEMO_POOL_LAUNCHPAD = 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0;
    address internal constant DEMO_MASTER_CONTROL = 0xb00767f80628405Db3b78502Df410A2aeebDbfFF;

    function run() external {
        // Keep run() minimal: read addresses and invoke small helpers
        address managerAddr = vm.envAddress("MANAGER");
        address padAddr = vm.envAddress("POOL_LAUNCHPAD");
        address masterControlAddr = vm.envAddress("MASTER_CONTROL");

        if (managerAddr == address(0)) managerAddr = DEMO_MANAGER;
        if (padAddr == address(0)) padAddr = DEMO_POOL_LAUNCHPAD;
        if (masterControlAddr == address(0)) masterControlAddr = DEMO_MASTER_CONTROL;

        require(managerAddr != address(0) && padAddr != address(0) && masterControlAddr != address(0), "missing core addrs");

        _seedPools(managerAddr, padAddr, masterControlAddr);
    }

    // Small helper that does all pool creations — internal to reduce run() locals
    function _seedPools(address managerAddr, address padAddr, address masterControlAddr) internal {
        vm.startBroadcast();
 
        PoolLaunchPad pad = PoolLaunchPad(payable(padAddr));
        // Best-effort: tell MasterControl about the PoolLaunchPad so initialize hooks accept it.
        MasterControl mc = MasterControl(masterControlAddr);
        (bool ok, ) = address(mc).call(abi.encodeWithSelector(mc.setPoolLaunchPad.selector, padAddr));
        (ok); // silence unused-var warning
 
        // Create pools (no LP seeding to avoid needing token transfers)
        pad.createNewTokenAndInitWithNative("TokenA", "TKA", 1_000_000 ether, 300, 60, uint160(2**96), IHooks(masterControlAddr));
        pad.createNewTokenAndInitWithNative("TokenB", "TKB", 500_000 ether, 300, 60, uint160(2**96), IHooks(masterControlAddr));
        // Create TokenA-2 then TokenC paired with it
        (, address createdA) = pad.createNewTokenAndInitWithNative("TokenA-2", "TKA2", 200_000 ether, 300, 60, uint160(2**96), IHooks(masterControlAddr));
        pad.createNewTokenAndInitWithToken("TokenC", "TKC", 250_000 ether, createdA, 300, 60, uint160(2**96), IHooks(masterControlAddr));
 
        vm.stopBroadcast();
    }

    // Create new token + initialize native pool (no LP seeding)
    function _createTokenAndSeedNative(
        PoolLaunchPad pad,
        address masterControlAddr,
        string memory name,
        string memory symbol,
        uint256 supply,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal returns (address) {
        (, address tokenAddr) = pad.createNewTokenAndInitWithNative(name, symbol, supply, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        return tokenAddr;
    }

    // Create new token paired with an existing token (no LP seeding)
    function _createTokenAndSeedToken(
        PoolLaunchPad pad,
        address masterControlAddr,
        string memory name,
        string memory symbol,
        uint256 supply,
        address otherToken,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal returns (address) {
        (, address tokenAddr) = pad.createNewTokenAndInitWithToken(name, symbol, supply, otherToken, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        return tokenAddr;
    }
}