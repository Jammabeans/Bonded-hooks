// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolLaunchPad, ERC20Deployer} from "../src/PoolLaunchPad.sol";
import {AccessControl} from "../src/AccessControl.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract PoolLaunchPadTest is Test, Deployers {
    PoolLaunchPad launchpad;
    AccessControl accessControl;

    function setUp() public {
        deployFreshManagerAndRouters();
        accessControl = new AccessControl();
        launchpad = new PoolLaunchPad(manager, accessControl);
        accessControl.setPoolLaunchPad(address(launchpad));
    }

    function test_newTokenPairedWithNative_initializesPool() public {
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithNative(
            "TKN",
            "TKN",
            1000 ether,
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );
        assert(PoolId.unwrap(pid) != 0);
    }

    function test_suppliedTokenPairedWithNative_initializesPool() public {
        ERC20Deployer token = new ERC20Deployer("Test","T", address(this), 1000 ether);
        (PoolId pid, address tokenAddr) = launchpad.createSuppliedTokenAndInitWithNative(
            address(token),
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );
        assert(PoolId.unwrap(pid) != 0);
    }

    function test_newTokenPairedWithSuppliedToken_initializesPool() public {
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithToken(
            "TKN",
            "TKN",
            1000 ether,
            address(new ERC20Deployer("Other","O", address(this), 1000 ether)),
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );
        assert(PoolId.unwrap(pid) != 0);
    }

    function test_initWithSuppliedTokens_initializesPool() public {
        ERC20Deployer a = new ERC20Deployer("A","A", address(this), 1000 ether);
        ERC20Deployer b = new ERC20Deployer("B","B", address(this), 1000 ether);
        PoolId pid = launchpad.initWithSuppliedTokens(
            address(a),
            address(b),
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );
        assert(PoolId.unwrap(pid) != 0);
    }
}