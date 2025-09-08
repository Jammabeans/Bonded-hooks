// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/Settings.sol";
import "../src/GasBank.sol";
import "../src/DegenPool.sol";
import "../src/FeeCollector.sol";

contract SettingsExtraTest is Test {
    Settings settings;
    GasBank gb;
    DegenPool dp;
    FeeCollector fc;
    address nonOwner = address(0xBAD);

    function setUp() public {
        AccessControl acl = new AccessControl();
        gb = new GasBank(acl);
        dp = new DegenPool(acl);
        fc = new FeeCollector(acl);
        settings = new Settings(address(gb), address(dp), address(fc), acl);
        // grant required admin roles so this test can perform owner-like operations under ACL
        acl.grantRole(gb.ROLE_GAS_BANK_ADMIN(), address(this));
        acl.grantRole(dp.ROLE_DEGEN_ADMIN(), address(this));
        acl.grantRole(fc.ROLE_FEE_COLLECTOR_ADMIN(), address(this));
        acl.grantRole(settings.ROLE_SETTINGS_ADMIN(), address(this));
    }

    function testSetDefaultSharesRejectsInvalid() public {
        address[] memory recips = new address[](2);
        uint256[] memory weights = new uint256[](2);

        // zero recipient should revert
        recips[0] = address(0);
        recips[1] = address(0x1);
        weights[0] = 10;
        weights[1] = 10;
        vm.expectRevert(bytes("Zero recipient"));
        settings.setDefaultShares(recips, weights);

        // zero weight should revert
        recips[0] = address(0x1);
        recips[1] = address(0x2);
        weights[0] = 0;
        weights[1] = 10;
        vm.expectRevert(bytes("Zero weight"));
        settings.setDefaultShares(recips, weights);

        // mismatched arrays should revert
        address[] memory r2 = new address[](1);
        uint256[] memory w2 = new uint256[](2);
        r2[0] = address(0x1);
        w2[0] = 1;
        w2[1] = 2;
        vm.expectRevert(bytes("Mismatched arrays"));
        settings.setDefaultShares(r2, w2);
    }

    function testOnlyOwnerCanSetCustomShares() public {
        address[] memory recips = new address[](1);
        uint256[] memory weights = new uint256[](1);
        recips[0] = address(0xDEAD);
        weights[0] = 100;

        // non-owner should revert
        vm.prank(nonOwner);
        vm.expectRevert();
        settings.setCustomSharesFor(nonOwner, recips, weights);

        // owner (this) can set
        settings.setCustomSharesFor(nonOwner, recips, weights);
        (address[] memory gotRecips, uint256[] memory gotWeights) = settings.getSharesFor(nonOwner);
        assertEq(gotRecips.length, 1);
        assertEq(gotRecips[0], recips[0]);
        assertEq(gotWeights[0], weights[0]);
    }

    function testClearCustomSharesRevertsToDefault() public {
        address target = address(0xFEED);
        address[] memory recips = new address[](1);
        uint256[] memory weights = new uint256[](1);
        recips[0] = address(0x111);
        weights[0] = 10;

        settings.setCustomSharesFor(target, recips, weights);
        (address[] memory gotRecips, ) = settings.getSharesFor(target);
        assertEq(gotRecips[0], recips[0]);

        // clear
        settings.clearCustomSharesFor(target);
        (address[] memory defRecips, uint256[] memory defWeights) = settings.getSharesFor(target);
        (address[] memory explicitDefaults, uint256[] memory explicitWeights) = settings.getDefaultShares();
        assertEq(defRecips.length, explicitDefaults.length);
        for (uint256 i = 0; i < defRecips.length; i++) {
            assertEq(defRecips[i], explicitDefaults[i]);
            assertEq(defWeights[i], explicitWeights[i]);
        }
    }
}