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
import {Currency} from "v4-core/types/Currency.sol";

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

        // Reconstruct the canonical PoolKey used by the launchpad and assert pool id matches
        address currency0Addr = tokenAddr;
        address currency1Addr = address(0);
        (address c0, address c1) = currency0Addr == currency1Addr ? (currency0Addr, currency1Addr) : (currency0Addr < currency1Addr ? (currency0Addr, currency1Addr) : (currency1Addr, currency0Addr));
        PoolKey memory expectedKey = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 3000, 60, IHooks(address(0)));

        assert(PoolId.unwrap(pid) == PoolId.unwrap(expectedKey.toId()));

        // Ensure AccessControl registered the calling account (this test) as pool admin
        uint256 pidUint = uint256(PoolId.unwrap(pid));
        assert(accessControl.getPoolAdmin(pidUint) == address(this));
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

        address currency0Addr = address(0);
        address currency1Addr = tokenAddr;
        (address c0, address c1) = currency0Addr == currency1Addr ? (currency0Addr, currency1Addr) : (currency0Addr < currency1Addr ? (currency0Addr, currency1Addr) : (currency1Addr, currency0Addr));
        PoolKey memory expectedKey = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 3000, 60, IHooks(address(0)));

        assert(PoolId.unwrap(pid) == PoolId.unwrap(expectedKey.toId()));

        uint256 pidUint2 = uint256(PoolId.unwrap(pid));
        assert(accessControl.getPoolAdmin(pidUint2) == address(this));
    }

    function test_newTokenPairedWithSuppliedToken_initializesPool() public {
        address otherToken = address(new ERC20Deployer("Other","O", address(this), 1000 ether));
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithToken(
            "TKN",
            "TKN",
            1000 ether,
            otherToken,
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );

        address currency0Addr = tokenAddr;
        address currency1Addr = otherToken;
        (address c0, address c1) = currency0Addr == currency1Addr ? (currency0Addr, currency1Addr) : (currency0Addr < currency1Addr ? (currency0Addr, currency1Addr) : (currency1Addr, currency0Addr));
        PoolKey memory expectedKey = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 3000, 60, IHooks(address(0)));

        assert(PoolId.unwrap(pid) == PoolId.unwrap(expectedKey.toId()));

        uint256 pidUint2 = uint256(PoolId.unwrap(pid));
        assert(accessControl.getPoolAdmin(pidUint2) == address(this));
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
 
        address currency0Addr = address(a);
        address currency1Addr = address(b);
        (address c0, address c1) = currency0Addr == currency1Addr ? (currency0Addr, currency1Addr) : (currency0Addr < currency1Addr ? (currency0Addr, currency1Addr) : (currency1Addr, currency0Addr));
        PoolKey memory expectedKey = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 3000, 60, IHooks(address(0)));
 
        assert(PoolId.unwrap(pid) == PoolId.unwrap(expectedKey.toId()));
 
        uint256 pidUint2 = uint256(PoolId.unwrap(pid));
        assert(accessControl.getPoolAdmin(pidUint2) == address(this));
    }

    function test_allPools_returnsCreatedPools() public {
        (PoolId pid1, address token1) = launchpad.createNewTokenAndInitWithNative(
            "P1",
            "P1",
            1000 ether,
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );

        (PoolId pid2, address token2) = launchpad.createNewTokenAndInitWithNative(
            "P2",
            "P2",
            1000 ether,
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );

        (PoolId pid3, address token3) = launchpad.createNewTokenAndInitWithNative(
            "P3",
            "P3",
            1000 ether,
            3000,
            60,
            1 << 96,
            IHooks(address(0))
        );

        PoolId[] memory pools = launchpad.allPools();
        assert(pools.length == 3);

        assert(PoolId.unwrap(pools[0]) == PoolId.unwrap(pid1));
        assert(PoolId.unwrap(pools[1]) == PoolId.unwrap(pid2));
        assert(PoolId.unwrap(pools[2]) == PoolId.unwrap(pid3));
    }
}