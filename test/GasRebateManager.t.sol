// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/GasRebateManager.sol";

contract GasRebateManagerTest is Test {
    GasRebateManager gm;
    address operator = address(0xA11);
    address user1 = address(0xBEE1);
    address user2 = address(0xBEE2);

    // Re-declare events for vm.expectEmit checks
    event OperatorUpdated(address indexed operator, bool enabled);
    event GasPointsPushed(uint256 indexed epoch, address indexed operator, address[] users, uint256[] amounts);
    event RebateWithdrawn(address indexed user, uint256 amount);
    event Received(address indexed sender, uint256 amount);

    function setUp() public {
        gm = new GasRebateManager();
        // fund contract with 5 ether
        vm.deal(address(this), 10 ether);
        (bool ok, ) = address(gm).call{value: 5 ether}("");
        require(ok, "fund failed");

        // register operator
        gm.setOperator(operator, true);
    }

    function testPushAndWithdraw() public {
        uint256 epoch = 1;
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        // operator pushes the epoch credits
        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);

        // balances updated
        assertEq(gm.rebateBalance(user1), amounts[0]);
        assertEq(gm.rebateBalance(user2), amounts[1]);

        // record contract balance before withdraw
        uint256 contractBefore = address(gm).balance;
        assertEq(contractBefore, 5 ether);

        // have user1 withdraw
        vm.prank(user1);
        gm.withdrawGasRebate();

        // rebate balance cleared
        assertEq(gm.rebateBalance(user1), 0);

        // contract balance decreased by amounts[0]
        uint256 contractAfter = address(gm).balance;
        assertEq(contractAfter, contractBefore - amounts[0]);
    }

    function testCannotPushSameEpochTwice() public {
        uint256 epoch = 2;
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);

        vm.prank(operator);
        // expect revert due to epoch processed
        vm.expectRevert(bytes("Epoch already processed"));
        gm.pushGasPoints(epoch, users, amounts);
    }
    // New tests: non-operator push, underfunded withdraw, operator toggling

    function testPushByNonOperatorReverts() public {
        uint256 epoch = 10;
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // non-operator address tries to push
        address nonOp = address(0xC0);
        vm.prank(nonOp);
        vm.expectRevert(bytes("Caller is not an operator"));
        gm.pushGasPoints(epoch, users, amounts);
    }

    function testUnderfundedWithdrawRevertsAndBalanceIntact() public {
        // Drain contract to ensure it's underfunded
        address payable drainTo = payable(address(0xDD));
        uint256 contractBal = address(gm).balance;
        if (contractBal > 0) {
            gm.ownerWithdraw(drainTo, contractBal);
        }
        assertEq(address(gm).balance, 0);

        // Operator pushes credits larger than contract balance
        uint256 epoch = 20;
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);

        // User attempts to withdraw but contract has no funds => call should revert with ETH transfer failed
        vm.prank(user1);
        vm.expectRevert(bytes("ETH transfer failed"));
        gm.withdrawGasRebate();

        // Because the withdraw reverted, user's rebateBalance should remain unchanged
        assertEq(gm.rebateBalance(user1), amounts[0]);
    }

    function testOperatorEnableDisable() public {
        uint256 epoch = 30;
        address[] memory users = new address[](1);
        users[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // Disable operator
        gm.setOperator(operator, false);

        // Operator should no longer be able to push
        vm.prank(operator);
        vm.expectRevert(bytes("Caller is not an operator"));
        gm.pushGasPoints(epoch, users, amounts);

        // Re-enable and push should succeed
        gm.setOperator(operator, true);
        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);
 
        assertEq(gm.rebateBalance(user2), amounts[0]);
    }

    // Additional tests: events, multi-operator epoch prevention, multi-operator pushes

    function testEventEmissionsAndWithdrawEvent() public {
        uint256 epoch = 40;
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // Expect GasPointsPushed event
        vm.expectEmit(true, true, false, true);
        emit GasPointsPushed(epoch, operator, users, amounts);
        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);

        // Expect Received on deposit
        vm.expectEmit(true, false, false, true);
        emit Received(address(this), 0.1 ether);
        vm.deal(address(this), 0.1 ether);
        (bool ok, ) = address(gm).call{value: 0.1 ether}("");
        require(ok, "deposit failed");

        // Expect RebateWithdrawn when user withdraws
        uint256 beforeBal = user1.balance;
        vm.expectEmit(true, false, false, true);
        emit RebateWithdrawn(user1, 1 ether);
        vm.prank(user1);
        gm.withdrawGasRebate();
        assertEq(user1.balance - beforeBal, 1 ether);
    }

    function testSameEpochCannotBePushedByAnotherOperator() public {
        address op2 = address(0xB12);
        gm.setOperator(op2, true);

        uint256 epoch = 50;
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // operator1 pushes epoch 50
        vm.prank(operator);
        gm.pushGasPoints(epoch, users, amounts);

        // operator2 attempts to push same epoch => should revert
        vm.prank(op2);
        vm.expectRevert(bytes("Epoch already processed"));
        gm.pushGasPoints(epoch, users, amounts);
    }

    function testMultipleOperatorsPushDifferentEpochs() public {
        address op2 = address(0xB12);
        gm.setOperator(op2, true);

        // operator1 pushes epoch 60 to user1
        uint256 epoch1 = 60;
        address[] memory users1 = new address[](1);
        users1[0] = user1;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 1 ether;
        vm.prank(operator);
        gm.pushGasPoints(epoch1, users1, amounts1);

        // operator2 pushes epoch 61 to user2
        uint256 epoch2 = 61;
        address[] memory users2 = new address[](1);
        users2[0] = user2;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 2 ether;
        vm.prank(op2);
        gm.pushGasPoints(epoch2, users2, amounts2);

        // balances reflect both pushes
        assertEq(gm.rebateBalance(user1), amounts1[0]);
        assertEq(gm.rebateBalance(user2), amounts2[0]);
    }
}
