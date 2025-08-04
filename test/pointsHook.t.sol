// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import {Test} from "forge-std/Test.sol";

// import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
// import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
// import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
 
// import {PoolManager} from "v4-core/PoolManager.sol";
// import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
// import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
 
// import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
// import {PoolId} from "v4-core/types/PoolId.sol";
// import {PoolKey} from "v4-core/types/PoolKey.sol";
 
// import {Hooks} from "v4-core/libraries/Hooks.sol";
// import {TickMath} from "v4-core/libraries/TickMath.sol";
// import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
// import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
 
// import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
// import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

// import {IMemoryCard} from "../src/IMemoryCard.sol";
// import {PointsCommand} from "../src/PointsCommand.sol";



// contract TestPointsCommand is Test, Deployers {
//     MockERC20 token;
//     //TestPointsNFT pointsNFT;
//     PointsCommand pointsCommand;
//     IMemoryCard memoryCard;

//     //PoolKey key;
//     Currency ethCurrency = Currency.wrap(address(0));
//     Currency tokenCurrency;

//     address poolManagerAddr;
//     //address swapRouter;
//     //address modifyLiquidityRouter;

//     function setUp() public {
//         // Deploy PoolManager and routers
//         deployFreshManagerAndRouters();
//         poolManagerAddr = address(manager);

//         // Deploy ERC20
//         token = new MockERC20("Test Token", "TEST", 18);
//         tokenCurrency = Currency.wrap(address(token));
//         token.mint(address(this), 1000 ether);
//         token.mint(address(1), 1000 ether);

//         // Deploy memory card contract
//         memoryCard = IMemoryCard(deployCode("MemoryCard.sol"));

//         // Deploy points NFT contract
//         //pointsNFT = new TestPointsNFT();

//         // Deploy points command contract
//         pointsCommand = new PointsCommand();

//         // Approve token
//         token.approve(address(swapRouter), type(uint256).max);
//         token.approve(address(modifyLiquidityRouter), type(uint256).max);

//         // Initialize the pool
//         (key, ) = initPool(
//             ethCurrency,
//             tokenCurrency,
//             address(0), // hooks now managed by MasterControl, not this test (use the real dispatcher if needed)
//             3000,
//             SQRT_PRICE_1_1
//         );

//         // Add some liquidity
//         uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
//         uint256 ethToAdd = 0.003 ether;
//         uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
//             SQRT_PRICE_1_1,
//             sqrtPriceAtTickUpper,
//             ethToAdd
//         );
//         uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
//         uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
//             sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta
//         );

//         modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
//             key,
//             ModifyLiquidityParams({
//                 tickLower: -60,
//                 tickUpper: 60,
//                 liquidityDelta: int256(uint256(liquidityDelta)),
//                 salt: bytes32(0)
//             }),
//             ""
//         );

//         // Set initial config in memory card (stateless config, like bonus rate, etc)
//         pointsCommand.setBonusThreshold(address(memoryCard), 0.0025 ether);
//         pointsCommand.setBonusPercent(address(memoryCard), 10);
//         pointsCommand.setBasePointsPercent(address(memoryCard), 20);
//     }

//         function test_swap() public {
//     uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
//     uint256 pointsBalanceOriginal = hook.balanceOf(
//         address(this),
//         poolIdUint
//     );

//     // Set user address in hook data
//     bytes memory hookData = abi.encode(address(this));

//     // Now we swap
//     // We will swap 0.001 ether for tokens
//     // We should get 20% of 0.001 * 10**18 points
//     // = 2 * 10**14
//     swapRouter.swap{value: 0.001 ether}(
//         key,
//         SwapParams({
//             zeroForOne: true,
//             amountSpecified: -0.001 ether, // Exact input for output swap
//             sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
//         }),
//         PoolSwapTest.TestSettings({
//             takeClaims: false,
//             settleUsingBurn: false
//         }),
//         hookData
//     );
//     uint256 pointsBalanceAfterSwap = hook.balanceOf(
//         address(this),
//         poolIdUint
//     );
//     assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
//     }
// }