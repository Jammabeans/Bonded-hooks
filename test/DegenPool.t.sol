// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/DegenPool.sol";

contract DegenPoolTest is Test {
    DegenPool degen;
    address user1 = address(0xA1);

    // Re-declare events used for vm.expectEmit verification in tests
    event PointsMinted(address indexed account, uint256 pts, uint256 epoch);
    event DepositReceived(address indexed from, uint256 amount);
    event RewardsWithdrawn(address indexed account, uint256 amountPaid, uint256 pointsBurned);

    function setUp() public {
        degen = new DegenPool();
        // this test contract is the owner by default; set settlement role to this contract
        degen.setSettlementRole(address(this), true);
    }

    function testMintAndWithdrawBurnsHalfPoints() public {
        // Mint 1000 points to user1 via settlement role (this)
        uint256 epoch = 1;
        uint256 minted = 1000;
        degen.mintPoints(user1, minted, epoch);

        // Points and totalPoints reflect mint
        assertEq(degen.points(user1), minted);
        assertEq(degen.totalPoints(), minted);

        // Fund the DegenPool with 1 ETH from the test runner
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");

        // Confirm contract has balance
        assertEq(address(degen).balance, 1 ether);

        // Record user balance before withdraw
        uint256 userBefore = user1.balance;

        // Have user1 withdraw rewards (prank sets msg.sender)
        vm.prank(user1);
        degen.withdrawRewards();

        // Expected payout = contractBalance_before * userPts / totalPoints
        // Since user had all points (1000/1000), they should receive the full 1 ETH
        uint256 userAfter = user1.balance;
        assertEq(userAfter - userBefore, 1 ether);

        // Points should be halved (penalty)
        assertEq(degen.points(user1), minted / 2);

        // totalPoints decreased by burned amount
        assertEq(degen.totalPoints(), minted / 2);
    }

    function testWithdrawRequiresPointsAndFunds() public {
        // No points -> withdraw reverts
        vm.prank(user1);
        vm.expectRevert(bytes("Payout zero"));
        degen.withdrawRewards();
        
    }

    function testBatchMintAndMultipleWithdraws() public {
        address user2 = address(0xA2);
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;
        uint256[] memory pts = new uint256[](2);
        pts[0] = 1000;
        pts[1] = 1000;

        degen.batchMintPoints(accounts, pts, 1);
        assertEq(degen.points(user1), 1000);
        assertEq(degen.points(user2), 1000);
        assertEq(degen.totalPoints(), 2000);

        // Deposit 2 ETH to contract
        vm.deal(address(this), 2 ether);
        (bool ok, ) = address(degen).call{value: 2 ether}("");
        require(ok);

        // user1 withdraws: should receive 1 ETH (1000/2000 * 2 ETH)
        vm.prank(user1);
        degen.withdrawRewards();
        assertEq(degen.points(user1), 500);
        assertEq(degen.totalPoints(), 1500); // burned 500

        // user2 withdraws: now his share is 1000/1500 of remaining balance (contract balance is 1 ETH)
        // Expected payout = 1 ETH * 1000 / 1500 = 2/3 ETH (rounded down)
        uint256 before2 = user2.balance;
        vm.prank(user2);
        degen.withdrawRewards();
        uint256 after2 = user2.balance;
        // Check that some ETH was received and points halved
        assertGt(after2 - before2, 0);
        assertEq(degen.points(user2), 500);
    }
    // New tests: deposit-without-points, batch mint moves owed => pending, receive zero-value behavior

    function testDepositWhenNoPointsDoesNotIncreaseCumulative() public {
        // Ensure no points initially
        assertEq(degen.totalPoints(), 0);
        assertEq(degen.cumulativeRewardPerPoint(), 0);

        // Deposit 1 ETH while totalPoints == 0
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");
        // cumulativeRewardPerPoint should remain zero and contract should hold funds
        assertEq(degen.cumulativeRewardPerPoint(), 0);
        assertEq(address(degen).balance, 1 ether);

        // Now mint points; these points should not retroactively claim the prior 1 ETH
        uint256 minted = 1000;
        degen.mintPoints(user1, minted, 1);

        // Deposit 2 ETH which should be distributed over active points
        vm.deal(address(this), 2 ether);
        (ok, ) = address(degen).call{value: 2 ether}("");
        require(ok, "deposit2 failed");

        // Now user1 should be able to withdraw only the portion allocated after points existed (2 ETH),
        uint256 userBefore = user1.balance;
        vm.prank(user1);
        degen.withdrawRewards();
        assertEq(user1.balance - userBefore, 2 ether);

        // The original 1 ETH remains held in contract (unallocated)
        assertEq(address(degen).balance, 1 ether);
    }

    function testBatchMintMovesOwedToPending() public {
        // Mint initial points to user1
        degen.mintPoints(user1, 1000, 1);

        // Deposit 1 ETH to increase cumulativeRewardPerPoint
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");

        // Now batch mint more points to same user; owed amount should move to pendingRewards
        address[] memory accounts = new address[](1);
        accounts[0] = user1;
        uint256[] memory pts = new uint256[](1);
        pts[0] = 500;
        degen.batchMintPoints(accounts, pts, 2);

        // pendingRewards should reflect the owed amount from before the mint (1 ETH)
        uint256 pending = degen.getPendingRewards(user1);
        assertEq(pending, 1 ether);

        // Withdraw should pay the pending rewards (1 ETH) and clear pending
        uint256 before = user1.balance;
        vm.prank(user1);
        degen.withdrawRewards();
        assertEq(user1.balance - before, 1 ether);
        assertEq(degen.getPendingRewards(user1), 0);
    }

    function testReceiveZeroValueCallReturnsFalse() public {
        // Low-level call with zero value should fail because receive() requires msg.value > 0
        (bool ok, ) = address(degen).call{value: 0}("");
        assertEq(ok, false);
    }
    function testCumulativeScalingRemainderAndDistribution() public {
        // Two users with unequal points to exercise rounding remainders
        address user2 = address(0xA2);
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;
        uint256[] memory pts = new uint256[](2);
        pts[0] = 1;
        pts[1] = 2; // totalPoints = 3

        degen.batchMintPoints(accounts, pts, 1);
        assertEq(degen.totalPoints(), 3);

        // Deposit 1 wei (small amount causing rounding)
        vm.deal(address(this), 1 wei);
        (bool ok, ) = address(degen).call{value: 1 wei}("");
        require(ok, "deposit failed");

        uint256 cum = degen.cumulativeRewardPerPoint();
        uint256 last1 = degen.userCumPerPoint(user1);
        uint256 last2 = degen.userCumPerPoint(user2);

        uint256 owed1 = (degen.points(user1) * (cum - last1)) / degen.SCALE();
        uint256 owed2 = (degen.points(user2) * (cum - last2)) / degen.SCALE();

        // The sum of owed amounts must be <= deposit and the leftover remainder must be less than totalPoints
        uint256 sumOwed = owed1 + owed2;
        assertLe(sumOwed, 1 wei);
        assertLt(1 wei - sumOwed, degen.totalPoints());
    }

    function testOwnerWithdrawAccessAndInsufficientBalance() public {
        // Fund contract with 1 ETH and have owner withdraw it
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");

        address payable recipient = payable(address(0xDEAD));
        uint256 before = address(recipient).balance;

        // owner (this) withdraws successfully
        degen.ownerWithdraw(recipient, 1 ether);
        assertEq(address(recipient).balance - before, 1 ether);
        assertEq(address(degen).balance, 0);

        // Non-owner cannot call ownerWithdraw
        vm.deal(address(this), 0.5 ether);
        (ok, ) = address(degen).call{value: 0.5 ether}("");
        require(ok, "deposit2 failed");
        vm.prank(user1);
        vm.expectRevert(bytes("OwnableUnauthorizedAccount(0x00000000000000000000000000000000000000A1)"));
        degen.ownerWithdraw(recipient, 0);

        // Owner withdraw with insufficient balance should revert
        vm.expectRevert(bytes("Insufficient balance"));
        degen.ownerWithdraw(recipient, 1 ether);
    }
    function testMultiEpochFlow() public {
        // Mint initial points, deposit, mint more (moves owed -> pending), deposit again, then withdraw
        vm.deal(address(this), 1 ether);
        degen.mintPoints(user1, 1000, 1);

        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");

        // Mint additional points (should move owed from existing points into pending)
        degen.mintPoints(user1, 500, 2);
        uint256 pending = degen.getPendingRewards(user1);
        assertEq(pending, 1 ether);

        // Deposit another 0.5 ETH which will be shared across current active points (1500)
        vm.deal(address(this), 0.5 ether);
        (ok, ) = address(degen).call{value: 0.5 ether}("");
        require(ok, "deposit2 failed");

        // Withdraw: should receive pending (1 ETH) + owed from active points (0.5 ETH) = 1.5 ETH
        uint256 before = user1.balance;
        vm.prank(user1);
        degen.withdrawRewards();
        assertEq(user1.balance - before, 1.5 ether - 1); // allow 1 wei rounding tolerance

        // Points should be halved (1500 / 2)
        assertEq(degen.points(user1), 750);
    }

    function testEventEmissions() public {
        uint256 minted = 100;
        // Expect PointsMinted
        vm.expectEmit(true, false, false, true);
        emit PointsMinted(user1, minted, 1);
        degen.mintPoints(user1, minted, 1);

        // Expect DepositReceived
        vm.deal(address(this), 1 ether);
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(address(this), 1 ether);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok, "deposit failed");

        // Expect RewardsWithdrawn when user withdraws entire share
        // Setup: user has all points so withdraw should pay 1 ETH and burn half
        uint256 beforeBal = user1.balance;
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RewardsWithdrawn(user1, 1 ether, minted / 2);
        degen.withdrawRewards();
        assertEq(user1.balance - beforeBal, 1 ether);
    }

    function testMultipleSmallDepositsRoundingRegression() public {
        address user2 = address(0xA2);
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;
        uint256[] memory pts = new uint256[](2);
        pts[0] = 3;
        pts[1] = 7; // totalPoints = 10

        degen.batchMintPoints(accounts, pts, 1);
        assertEq(degen.totalPoints(), 10);

        // Make multiple 1-wei deposits to exercise rounding behavior
        uint256 deposits = 10;
        for (uint256 i = 0; i < deposits; i++) {
            vm.deal(address(this), 1 wei);
            (bool ok, ) = address(degen).call{value: 1 wei}("");
            require(ok, "small deposit failed");
        }

        uint256 cum = degen.cumulativeRewardPerPoint();
        uint256 owed1 = (degen.points(user1) * (cum - degen.userCumPerPoint(user1))) / degen.SCALE();
        uint256 owed2 = (degen.points(user2) * (cum - degen.userCumPerPoint(user2))) / degen.SCALE();

        // Total owed must be <= total deposited and remainder should be less than totalPoints
        uint256 sumOwed = owed1 + owed2;
        assertLe(sumOwed, deposits);
        assertLt(deposits - sumOwed, degen.totalPoints());
    }
}
