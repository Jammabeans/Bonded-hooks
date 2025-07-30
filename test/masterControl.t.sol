// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import "forge-std/console.sol";
import {MasterControl} from "../src/MasterControl.sol";
import {PointsMintHook} from "../src/PointsMintHook.sol";

contract TestMasterControl is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    MasterControl masterControl;
    PointsMintHook pointsMintHook;

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        // Deploy MasterControl to an address with AFTER_SWAP_FLAG set
        uint160 flags = uint160(Hooks.ALL_HOOK_MASK);
        console.log("flags Master " , address(flags));
        // Use full artifact path to avoid ambiguity and ensure correct bytecode
        deployCodeTo("MasterControl.sol:MasterControl", abi.encode(manager), address(flags));
        masterControl = MasterControl(address(flags));

        console.log("point 1"); 

        // Deploy PointsMintHook
        pointsMintHook = new PointsMintHook(manager);

        console.log("mintHook address: ", address(pointsMintHook)); 

        // Register PointsMintHook with MasterControl for afterSwap
      // masterControl.addHook("afterSwap", address(pointsMintHook), "Points Mint Hook");

        // Approve TOKEN for spending on routers
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize a pool with MasterControl as the hook
        (key, ) = initPool(
            ethCurrency,
            tokenCurrency,
            masterControl,
            3000,
            SQRT_PRICE_1_1
        );

        // Add some liquidity to the pool
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.003 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );

        console.log(" address this MastrtControl.t.sol: ", address(this));
        console.log("adddress modifyLiquidityRouter: ", address(modifyLiquidityRouter));
        console.log("swapRouter: ", address(swapRouter));

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swap_mints_points() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = pointsMintHook.balanceOf(
            address(this),
            poolIdUint
        );

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        console.log("point 2");

        // Swap 0.001 ETH for tokens, expect 20% of 0.001 * 10**18 points
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
        
        uint256 pointsBalanceAfterSwap = pointsMintHook.balanceOf(
            address(this),
            poolIdUint
        );
        console.log("pointsBalanceAfterSwap: ", pointsBalanceAfterSwap);
       // assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    }
}