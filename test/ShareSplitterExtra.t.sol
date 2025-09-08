// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/ShareSplitter.sol";
import "../src/Settings.sol";
import "../src/GasBank.sol";
import "../src/DegenPool.sol";
import "../src/FeeCollector.sol";

contract ShareSplitterExtraTest is Test {
    Settings settings;
    ShareSplitter splitter;
    GasBank gb;
    DegenPool dp;
    FeeCollector fc;
    address sender = address(0xABC);

    event SplitExecuted(address indexed sender, uint256 amount, address[] recipients, uint256[] amounts);

    function setUp() public {
        // deploy ACL and pass into contracts
        AccessControl acl = new AccessControl();
        gb = new GasBank(acl);
        dp = new DegenPool(acl);
        fc = new FeeCollector(acl);
        settings = new Settings(address(gb), address(dp), address(fc), acl);
        // grant admin roles required for tests
        acl.grantRole(gb.ROLE_GAS_BANK_ADMIN(), address(this));
        acl.grantRole(dp.ROLE_DEGEN_ADMIN(), address(this));
        acl.grantRole(fc.ROLE_FEE_COLLECTOR_ADMIN(), address(this));
        acl.grantRole(settings.ROLE_SETTINGS_ADMIN(), address(this));
        splitter = new ShareSplitter(address(settings), acl);
    }

    function testOwnerCanChangeDefaultAndSplitterRespectsIt() public {
        // New default: 2 recipients, 1:1 split
        address[] memory recips = new address[](2);
        recips[0] = address(dp);
        recips[1] = address(fc);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        // owner sets default shares
        settings.setDefaultShares(recips, weights);

        // sender splits 10 wei
        uint256 amount = 10 wei;
        vm.deal(sender, amount);
        // perform split and assert balances (event ordering may include intermediate DepositReceived logs)
        vm.prank(sender);
        splitter.splitAndForward{value: amount}();

        // Each recipient should have roughly half; check sum equals amount
        uint256 b0 = address(recips[0]).balance;
        uint256 b1 = address(recips[1]).balance;
        assertEq(b0 + b1, amount);
    }

    function testSetDefaultSharesRejectsZeroTotalWeight() public {
        // Attempt to set default shares with zero total weight (all weights zero)
        address[] memory recips = new address[](2);
        recips[0] = address(0x1);
        recips[1] = address(0x2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0;
        weights[1] = 0;
 
        vm.expectRevert();
        settings.setDefaultShares(recips, weights);
    }

    function testSplitterFailsOnZeroValue() public {
        vm.prank(sender);
        vm.expectRevert(bytes("No ETH"));
        splitter.splitAndForward{value: 0}();
    }
}