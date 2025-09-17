// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "./Deploy.s.sol";
import {PoolLaunchPad, ERC20Deployer} from "../src/PoolLaunchPad.sol";
import "../src/BidManager.sol";
import "../src/Bonding.sol";
import "v4-core/interfaces/IHooks.sol";

// Use the same imports the tests use (remappings provide these)
import "v4-core/test/PoolModifyLiquidityTest.sol";
import "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import "v4-core/libraries/TickMath.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/types/PoolId.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import "v4-core/interfaces/IPoolManager.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/MasterControl.sol";
import "../src/AccessControl.sol";

/// @notice SetupDefaults script: create a set of sample pools, create bids from two EOAs,
/// and deposit some native bonds to a PointsCommand target to seed local dev state.
///
/// Environment variables expected:
/// - MANAGER
/// - POOL_LAUNCHPAD
/// - BID_MANAGER
/// - BONDING
/// - POINTS_COMMAND
/// - FUNDING_KEY_1 (hex or decimal private key for bidder1)
/// - FUNDING_KEY_2 (hex or decimal private key for bidder2)
///
/// Usage:
///   export FUNDING_KEY_1="0x...."
///   export FUNDING_KEY_2="0x...."
///   forge script script/SetupDefaults.s.sol:SetupDefaults --rpc-url http://127.0.0.1:8545 --private-key $ANVIL_PRIVATE_KEY --broadcast -vvvv
contract SetupDefaults is Script {

    // Small helper to perform a native bond deposit using a potentially different EOA key.
    // For the demo we use the hard-coded Bonding / PointsCommand addresses.
    function _doDepositBond(uint256 bondKey) internal {
        address bondingAddr = address(0x59b670e9fA9D0A427751Af201D676719a970857b);
        address target = address(0x809d550fca64d94Bd9F66E60752A544199cfAC3D);
        if (bondKey == 0) {
            vm.startBroadcast();
            Bonding(payable(bondingAddr)).depositBondNative{value: 0.5 ether}(target);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(bondKey);
            Bonding(payable(bondingAddr)).depositBondNative{value: 0.5 ether}(target);
            vm.stopBroadcast();
        }
    }
// Helpers that encapsulate per-pool locals so the main _seed() function stays small.
// Each helper deploys/initializes a pool and adds a small LP position using the supplied modifyRouter.

function _seedNewTokenNative(
    PoolLaunchPad pad,
    PoolModifyLiquidityTest modifyRouter,
    address masterControlAddr,
    string memory name,
    string memory symbol,
    uint256 supply,
    uint24 fee,
    int24 tickSpacing,
    uint160 sqrtPriceX96,
    uint256 ethToAdd
) internal returns (address tokenAddr) {
    (, tokenAddr) = pad.createNewTokenAndInitWithNative(name, symbol, supply, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
    // Transfer minted tokens from the launchpad to this script contract so we can approve/use them
    vm.prank(address(pad));
    ERC20(tokenAddr).transfer(address(this), supply);
    // approve modify router and add small native liquidity
    ERC20(tokenAddr).approve(address(modifyRouter), type(uint256).max);
    PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(tokenAddr), fee, tickSpacing, IHooks(masterControlAddr));
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
    uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, ethToAdd);
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
        tickLower: int24(-60),
        tickUpper: int24(60),
        liquidityDelta: int256(uint256(liquidityDelta)),
        salt: bytes32(0)
    });
    modifyRouter.modifyLiquidity{value: ethToAdd}(key, params, "");
    return tokenAddr;
}

function _seedNewTokenTokenPair(
    PoolLaunchPad pad,
    PoolModifyLiquidityTest modifyRouter,
    address masterControlAddr,
    string memory name,
    string memory symbol,
    uint256 supply,
    address otherToken,
    uint24 fee,
    int24 tickSpacing,
    uint160 sqrtPriceX96,
    uint256 ethToAdd
) internal returns (address tokenAddr) {
    (, tokenAddr) = pad.createNewTokenAndInitWithToken(name, symbol, supply, otherToken, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
    // Transfer minted tokens from the launchpad to this script contract so we can approve/use them
    vm.prank(address(pad));
    ERC20(tokenAddr).transfer(address(this), supply);
    ERC20(tokenAddr).approve(address(modifyRouter), type(uint256).max);
    // build ordered PoolKey
    address a = tokenAddr;
    address b = otherToken;
    (address c0, address c1) = a == b ? (a, b) : (a < b ? (a, b) : (b, a));
    PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), fee, tickSpacing, IHooks(masterControlAddr));
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
    uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, ethToAdd);
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
        tickLower: int24(-60),
        tickUpper: int24(60),
        liquidityDelta: int256(uint256(liquidityDelta)),
        salt: bytes32(0)
    });
    modifyRouter.modifyLiquidity{value: ethToAdd}(key, params, "");
    return tokenAddr;
}

function _seedSuppliedNativeLP(
    PoolModifyLiquidityTest modifyRouter,
    address masterControlAddr,
    address token,
    uint24 fee,
    int24 tickSpacing,
    uint160 sqrtPriceX96,
    uint256 ethToAdd
) internal {
    PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(token), fee, tickSpacing, IHooks(masterControlAddr));
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
    uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, ethToAdd);
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
        tickLower: int24(-60),
        tickUpper: int24(60),
        liquidityDelta: int256(uint256(liquidityDelta)),
        salt: bytes32(0)
    });
    modifyRouter.modifyLiquidity{value: ethToAdd}(key, params, "");
}

function _seedPairLP(
    PoolModifyLiquidityTest modifyRouter,
    address masterControlAddr,
    address tokenA,
    address tokenB,
    uint24 fee,
    int24 tickSpacing,
    uint160 sqrtPriceX96,
    uint256 ethToAdd
) internal {
    address a = tokenA;
    address b = tokenB;
    (address c0, address c1) = a == b ? (a, b) : (a < b ? (a, b) : (b, a));
    PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), fee, tickSpacing, IHooks(masterControlAddr));
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
    uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, ethToAdd);
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
        tickLower: int24(-60),
        tickUpper: int24(60),
        liquidityDelta: int256(uint256(liquidityDelta)),
        salt: bytes32(0)
    });
    modifyRouter.modifyLiquidity{value: ethToAdd}(key, params, "");
}
    function _seed() internal {
        // For the student demo we use the hard-coded deployed addresses.
        address managerAddr = address(0x5FbDB2315678afecb367f032d93F642f64180aa3);
        address padAddr = address(0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0);
        address bidMgrAddr = address(0x4c5859f0F772848b2D91F1D83E2Fe57935348029);
        address bondingAddr = address(0x59b670e9fA9D0A427751Af201D676719a970857b);
        address pointsCmdAddr = address(0x809d550fca64d94Bd9F66E60752A544199cfAC3D);
 
        require(managerAddr != address(0), "MANAGER not set");
        require(padAddr != address(0), "POOL_LAUNCHPAD not set");
        require(bidMgrAddr != address(0), "BID_MANAGER not set");
        require(bondingAddr != address(0), "BONDING not set");
        require(pointsCmdAddr != address(0), "POINTS_COMMAND not set");
 
        PoolLaunchPad pad = PoolLaunchPad(payable(padAddr));
        BidManager bm = BidManager(payable(bidMgrAddr));
        // bond deposits will be done by direct calls to the bonding address when needed
        address masterControlAddr = vm.envAddress("MASTER_CONTROL");
        require(masterControlAddr != address(0), "MASTER_CONTROL not set");
 
        // A canonical sqrtPrice for price=1 in Q96 format
        uint160 sqrtPriceX96 = uint160(2**96);
        // Common pool params used for simplicity
        uint24 fee = 300; // 0.03% style placeholder
        int24 tickSpacing = 60;
 
        // Array to hold created token addresses for reuse
        address[] memory createdTokens = new address[](3);
 
        // Broadcast context: use the default private key provided to forge/script for admin-like actions.
        vm.startBroadcast();
 
        // Deploy a local modify-liquidity router so we can seed liquidity (like tests do)
        PoolModifyLiquidityTest modifyRouter = new PoolModifyLiquidityTest(IPoolManager(managerAddr));
        // Attempt to register the PoolLaunchPad on MasterControl so hooks accept the LaunchPad as the initializer.
        // Use a safe low-level call and ignore failure (owner may be different), but this helps demos where owner==broadcast key.
        MasterControl mc = MasterControl(masterControlAddr);
        (bool ok, ) = address(mc).call(abi.encodeWithSelector(mc.setPoolLaunchPad.selector, padAddr));
        // ignore ok/failure - proceed regardless
 
        // 1) Create TokenA and init pool TokenA <-> Native (use MasterControl as hooks)
        ( , address tokenA) = pad.createNewTokenAndInitWithNative("TokenA", "TKA", 1_000_000 ether, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        createdTokens[0] = tokenA;
        // Approve router and add small native liquidity so pool is usable
        ERC20(tokenA).approve(address(modifyRouter), type(uint256).max);
        {
            // Build PoolKey similarly to PoolLaunchPad ordering: token vs native => (0, token)
            address currency0Addr = address(0);
            address currency1Addr = tokenA;
            PoolKey memory key = PoolKey(Currency.wrap(currency0Addr), Currency.wrap(currency1Addr), fee, tickSpacing, IHooks(masterControlAddr));
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
            uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, 0.01 ether);
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: int24(-60),
                tickUpper: int24(60),
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            });
            modifyRouter.modifyLiquidity{value: 0.01 ether}(key, params, "");
        }
 
        // 2) Create TokenB and init pool TokenB <-> Native
        ( , address tokenB) = pad.createNewTokenAndInitWithNative("TokenB", "TKB", 500_000 ether, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        createdTokens[1] = tokenB;
        ERC20(tokenB).approve(address(modifyRouter), type(uint256).max);
        {
            address currency0Addr = address(0);
            address currency1Addr = tokenB;
            PoolKey memory key = PoolKey(Currency.wrap(currency0Addr), Currency.wrap(currency1Addr), fee, tickSpacing, IHooks(masterControlAddr));
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
            uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, 0.005 ether);
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: int24(-60),
                tickUpper: int24(60),
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            });
            modifyRouter.modifyLiquidity{value: 0.005 ether}(key, params, "");
        }
 
        // 3) Create TokenC and init pool TokenC <-> TokenA
        ( , address tokenC) = pad.createNewTokenAndInitWithToken("TokenC", "TKC", 250_000 ether, tokenA, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        createdTokens[2] = tokenC;
        ERC20(tokenC).approve(address(modifyRouter), type(uint256).max);
        {
            // Determine ordering (tokenA vs tokenC) similar to PoolLaunchPad._orderTokens
            address a = tokenC;
            address b = tokenA;
            (address c0, address c1) = a == b ? (a, b) : (a < b ? (a, b) : (b, a));
            PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), fee, tickSpacing, IHooks(masterControlAddr));
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
            uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, 0.002 ether);
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: int24(-60),
                tickUpper: int24(60),
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            });
            modifyRouter.modifyLiquidity{value: 0.002 ether}(key, params, "");
        }
 
        // 4) Initialize a supplied-token native pool using existing TokenA
        pad.createSuppliedTokenAndInitWithNative(tokenA, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        // Add a small amount of LP for this pair too (tokenA/native)
        {
            address currency0Addr = address(0);
            address currency1Addr = tokenA;
            PoolKey memory key = PoolKey(Currency.wrap(currency0Addr), Currency.wrap(currency1Addr), fee, tickSpacing, IHooks(masterControlAddr));
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
            uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, 0.003 ether);
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: int24(-60),
                tickUpper: int24(60),
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            });
            modifyRouter.modifyLiquidity{value: 0.003 ether}(key, params, "");
        }
 
        // 5) Initialize a supplied-token pair between TokenB and TokenC
        pad.initWithSuppliedTokens(tokenB, tokenC, fee, tickSpacing, sqrtPriceX96, IHooks(masterControlAddr));
        {
            address a = tokenB;
            address b = tokenC;
            (address c0, address c1) = a == b ? (a, b) : (a < b ? (a, b) : (b, a));
            PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), fee, tickSpacing, IHooks(masterControlAddr));
            uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(int24(60));
            uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, 0.004 ether);
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: int24(-60),
                tickUpper: int24(60),
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            });
            // Approve token transfers for both tokens to modify router if needed
            ERC20(tokenB).approve(address(modifyRouter), type(uint256).max);
            ERC20(tokenC).approve(address(modifyRouter), type(uint256).max);
            modifyRouter.modifyLiquidity{value: 0.004 ether}(key, params, "");
        }
 
        vm.stopBroadcast();
 
        // --- Create two bids from two different EOAs (FUNDING_KEY_1, FUNDING_KEY_2) ---
        uint256 fkey1 = vm.envUint("FUNDING_KEY_1");
        uint256 fkey2 = vm.envUint("FUNDING_KEY_2");
 
        // Fallback: if env keys not set, attempt to use the deployer key (already used above).
        // But prefer explicit keys so multiple bidder addresses exist in anvil.
        if (fkey1 == 0) {
            console.log("FUNDING_KEY_1 not set; using the default broadcast key for bidder1 (single-key environment).");
        } else {
            vm.startBroadcast(fkey1);
            // bidder1 creates a bid with 1 ETH (parameters: maxSpendPerEpoch, minMintingRate, rushFactor)
            bm.createBid{value: 1 ether}(0, 0, 50);
            vm.stopBroadcast();
        }
 
        if (fkey2 == 0) {
            console.log("FUNDING_KEY_2 not set; skipping bidder2 creation.");
        } else {
            vm.startBroadcast(fkey2);
            // bidder2 creates a bid with 2 ETH
            bm.createBid{value: 2 ether}(0, 0, 100);
            vm.stopBroadcast();
        }
 
        // If keys were not supplied, attempt to create an extra bid using the deployer account
        if (fkey1 == 0 && fkey2 == 0) {
            // Single-bid fallback: use the deployer (first key) to create one bid
            vm.startBroadcast();
            bm.createBid{value: 1 ether}(0, 0, 50);
            vm.stopBroadcast();
        }
 
        // --- Deposit native bonds into Bonding for the PointsCommand target ---
        // Use bidder1's key if available (otherwise deployer)
        uint256 bondKey = fkey1 != 0 ? fkey1 : uint256(vm.envUint("PRIVATE_KEY"));
        _doDepositBond(bondKey);
 
        // Output a short summary (avoid logging many locals to prevent stack pressure)
        console.log("SetupDefaults completed. Pools, bids and bonds seeded.");
        // For detailed addresses check /tmp/setup-defaults.txt when run via the integration helper.
    }
 
    // Public entrypoint kept minimal to avoid stack-too-deep in external invocation.
    // Heavy locals live inside `_seed()`.
    function run() external {
        _seed();
    }
}