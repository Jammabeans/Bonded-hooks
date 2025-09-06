// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/Settings.sol";
import "../src/GasBank.sol";
import "../src/DegenPool.sol";
import "../src/FeeCollector.sol";

contract SettingsTest is Test {
    Settings settings;
    GasBank gb;
    DegenPool dp;
    FeeCollector fc;

    function setUp() public {
        gb = new GasBank();
        dp = new DegenPool();
        fc = new FeeCollector();
        settings = new Settings(address(gb), address(dp), address(fc));
    }

    function testDefaultSharesInitialized() public {
        (address[] memory recips, uint256[] memory weights) = settings.getDefaultShares();
        // Expect three recipients in the order provided by constructor
        assertEq(recips.length, 3);
        assertEq(weights.length, 3);

        assertEq(recips[0], address(gb));
        assertEq(recips[1], address(dp));
        assertEq(recips[2], address(fc));

        assertEq(weights[0], 400);
        assertEq(weights[1], 250);
        assertEq(weights[2], 100);
    }

    function testOwnerCanSetCustomSharesAndGetSharesFor() public {
        address ownerAddr = address(0xABC);
        address[] memory recips = new address[](2);
        uint256[] memory weights = new uint256[](2);
        recips[0] = address(0x111);
        recips[1] = address(0x222);
        weights[0] = 10;
        weights[1] = 90;

        // only owner may call setCustomSharesFor; test contract is owner
        settings.setCustomSharesFor(ownerAddr, recips, weights);

        (address[] memory gotRecips, uint256[] memory gotWeights) = settings.getSharesFor(ownerAddr);
        assertEq(gotRecips.length, 2);
        assertEq(gotWeights.length, 2);
        assertEq(gotRecips[0], recips[0]);
        assertEq(gotRecips[1], recips[1]);
        assertEq(gotWeights[0], weights[0]);
        assertEq(gotWeights[1], weights[1]);
    }
}