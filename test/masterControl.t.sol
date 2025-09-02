// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MemoryCard} from "../src/MemoryCard.sol";
import {PoolLaunchPad, ERC20Deployer} from "../src/PoolLaunchPad.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import "forge-std/console.sol";
import {MasterControl} from "../src/MasterControl.sol";
import {AccessControl} from "../src/AccessControl.sol";

import {PointsCommand} from "../src/PointsCommand.sol";

contract TestMasterControl is Test, Deployers, ERC1155TokenReceiver {
    // Common fixtures
    MockERC20 token;
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    MasterControl masterControl;
    PointsCommand pointsCommand;
    MemoryCard memoryCard;
    AccessControl accessControl;
    PoolLaunchPad launchpad;

    // Reused state for tests
    // Use Deployers' `key` to avoid duplicate declaration
    uint256 poolIdUint;
    address poolCreator;

    /* ========== Helpers ========== */

    function _deployCore() internal {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy MemoryCard for config and state
        memoryCard = new MemoryCard();

        // Deploy MasterControl with AFTER_SWAP_FLAG set
        uint160 flags = uint160(Hooks.ALL_HOOK_MASK);
        deployCodeTo("MasterControl.sol:MasterControl", abi.encode(manager), address(flags));
        masterControl = MasterControl(address(flags));

        // Deploy AccessControl and register in MasterControl as owner
        accessControl = new AccessControl();
        address mcOwner = masterControl.owner();
        vm.prank(mcOwner);
        masterControl.setAccessControl(address(accessControl));

        // Deploy PoolLaunchPad and configure AccessControl
        launchpad = new PoolLaunchPad(manager, accessControl);
        accessControl.setPoolLaunchPad(address(launchpad));

        // Deploy PointsCommand
        pointsCommand = new PointsCommand();
    }

    function _createAndInitTokenPairWithNative(string memory name, string memory symbol, uint256 supply, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) internal returns (PoolId pid, address tokenAddr) {
        (pid, tokenAddr) = launchpad.createNewTokenAndInitWithNative(
            name,
            symbol,
            supply,
            fee,
            tickSpacing,
            sqrtPriceX96,
            IHooks(address(masterControl))
        );

        // Transfer tokens from launchpad's initial holder to this test contract
        vm.prank(address(launchpad));
        ERC20(tokenAddr).transfer(address(this), supply);

        // Approve routers
        tokenCurrency = Currency.wrap(tokenAddr);
        ERC20(tokenAddr).approve(address(swapRouter), type(uint256).max);
        ERC20(tokenAddr).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Build canonical PoolKey for this pool and save in contract state
        address currency0Addr = tokenAddr;
        address currency1Addr = address(0);
        (address c0, address c1) = currency0Addr == currency1Addr ? (currency0Addr, currency1Addr) : (currency0Addr < currency1Addr ? (currency0Addr, currency1Addr) : (currency1Addr, currency0Addr));
        key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), fee, tickSpacing, IHooks(address(masterControl)));
        poolIdUint = uint256(PoolId.unwrap(key.toId()));
    }

    function _addLiquidityToPool(uint256 ethToAdd) internal {
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );

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

    function _approvePointCommands(bytes32 hookPath) internal {
        address owner = masterControl.owner();
        vm.prank(owner);
        masterControl.approveCommand(hookPath, address(pointsCommand), pointsCommand.afterSwap.selector, "afterSwap");
        vm.prank(owner);
        masterControl.approveCommand(hookPath, address(pointsCommand), pointsCommand.setBonusThreshold.selector, "setBonusThreshold");
        vm.prank(owner);
        masterControl.approveCommand(hookPath, address(pointsCommand), pointsCommand.setBonusPercent.selector, "setBonusPercent");
        vm.prank(owner);
        masterControl.approveCommand(hookPath, address(pointsCommand), pointsCommand.setBasePointsPercent.selector, "setBasePointsPercent");
    }

    // Helper: create a whitelisted block as owner and apply it to the pool as the given admin
    function _createBlockAndApply(uint256 poolId, bytes32 hookPath, MasterControl.Command[] memory cmds, uint256 blockId, address admin) internal {
        address mcOwner = masterControl.owner();
        // Approve each command as owner (use each command's declared hookPath)
        for (uint i = 0; i < cmds.length; i++) {
            vm.prank(mcOwner);
            masterControl.approveCommand(cmds[i].hookPath, cmds[i].target, cmds[i].selector, "auto");
        }
        // Owner creates the whitelisted block
        vm.prank(mcOwner);
        masterControl.createBlock(blockId, cmds, 0);
        // Admin applies the block to the pool
        uint256[] memory blockIds = new uint256[](1);
        blockIds[0] = blockId;
        vm.prank(admin);
        masterControl.applyBlocksToPool(poolId, blockIds);
    }

    function _registerCommandsForPool(bytes32 hookPath) internal {
        // Build a single-command block that targets the PointsCommand.afterSwap
        MasterControl.Command[] memory commands = new MasterControl.Command[](1);
        commands[0] = MasterControl.Command({
            hookPath: hookPath,
            target: address(pointsCommand),
            selector: pointsCommand.afterSwap.selector,
            data: "", // input will be provided as hookData at swap time
            callType: MasterControl.CallType.Delegate
        });
 
        // Owner creates a whitelisted block
        uint256 blockId = 1;
        address mcOwner = masterControl.owner();
        vm.prank(mcOwner);
        masterControl.createBlock(blockId, commands, 0);
 
        // Set poolCreator and ensure it is recognized as pool admin for the test
        poolCreator = address(2);
        vm.deal(poolCreator, 10 ether);
 
        // Force AccessControl admin to poolCreator (for test setup)
        vm.prank(address(launchpad));
        accessControl.setPoolAdmin(poolIdUint, poolCreator);
 
        // Apply the created block to the pool as the pool admin
        uint256[] memory blockIds = new uint256[](1);
        blockIds[0] = blockId;
        vm.prank(poolCreator);
        masterControl.applyBlocksToPool(poolIdUint, blockIds);
    }

    function _configurePoolSettings(address memoryCardAddr) internal {
        // Owner must register the MemoryCard and whitelist allowed keys.
        address mcOwner = masterControl.owner();
        vm.prank(mcOwner);
        masterControl.setMemoryCard(memoryCardAddr);
        vm.prank(mcOwner);
        masterControl.setAllowedConfigKey(keccak256("bonus_threshold"), true);
        vm.prank(mcOwner);
        masterControl.setAllowedConfigKey(keccak256("bonus_percent"), true);
        vm.prank(mcOwner);
        masterControl.setAllowedConfigKey(keccak256("base_points_percent"), true);
 
        // Pool admin writes per-pool values via the safe API.
        vm.prank(poolCreator);
        masterControl.setPoolConfigValue(poolIdUint, keccak256("bonus_threshold"), abi.encode(0.0002 ether));
        vm.prank(poolCreator);
        masterControl.setPoolConfigValue(poolIdUint, keccak256("bonus_percent"), abi.encode(20));
        vm.prank(poolCreator);
        masterControl.setPoolConfigValue(poolIdUint, keccak256("base_points_percent"), abi.encode(20));
    }

    function _performSwapAndReturnPoints(int256 amount0) internal returns (uint256) {
        PointsCommand.AfterSwapInput memory afterSwapInput = PointsCommand.AfterSwapInput({
            memoryCardAddr: address(memoryCard),
            pointsTokenAddr: address(masterControl),
            poolId: poolIdUint,
            user: address(this),
            amount0: amount0,
            amount1: 0,
            swapParams: ""
        });
        bytes memory hookData = abi.encode(afterSwapInput);

        uint256 beforeBal = masterControl.balanceOf(address(this), poolIdUint);

        swapRouter.swap{value: uint256(-amount0)}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: amount0,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 afterBal = masterControl.balanceOf(address(this), poolIdUint);
        return afterBal - beforeBal;
    }

    /* ========== Test setup ========== */

    function setUp() public {
        _deployCore();

        // Create token + initialize pool, add liquidity, approve commands, register and configure pool
        (PoolId pid, address tokenAddr) = _createAndInitTokenPairWithNative(
            "Test Token",
            "TEST",
            1000 ether,
            3000,
            60,
            SQRT_PRICE_1_1
        );

        _addLiquidityToPool(0.003 ether);

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

        _approvePointCommands(hookPath);
        _registerCommandsForPool(hookPath);
        _configurePoolSettings(address(memoryCard));
    }

    /* ========== Tests ========== */

    function test_swap_mints_points() public {
        // Swap 0.001 ETH for tokens, expect points minted according to configured percentages
        uint256 minted = _performSwapAndReturnPoints(-0.001 ether);
        // Basic sanity: some points should be minted
        assert(minted > 0);
        console.log("Points minted for 0.001 ETH swap:", minted);
    }

    function test_createBlock_reverts_for_unapproved_command() public {
        bytes32 hookPath = keccak256(abi.encodePacked("unapprovedHook", key.currency0, key.currency1, key.fee));
        MasterControl.Command[] memory badCommands = new MasterControl.Command[](1);
        badCommands[0] = MasterControl.Command({
            hookPath: hookPath,
            target: address(bytes20(hex"DEAD00000000000000000000000000000000BEEF")),
            selector: bytes4(0x12345678),
            data: "",
            callType: MasterControl.CallType.Delegate
        });
 
        address mcOwner = masterControl.owner();
        vm.prank(mcOwner);
        vm.expectRevert(bytes("MasterControl: command not approved for block"));
        masterControl.createBlock(999, badCommands, 0);
    }
}