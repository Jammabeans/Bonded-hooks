// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/ShareSplitter.sol";
import "../src/Settings.sol";
import "../src/GasBank.sol";
import "../src/DegenPool.sol";
import "../src/FeeCollector.sol";

contract ShareSplitterTest is Test {
    Settings settings;
    ShareSplitter splitter;
    GasBank gb;
    DegenPool dp;
    FeeCollector fc;
    address sender = address(0xABC);

    // re-declare SplitExecuted and DepositReceived events for vm.expectEmit pattern
    event SplitExecuted(address indexed sender, uint256 amount, address[] recipients, uint256[] amounts);
    event DepositReceived(address indexed from, uint256 amount);

    function setUp() public {
        gb = new GasBank();
        dp = new DegenPool();
        fc = new FeeCollector();
        settings = new Settings(address(gb), address(dp), address(fc));
        splitter = new ShareSplitter(address(settings));
    }

    function testSplitAndForwardBasic() public {
        // Setup funds for sender
        vm.deal(sender, 3 ether);
 
        // Expect SplitExecuted with recipients and weights; amounts will be (400/750,250/750,100/750)
        vm.expectEmit(true, false, false, true);
        address[] memory recips = new address[](3);
        recips[0] = address(gb);
        recips[1] = address(dp);
        recips[2] = address(fc);
        uint256[] memory amts = new uint256[](3);
        amts[0] = (3 ether * 400) / 750;
        amts[1] = (3 ether * 250) / 750;
        amts[2] = (3 ether * 100) / 750;
        emit SplitExecuted(sender, 3 ether, recips, amts);
 
        vm.prank(sender);
        splitter.splitAndForward{value: 3 ether}();
        // Check balances
        assertEq(address(gb).balance, amts[0]);
        assertEq(address(dp).balance, amts[1]);
        assertEq(address(fc).balance, amts[2]);
    }

    function testRemainderGoesToLastRecipient() public {
        // Use an amount that creates a remainder when divided
        uint256 amount = 1 wei;
        vm.deal(sender, amount);
        vm.prank(sender);

        // Read default shares to compute expected distribution and remainder
        (address[] memory recips, uint256[] memory weights) = settings.getDefaultShares();
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) totalWeight += weights[i];

        uint256 distributed = 0;
        uint256[] memory expected = new uint256[](recips.length);
        for (uint256 i = 0; i < recips.length; i++) {
            expected[i] = (amount * weights[i]) / totalWeight;
            distributed += expected[i];
        }
        uint256 remainder = amount - distributed;
        expected[recips.length - 1] += remainder;

        vm.prank(sender);
        splitter.splitAndForward{value: amount}();

        for (uint256 i = 0; i < recips.length; i++) {
            assertEq(address(recips[i]).balance, expected[i]);
        }
    }

    function testOwnerCanSetCustomSharesForSender() public {
        // Create a custom split for sender with 2 recipients
        address[] memory recips = new address[](2);
        recips[0] = address(0x111);
        recips[1] = address(0x222);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 3;
        weights[1] = 7;

        // settings is owned by this test contract
        settings.setCustomSharesFor(sender, recips, weights);

        // Now split 10 wei from sender and verify recipients get the custom shares
        uint256 amount = 10 wei;
        vm.deal(sender, amount);
        vm.prank(sender);
        splitter.splitAndForward{value: amount}();

        // Check computed shares
        uint256 totalWeight = 10;
        uint256 a0 = (amount * weights[0]) / totalWeight;
        uint256 a1 = (amount * weights[1]) / totalWeight;
        uint256 distributed = a0 + a1;
        uint256 remainder = amount - distributed;
        a1 += remainder;

        assertEq(address(recips[0]).balance, a0);
        assertEq(address(recips[1]).balance, a1);
    }

    function testZeroValueReverts() public {
        vm.prank(sender);
        vm.expectRevert(bytes("No ETH"));
        splitter.splitAndForward{value: 0}();
    }
}