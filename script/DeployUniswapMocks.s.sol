// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapRouterNoChecks} from "v4-core/test/SwapRouterNoChecks.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolModifyLiquidityTestNoChecks} from "v4-core/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/test/PoolClaimsTest.sol";
import {PoolNestedActionsTest} from "v4-core/test/PoolNestedActionsTest.sol";
import {ActionsRouter} from "v4-core/test/ActionsRouter.sol";

/// @notice Deploys the Uniswap v4 test manager + test routers used by the repo's tests.
/// Writes a small JSON artifact to `script/uniswap-mocks.json` with deployed addresses
/// so subsequent scripts can pick them up.
contract DeployUniswapMocks is Script {
    function run() external returns (address[] memory) {
        vm.startBroadcast();

        // Deploy PoolManager with tx.origin as owner so subsequent role grants work from EOA used to broadcast
        PoolManager pm = new PoolManager(tx.origin);
        address manager = address(pm);

        // Deploy the set of test routers used across the tests
        PoolSwapTest swapRouter = new PoolSwapTest(pm);
        SwapRouterNoChecks swapRouterNoChecks = new SwapRouterNoChecks(pm);
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(pm);
        PoolModifyLiquidityTestNoChecks modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(pm);
        PoolDonateTest donateRouter = new PoolDonateTest(pm);
        PoolTakeTest takeRouter = new PoolTakeTest(pm);
        PoolClaimsTest claimsRouter = new PoolClaimsTest(pm);
        PoolNestedActionsTest nestedActionRouter = new PoolNestedActionsTest(pm);
        ActionsRouter actionsRouter = new ActionsRouter(pm);

        // Set a protocol fee controller so manager isn't left unconfigured
        pm.setProtocolFeeController(tx.origin);

        // Build JSON
        bytes memory jb = abi.encodePacked("{");
        jb = abi.encodePacked(jb, '"PoolManager":"', toHexString(manager), '"');
        jb = abi.encodePacked(jb, ',"PoolSwapTest":"', toHexString(address(swapRouter)), '"');
        jb = abi.encodePacked(jb, ',"SwapRouterNoChecks":"', toHexString(address(swapRouterNoChecks)), '"');
        jb = abi.encodePacked(jb, ',"PoolModifyLiquidityTest":"', toHexString(address(modifyLiquidityRouter)), '"');
        jb = abi.encodePacked(jb, ',"PoolModifyLiquidityTestNoChecks":"', toHexString(address(modifyLiquidityNoChecks)), '"');
        jb = abi.encodePacked(jb, ',"PoolDonateTest":"', toHexString(address(donateRouter)), '"');
        jb = abi.encodePacked(jb, ',"PoolTakeTest":"', toHexString(address(takeRouter)), '"');
        jb = abi.encodePacked(jb, ',"PoolClaimsTest":"', toHexString(address(claimsRouter)), '"');
        jb = abi.encodePacked(jb, ',"PoolNestedActionsTest":"', toHexString(address(nestedActionRouter)), '"');
        jb = abi.encodePacked(jb, ',"ActionsRouter":"', toHexString(address(actionsRouter)), '"');
        jb = abi.encodePacked(jb, "}");
        string memory json = string(jb);

        // Print the JSON so callers invoking `forge script` can capture it from stdout.
        console.log(json);

        vm.stopBroadcast();

        // Return a small array for convenience
        address[] memory addrs = new address[](10);
        addrs[0] = manager;
        addrs[1] = address(swapRouter);
        addrs[2] = address(swapRouterNoChecks);
        addrs[3] = address(modifyLiquidityRouter);
        addrs[4] = address(modifyLiquidityNoChecks);
        addrs[5] = address(donateRouter);
        addrs[6] = address(takeRouter);
        addrs[7] = address(claimsRouter);
        addrs[8] = address(nestedActionRouter);
        addrs[9] = address(actionsRouter);
        return addrs;
    }

    function toHexString(address account) internal pure returns (string memory) {
        bytes20 value = bytes20(account);
        bytes16 hexSymbols = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = hexSymbols[uint8(value[i] >> 4)];
            str[3 + i * 2] = hexSymbols[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }
}