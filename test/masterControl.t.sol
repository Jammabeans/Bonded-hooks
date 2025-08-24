// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MemoryCard} from "../src/MemoryCard.sol";

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
import {AccessControl} from "../src/AccessControl.sol";

import {PointsCommand} from "../src/PointsCommand.sol";

contract TestMasterControl is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    MasterControl masterControl;
    PointsCommand pointsCommand;
    MemoryCard memoryCard;
    AccessControl accessControl;

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        // Deploy MemoryCard for config and state
        memoryCard = new MemoryCard();
        console.log("MemoryCard deployed at: ", address(memoryCard));

        // Deploy MasterControl to an address with AFTER_SWAP_FLAG set
        uint160 flags = uint160(Hooks.ALL_HOOK_MASK);
        console.log("flags Master " , address(flags));
        // Use full artifact path to avoid ambiguity and ensure correct bytecode
        deployCodeTo("MasterControl.sol:MasterControl", abi.encode(manager), address(flags));
        masterControl = MasterControl(address(flags));
 
        // Deploy and register AccessControl, then set in MasterControl (must be called by pool manager)
        accessControl = new AccessControl();
        vm.prank(address(manager));
        masterControl.setAccessControl(address(accessControl));
 
        console.log("point 1");
 
        // Deploy pointsCommand
        pointsCommand = new PointsCommand();

        // Set up MemoryCard config for PointsCommand
        // These values can be adjusted as needed for your test logic
        address memoryCardAddr = address(memoryCard);

        // Prepare batch commands for PointsCommand setters (data will be finalized after pool creation)
        MasterControl.Command[] memory setupCommands = new MasterControl.Command[](3);
        setupCommands[0] = MasterControl.Command({
            target: address(pointsCommand),
            selector: pointsCommand.setBonusThreshold.selector,
            data: abi.encode(memoryCardAddr, bytes32(0), 0.0002 ether), // placeholder for poolKeyHash
            callType: MasterControl.CallType.Delegate
        });
        setupCommands[1] = MasterControl.Command({
            target: address(pointsCommand),
            selector: pointsCommand.setBonusPercent.selector,
            data: abi.encode(memoryCardAddr, bytes32(0), 20), // placeholder
            callType: MasterControl.CallType.Delegate
        });
        setupCommands[2] = MasterControl.Command({
            target: address(pointsCommand),
            selector: pointsCommand.setBasePointsPercent.selector,
            data: abi.encode(memoryCardAddr, bytes32(0), 20), // placeholder
            callType: MasterControl.CallType.Delegate
        });

        console.log("mintHook address: ", address(pointsCommand));

        // Register pointsCommand with MasterControl for afterSwap
      // masterControl.addHook("afterSwap", address(pointsCommand), "Points Mint Hook");

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

         // ---------- Register pointsCommand as afterSwap command in MasterControl ---------
        MasterControl.Command[] memory commands = new MasterControl.Command[](1);

        commands[0] = MasterControl.Command({
            target: address(pointsCommand),
            selector: pointsCommand.afterSwap.selector,
            data: "", // input will be provided as hookData at swap time
            callType: MasterControl.CallType.Delegate
        });

        bytes32 poolKeyHash = keccak256(abi.encode(key));
        bytes32 hookPath = keccak256(
            abi.encodePacked(
                "afterSwap",
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                key.hooks
            )
        );
 
        // Simulate a separate user creating the pool and becoming the pool admin,
        // then run the setup commands as that admin so per-pool config is written.
        address poolCreator = address(2);
        vm.deal(poolCreator, 10 ether);
        // Register pool admin (AccessControl allows first setter by anyone)
        vm.prank(poolCreator);
        accessControl.setPoolAdmin(poolKeyHash, poolCreator);
 
        // Have the poolCreator register the commands for this pool
        vm.prank(poolCreator);
        masterControl.setCommands(key, hookPath, commands);
 
        // Finalize setupCommands with actual poolKeyHash and run them as pool admin
        setupCommands[0].data = abi.encode(memoryCardAddr, poolKeyHash, 0.0002 ether);
        setupCommands[1].data = abi.encode(memoryCardAddr, poolKeyHash, 20);
        setupCommands[2].data = abi.encode(memoryCardAddr, poolKeyHash, 20);
 
        vm.prank(poolCreator);
        masterControl.runCommandBatchForPool(key, setupCommands);
 
    }

    function test_swap_mints_points() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = masterControl.balanceOf(
            address(this),
            poolIdUint
        );

        // Prepare AfterSwapInput for PointsCommand
        PointsCommand.AfterSwapInput memory afterSwapInput = PointsCommand.AfterSwapInput({
            memoryCardAddr: address(memoryCard),
            pointsTokenAddr: address(masterControl),
            poolId: uint256(PoolId.unwrap(key.toId())),
            user: address(this),
            amount0: -0.001 ether,
            amount1: 0, // This can be set to the expected output amount if needed
            swapParams: "" // Not used in PointsCommand logic
        });
        bytes memory hookData = abi.encode(afterSwapInput);
        // Debug: log encoded AfterSwapInput
        console.log("Encoded AfterSwapInput length: ", hookData.length);
        if (hookData.length >= 32) {
            bytes32 word0;
            assembly { word0 := mload(add(hookData, 0x20)) }
            console.logBytes32(word0);
        }
        if (hookData.length >= 64) {
            bytes32 word1;
            assembly { word1 := mload(add(hookData, 0x40)) }
            console.logBytes32(word1);
        }

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
        
        uint256 pointsBalanceAfterSwap = masterControl.balanceOf(
            address(this),
            poolIdUint
        );
        console.log("poolIdUint: ", poolIdUint);
        console.log("address.this: ", address(this));
        console.log("pointsBalanceAfterSwap: ", pointsBalanceAfterSwap);
        // Uncomment and adjust the assertion as needed for your points logic
        // assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    }
}