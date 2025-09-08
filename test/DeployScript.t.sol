// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import "../script/Deploy.s.sol";

contract DeployScriptTest is Test, Deployers {    

    function test_run_deploy_script_writes_json() public {
        // Deploy Uniswap test manager & routers so we have a valid manager for the deploy script
        deployFreshManagerAndRouters();

        // Instantiate and run the deploy script (runs in the test VM)
        DeployScript ds = new DeployScript();
        // Provide the freshly deployed test manager to the script
        ds.setManager(address(manager));
        // Use the test-friendly runNoWrite() which returns the array of deployed addresses
        address[] memory addrs = ds.run();
        assert(addrs.length == 16);
        // Basic sanity checks for expected deployed contracts:
        // MasterControl is at index 3, PointsCommand at index 12, MockAVS at index 14
        assert(addrs[3] != address(0));
        assert(addrs[12] != address(0));
        assert(addrs[14] != address(0));        
    }
}