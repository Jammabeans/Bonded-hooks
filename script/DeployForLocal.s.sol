// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "./Deploy.s.sol";
// Import the core PoolManager and the test routers we use as lightweight "mocks"
// (we deploy these directly so we don't rely on the Test harness / vm cheats).
import "../lib/v4-periphery/lib/v4-core/src/PoolManager.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolSwapTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/SwapRouterNoChecks.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolModifyLiquidityTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolModifyLiquidityTestNoChecks.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolDonateTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolTakeTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolClaimsTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/PoolNestedActionsTest.sol";
import "../lib/v4-periphery/lib/v4-core/src/test/ActionsRouter.sol";

/// @notice Deploy Uniswap v4 mocks (manager + routers) then run the project's DeployScript
/// so MasterControl is deployed with the special CREATE2 address. This reproduces what
/// `test/DeployScript.t.sol` does but as a forge script that prints a JSON line with deployed addresses.
///
/// Usage (local Anvil):
///   anvil -p 8545
///   forge script script/DeployForLocal.s.sol:DeployForLocal --rpc-url http://127.0.0.1:8545 --private-key <KEY> --broadcast -vvvv
contract DeployForLocal is Script {
    function run() external returns (address[] memory) {
        // Start broadcast so deployments are visible on the RPC (and to console.log)
        vm.startBroadcast();
 
        // Deploy a PoolManager and the test routers programmatically (no test-only cheats).
        // Use tx.origin as the initial owner so subsequent grantRole calls in DeployScript succeed.
        PoolManager pm = new PoolManager(tx.origin);
        IPoolManager manager = IPoolManager(address(pm));
 
        // Deploy the routers and helper test contracts against the manager
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        SwapRouterNoChecks swapRouterNoChecks = new SwapRouterNoChecks(manager);
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        PoolModifyLiquidityTestNoChecks modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        PoolDonateTest donateRouter = new PoolDonateTest(manager);
        PoolTakeTest takeRouter = new PoolTakeTest(manager);
        PoolClaimsTest claimsRouter = new PoolClaimsTest(manager);
        PoolNestedActionsTest nestedActionRouter = new PoolNestedActionsTest(manager);
        ActionsRouter actionsRouter = new ActionsRouter(manager);
 
        // set a protocol fee controller so manager isn't left unconfigured (use tx.origin)
        pm.setProtocolFeeController(tx.origin);
 
        // Now run the project's DeployScript, passing the freshly deployed manager
        // Deploy the helper DeployScript while broadcast is active so the contract is created,
        // then stop the current broadcast so DeployScript.run() can safely call vm.startBroadcast().
        DeployScript ds = new DeployScript();
        ds.setManager(address(manager));
        vm.stopBroadcast();
        // DeployScript.run() will start its own broadcast; capture the returned addresses.
        address[] memory addrs = ds.run();

        // Build a small JSON artifact for consumers (operator helper / CI)
        // Construct incrementally to avoid "stack too deep" during compilation.
        bytes memory jb = abi.encodePacked("{");
        jb = abi.encodePacked(jb, '"PoolManager":"', toHexString(addrs[0]), '"');
        jb = abi.encodePacked(jb, ',"AccessControl":"', toHexString(addrs[1]), '"');
        jb = abi.encodePacked(jb, ',"PoolLaunchPad":"', toHexString(addrs[2]), '"');
        jb = abi.encodePacked(jb, ',"MasterControl":"', toHexString(addrs[3]), '"');
        jb = abi.encodePacked(jb, ',"FeeCollector":"', toHexString(addrs[4]), '"');
        jb = abi.encodePacked(jb, ',"GasBank":"', toHexString(addrs[5]), '"');
        jb = abi.encodePacked(jb, ',"DegenPool":"', toHexString(addrs[6]), '"');
        jb = abi.encodePacked(jb, ',"Settings":"', toHexString(addrs[7]), '"');
        jb = abi.encodePacked(jb, ',"ShareSplitter":"', toHexString(addrs[8]), '"');
        jb = abi.encodePacked(jb, ',"Bonding":"', toHexString(addrs[9]), '"');
        jb = abi.encodePacked(jb, ',"PrizeBox":"', toHexString(addrs[10]), '"');
        jb = abi.encodePacked(jb, ',"Shaker":"', toHexString(addrs[11]), '"');
        jb = abi.encodePacked(jb, ',"PointsCommand":"', toHexString(addrs[12]), '"');
        jb = abi.encodePacked(jb, ',"BidManager":"', toHexString(addrs[13]), '"');
        jb = abi.encodePacked(jb, "}");
        string memory json = string(jb);

        // Print single-line JSON (CI / helper scripts expect the last printed line to be JSON)
        console.log(json);
 
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