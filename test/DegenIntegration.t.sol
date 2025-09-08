// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/DegenPool.sol";
import "../src/BidManager.sol";
import "../src/GasRebateManager.sol";
import "../src/GasBank.sol";

contract IntegrationTest is Test {
    DegenPool degen;
    BidManager bm;
    GasRebateManager gm;
    AccessControl acl;

    address pool = address(0x100);
    address bidder1 = address(0xB1);
    address bidder2 = address(0xB2);

    function setUp() public {
        // deploy central AccessControl and pass into refactored contracts
        acl = new AccessControl();
        degen = new DegenPool(acl);
        bm = new BidManager(acl);
        gm = new GasRebateManager(acl);
 
        // grant admin roles so this test contract can call admin APIs and configure settlement roles
        acl.grantRole(degen.ROLE_DEGEN_ADMIN(), address(this));
        acl.grantRole(bm.ROLE_BID_MANAGER_ADMIN(), address(this));
        acl.grantRole(gm.ROLE_GAS_REBATE_ADMIN(), address(this));
 
        // give settlement role to this test contract so it can call settlement functions
        degen.setSettlementRole(address(this), true);
        bm.setSettlementRole(address(this), true);
    }

    /// Basic flow:
    /// - mint active points for bidder1
    /// - pool deposits ETH
    /// - allocate deposits -> reward is attributable to existing points
    /// - bidder1 withdraws -> receives payout and points are halved
    function testActivePointsReceiveDepositsAndWithdrawBurnsHalf() public {
        // Mint active points now for bidder1 (settlement role)
        degen.mintPoints(bidder1, 1000, 1);
        assertEq(degen.points(bidder1), 1000);
        assertEq(degen.totalPoints(), 1000);

        // Simulate pool depositing 2 ETH
        vm.deal(pool, 2 ether);
        vm.prank(pool);
        (bool ok, ) = address(degen).call{value: 2 ether}("");
        require(ok, "deposit failed");

        // bidder1 should be able to withdraw the full 2 ETH since they hold all points
        uint256 beforeBalance = bidder1.balance;
        vm.prank(bidder1);
        degen.withdrawRewards();
        uint256 afterBalance = bidder1.balance;
        assertEq(afterBalance - beforeBalance, 2 ether);

        // points should be halved
        assertEq(degen.points(bidder1), 500);
        assertEq(degen.totalPoints(), 500);
    }

    /// Test pending behavior:
    /// - bidder1 active points exist
    /// - deposit1 -> allocated to active points only
    /// - batchMint points for bidder2 (they should NOT receive share of deposit1 because checkpointing sets their starting cumulative)
    /// - deposit2 -> bidder2 should receive share only from deposit2
    function testPendingPointsNotRetroactiveAndPaidAfterAllocation() public {
        // redeploy fresh DegenPool to reset state
        degen = new DegenPool(acl);
        degen.setSettlementRole(address(this), true);

        // bidder1 active points = 1000
        degen.mintPoints(bidder1, 1000, 1);

        // pool deposits 1 ETH -> allocate to bidder1 only
        vm.deal(pool, 1 ether);
        vm.prank(pool);
        (bool ok, ) = address(degen).call{value: 1 ether}("");
        require(ok);

        // Now batch mint points for bidder2. Because batchMintPoints checkpoints the user's
        // cumulative to the current cumulativeRewardPerPoint, bidder2 will not retroactively
        // receive rewards from the first deposit.
        address[] memory accounts = new address[](1);
        accounts[0] = bidder2;
        uint256[] memory pts = new uint256[](1);
        pts[0] = 1000;
        degen.batchMintPoints(accounts, pts, 2);

        // bidder2 should now have active points (checkpointed) and no pendingRewards from past deposits
        assertEq(degen.points(bidder2), 1000);
        assertEq(degen.getPendingRewards(bidder2), 0);

        // total points should be 2000 now
        assertEq(degen.totalPoints(), 2000);

        // Now deposit another 1 ETH; this deposit will be shared among current active points (both bidders)
        vm.deal(pool, 1 ether);
        vm.prank(pool);
        (bool ok2, ) = address(degen).call{value: 1 ether}("");
        require(ok2);

        // Now bidder2 withdraws: since both have 1000 points (total 2000), and only deposit2 (1 ETH)
        // bidder2 should get 0.5 ETH (1 ETH * 1000 / 2000)
        uint256 beforeBalance2 = bidder2.balance;
        vm.prank(bidder2);
        degen.withdrawRewards();
        uint256 afterBalance2 = bidder2.balance;
        assertEq(afterBalance2 - beforeBalance2, 0.5 ether);

        // bidder2's points should be halved
        assertEq(degen.points(bidder2), 500);
    }

    /// Full end-to-end flow:
    /// - operator credits rebates to bidders via GasRebateManager
    /// - bidders withdraw rebates and deposit proceeds into DegenPool
    /// - bidders create bids in BidManager
    /// - settle/consume bids and ownerRecoverBid routes consumed funds into DegenPool
    /// - assert final balances and state across contracts
    function testFullEndToEndFlow() public {
        // make this test contract an operator for gm and fund GasBank, then wire GasBank <-> GasRebateManager
        gm.setOperator(address(this), true);
        GasBank gb = new GasBank(acl);
        // grant GasBank admin role to this test contract so it can configure the bank
        acl.grantRole(gb.ROLE_GAS_BANK_ADMIN(), address(this));
        // configure GasBank and GasRebateManager so gm can pull funds
        gb.setRebateManager(address(gm));
        gm.setGasBank(address(gb));
        vm.deal(address(this), 3 ether);
        (bool okFund, ) = address(gb).call{value: 3 ether}("");
        require(okFund, "gb fund failed");

        // operator pushes rebates to bidders
        uint256 epoch = 100;
        address[] memory users = new address[](2);
        users[0] = bidder1;
        users[1] = bidder2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 ether;
        amounts[1] = 1 ether;
        gm.pushGasPoints(epoch, users, amounts);

        // bidders withdraw from GasRebateManager into their accounts
        vm.prank(bidder1);
        gm.withdrawGasRebate();
        vm.prank(bidder2);
        gm.withdrawGasRebate();

        // mint points so deposits will be allocated
        degen.mintPoints(bidder1, 1000, 1);
        degen.mintPoints(bidder2, 1000, 1);

        // bidders deposit some of their withdrawn ETH into the DegenPool
        // note: impersonate bidders and send ETH they withdrew earlier
        vm.prank(bidder1);
        (bool ok1, ) = address(degen).call{value: 1 ether}("");
        require(ok1, "deposit1 failed");
        vm.prank(bidder2);
        (bool ok2, ) = address(degen).call{value: 0.5 ether}("");
        require(ok2, "deposit2 failed");

        // bidders create bids in BidManager using remaining ETH
        vm.prank(bidder1);
        bm.createBid{value: 0.5 ether}(0, 0, 10);
        vm.prank(bidder2);
        bm.createBid{value: 0.25 ether}(0, 0, 20);

        // finalize epoch to consume parts of the bids (this test contract has settlement role)
        address[] memory bidAddrs = new address[](2);
        bidAddrs[0] = bidder1;
        bidAddrs[1] = bidder2;
        uint256[] memory consumed = new uint256[](2);
        consumed[0] = 0.3 ether;
        consumed[1] = 0.2 ether;
        bm.finalizeEpochConsumeBids(200, bidAddrs, consumed);

        // Move the consumed ETH (which remains in the contract balance) into DegenPool using ownerWithdraw
        // (finalizeEpochConsumeBids deducted bid balances but left ETH in the BidManager contract)
        bm.ownerWithdraw(payable(address(degen)), consumed[0] + consumed[1]);

        // Assert bids were debited
        assertEq(bm.getBid(bidder1).totalBidAmount, 0.5 ether - 0.3 ether);
        assertEq(bm.getBid(bidder2).totalBidAmount, 0.25 ether - 0.2 ether);

        // DegenPool contract balance should reflect deposits + recovered amounts
        uint256 expected = 1 ether + 0.5 ether + 0.3 ether + 0.2 ether; // deposits + recovered
        assertEq(address(degen).balance, expected);

        // cumulativeRewardPerPoint should have increased due to recovered deposits (since totalPoints > 0)
        assertGt(degen.cumulativeRewardPerPoint(), 0);
    }

}