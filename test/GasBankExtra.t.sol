// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/GasBank.sol";
import "../src/GasRebateManager.sol";
import "../src/ShareSplitter.sol";
import "../src/Settings.sol";
import "../src/DegenPool.sol";
import "../src/FeeCollector.sol";

contract GasBankExtraTest is Test {
    GasBank gb;
    GasRebateManager gm;
    ShareSplitter splitter;
    Settings settings;
    GasBank gb2;
    DegenPool dp;
    FeeCollector fc;

    address sender = address(0xCAFE);
    address recipient = address(0xBEEF);

    function setUp() public {
        gb = new GasBank();
        gm = new GasRebateManager();
        dp = new DegenPool();
        fc = new FeeCollector();
        // create a second GasBank to test settings wiring separately when needed
        gb2 = new GasBank();
        settings = new Settings(address(gb), address(dp), address(fc));
        splitter = new ShareSplitter(address(settings));
    }

    function testAllowPublicDepositsToggleAndShareSplitterDeposit() public {
        // By default allowPublicDeposits == true
        vm.deal(sender, 1 ether);
        vm.prank(sender);
        (bool ok,) = address(gb).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(gb).balance, 1 ether);

        // Disable public deposits and configure shareSplitter
        gb.setShareSplitter(address(splitter));
        gb.setAllowPublicDeposits(false);

        // Non-splitter sender trying to deposit should revert
        vm.deal(sender, 0.5 ether);
        vm.prank(sender);
        vm.expectRevert(bytes("Deposits not allowed"));
        (bool ok2,) = address(gb).call{value: 0.5 ether}("");
        // ok2 might be false due to revert; ensure gb balance unchanged
        assertEq(address(gb).balance, 1 ether);

        // Use the splitter to deposit; first wire settings to use gb as gas bank
        // settings was already initialized with gb in setUp
        vm.deal(sender, 3 ether);
        vm.prank(sender);
        splitter.splitAndForward{value: 3 ether}();
        // splitter will forward its portion (400/750) to gb — check gb balance increased
        uint256 expectedFromSplit = (3 ether * 400) / 750;
        assertEq(address(gb).balance, 1 ether + expectedFromSplit);
    }

    function testWithdrawToAuthorizationAndInsufficientBalance() public {
        // set rebate manager to gm and fund gb
        gb.setRebateManager(address(gm));
        vm.deal(address(gb), 1 ether);
        assertEq(address(gb).balance, 1 ether);

        // A non-rebateManager cannot call withdrawTo
        vm.expectRevert(bytes("Not rebate manager"));
        gb.withdrawTo(recipient, 0.1 ether);
 
        // When rebateManager calls withdrawTo it succeeds — simulate by setting rebateManager to this test contract
        gb.setRebateManager(address(this));
        gb.withdrawTo(recipient, 0.2 ether);
        assertEq(address(gb).balance, 1 ether - 0.2 ether);

        // Withdraw with insufficient balance should revert
        uint256 balNow = address(gb).balance;
        vm.expectRevert(bytes("Insufficient balance"));
        gb.withdrawTo(recipient, balNow + 1);
    }

    function testOwnerCanRecoverAndSettersEmit() public {
        // set and emit checks
        vm.expectEmit(true, false, false, true);
        emit GasBank.RebateManagerUpdated(address(this));
        gb.setRebateManager(address(this));

        vm.expectEmit(true, false, false, true);
        emit GasBank.ShareSplitterUpdated(address(splitter));
        gb.setShareSplitter(address(splitter));

        vm.expectEmit(true, false, false, true);
        emit GasBank.AllowPublicDepositsUpdated(false);
        gb.setAllowPublicDeposits(false);

        // OwnerWithdraw works
        vm.deal(address(gb), 1 ether);
        address payable to = payable(recipient);
        gb.ownerWithdraw(to, 0.5 ether);
        // recipient got funds (in testing environment, recipient is an address; check contract balance decreased)
        assertEq(address(gb).balance, 0.5 ether);
    }
}