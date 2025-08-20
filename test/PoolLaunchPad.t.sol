// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolLaunchPad} from "../src/PoolLaunchPad.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "../lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract PoolLaunchPadTest is Test, Deployers {
    PoolLaunchPad launchpad;

    function setUp() public {
        // Deploy manager and test routers (sets up modifyLiquidityRouter, etc.)
        deployFreshManagerAndRouters();
        // Deploy the launchpad with the test manager
        launchpad = new PoolLaunchPad(manager);
    }

    // Small smoke tests for each launchpad path (initialization only).

    function test_newTokenPairedWithNative_initializesPool() public {
        uint256 tokenSupply = 1000 ether;
        uint24 fee = 3000;
        int24 tickSpacing = 60;
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;

        (PoolId poolId, address tokenAddr) = launchpad.createNewTokenAndInitWithNative(
            "LP Test Token",
            "LPT",
            tokenSupply,
            fee,
            tickSpacing,
            sqrtPriceX96,
            IHooks(address(0))
        );

        (uint160 slot0SqrtPriceX96,,,) = StateLibrary.getSlot0(manager, poolId);
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
        assertTrue(tokenAddr != address(0));
    }

    function test_suppliedTokenPairedWithNative_initializesPool() public {
        uint256 tokenSupply = 1000 ether;
        uint24 fee = 3000;
        int24 tickSpacing = 60;
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;

        MockERC20 token = new MockERC20("LP Supplied", "LPS", 18);
        token.mint(address(this), tokenSupply);

        (PoolId poolId, address tokenAddr) = launchpad.createSuppliedTokenAndInitWithNative(
            address(token),
            fee,
            tickSpacing,
            sqrtPriceX96,
            IHooks(address(0))
        );

        (uint160 slot0SqrtPriceX96,,,) = StateLibrary.getSlot0(manager, poolId);
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
        assertEq(tokenAddr, address(token));
    }

    function test_newTokenPairedWithSuppliedToken_initializesPool() public {
        uint256 tokenSupply = 1000 ether;
        uint24 fee = 3000;
        int24 tickSpacing = 60;
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;

        MockERC20 other = new MockERC20("Other Token", "OTK", 18);
        other.mint(address(this), tokenSupply);

        (PoolId poolId, address tokenAddr) = launchpad.createNewTokenAndInitWithToken(
            "LP Token",
            "LPT",
            tokenSupply,
            address(other),
            fee,
            tickSpacing,
            sqrtPriceX96,
            IHooks(address(0))
        );

        (uint160 slot0SqrtPriceX96,,,) = StateLibrary.getSlot0(manager, poolId);
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
        assertTrue(tokenAddr != address(0));
    }

    function test_initWithSuppliedTokens_initializesPool() public {
        uint256 tokenSupply = 1000 ether;
        uint24 fee = 3000;
        int24 tickSpacing = 60;
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);
        tokenA.mint(address(this), tokenSupply);
        tokenB.mint(address(this), tokenSupply);

        PoolId poolId = launchpad.initWithSuppliedTokens(
            address(tokenA),
            address(tokenB),
            fee,
            tickSpacing,
            sqrtPriceX96,
            IHooks(address(0))
        );

        (uint160 slot0SqrtPriceX96,,,) = StateLibrary.getSlot0(manager, poolId);
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
    }
}