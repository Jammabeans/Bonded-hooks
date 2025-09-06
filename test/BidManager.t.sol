// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/BidManager.sol";

contract BidManagerTest is Test {
    BidManager bm;
    address bidder1 = address(0xB1);
    address bidder2 = address(0xB2);

    // Re-declare events so tests can use vm.expectEmit + emit(...) pattern
    event BidCreated(address indexed bidder, uint256 totalBidAmount, uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor);
    event BidToppedUp(address indexed bidder, uint256 amountWei);
    event BidConsumed(address indexed bidder, uint256 amountConsumed);

    function setUp() public {
        bm = new BidManager();
    }

    function testCreateAndTopUpAndConsume() public {
        // Fund bidders
        vm.deal(bidder1, 5 ether);
        vm.deal(bidder2, 5 ether);

        // bidder1 creates a bid of 1 ETH with rushFactor 100
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0, 0, 100);

        // bidder2 creates a bid of 2 ETH with rushFactor 200
        vm.prank(bidder2);
        bm.createBid{value: 2 ether}(0, 0, 200);

        // Verify stored bid amounts
        BidManager.Bid memory bid1 = bm.getBid(bidder1);
        address b1 = bid1.bidder;
        uint256 amt1 = bid1.totalBidAmount;
        BidManager.Bid memory bid2 = bm.getBid(bidder2);
        address b2 = bid2.bidder;
        uint256 amt2 = bid2.totalBidAmount;
        assertEq(b1, bidder1);
        assertEq(b2, bidder2);
        assertEq(amt1, 1 ether);
        assertEq(amt2, 2 ether);

        // Top up bidder1 by 0.5 ETH using direct call
        vm.prank(bidder1);
        bm.topUpBid{value: 0.5 ether}();

        BidManager.Bid memory bid1_after = bm.getBid(bidder1);
        uint256 amt1_after = bid1_after.totalBidAmount;
        assertEq(amt1_after, 1.5 ether);

        // Owner (this) sets settlement role to allow finalize
        bm.setSettlementRole(address(this), true);

        // Simulate consumption: consume 0.8 ETH from bidder1 and 1.2 ETH from bidder2 for epoch 1
        uint256 epoch = 1;
        address[] memory bidders = new address[](2);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        uint256[] memory consumed = new uint256[](2);
        consumed[0] = 0.8 ether;
        consumed[1] = 1.2 ether;

        bm.finalizeEpochConsumeBids(epoch, bidders, consumed);

        // Assert balances after consumption
        assertEq(bm.getBid(bidder1).totalBidAmount, 1.5 ether - 0.8 ether);
        assertEq(bm.getBid(bidder2).totalBidAmount, 2 ether - 1.2 ether);

        // Attempting to finalize same epoch again should revert
        vm.expectRevert(bytes("Epoch already processed"));
        bm.finalizeEpochConsumeBids(epoch, bidders, consumed);
    }

    // Test that createBid enforces minimum
    function testMinBidEnforced() public {
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        vm.expectRevert(bytes("Bid below minimum"));
        bm.createBid{value: 0.005 ether}(0,0,10);
    }

    function testCannotCreateSecondBidForSameAddress() public {
        vm.deal(bidder1, 3 ether);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,10);

        vm.prank(bidder1);
        vm.expectRevert(bytes("Bid exists"));
        bm.createBid{value: 1 ether}(0,0,20);
    }

    function testPendingRushAppliedTiming() public {
        vm.deal(bidder1, 3 ether);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,50); // initial rush 50

        // bidder updates rush factor (now applied immediately per new logic)
        vm.prank(bidder1);
        bm.updateRushFactor(100, 5);

        // Rush factor should be updated immediately
        assertEq(bm.getBid(bidder1).rushFactor, 100);
    }

    function testOwnerRecoverBidTransfersAndFailsOnInsufficient() public {
        vm.deal(bidder1, 3 ether);
        vm.prank(bidder1);
        bm.createBid{value: 2 ether}(0,0,30);

        // create a recipient to receive recovered funds
        address payable recipient = payable(address(0xCAFE));
        uint256 recBefore = address(recipient).balance;

        // Owner recovers 1 ether to recipient
        bm.ownerRecoverBid(bidder1, recipient, 1 ether);
        assertEq(address(recipient).balance, recBefore + 1 ether);

        // Remaining in bid should be 1 ether
        assertEq(bm.getBid(bidder1).totalBidAmount, 1 ether);

        // Attempt to recover more than remaining should revert
        vm.expectRevert(bytes("Insufficient bid balance"));
        bm.ownerRecoverBid(bidder1, recipient, 2 ether);
    }

    // New negative/edge-case and event tests
    function testFinalizeRequiresSettlementRole() public {
        vm.deal(bidder1, 2 ether);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,10);

        address[] memory biddersArr = new address[](1);
        biddersArr[0] = bidder1;
        uint256[] memory consumed = new uint256[](1);
        consumed[0] = 0.1 ether;

        vm.expectRevert(bytes("Caller is not settlement role"));
        bm.finalizeEpochConsumeBids(1, biddersArr, consumed);
    }

    function testEventsOnCreateTopUpAndConsume() public {
        vm.deal(bidder1, 3 ether);

        // Expect BidCreated
        vm.expectEmit(true, false, false, true);
        emit BidCreated(bidder1, 1 ether, 0, 0, 42);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,42);

        // Expect BidToppedUp
        vm.expectEmit(true, false, false, true);
        emit BidToppedUp(bidder1, 0.5 ether);
        vm.prank(bidder1);
        bm.topUpBid{value: 0.5 ether}();

        // Expect BidConsumed on finalize
        bm.setSettlementRole(address(this), true);
        address[] memory biddersArr = new address[](1);
        biddersArr[0] = bidder1;
        uint256[] memory consumed = new uint256[](1);
        consumed[0] = 0.3 ether;
        vm.expectEmit(true, false, false, true);
        emit BidConsumed(bidder1, 0.3 ether);
        bm.finalizeEpochConsumeBids(1, biddersArr, consumed);
    }

    function testTopUpOnlyByBidOwner() public {
        vm.deal(bidder1, 2 ether);
        vm.deal(bidder2, 2 ether);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,10);

        // bidder2 attempts to top-up (should revert: Unknown bid)
        vm.prank(bidder2);
        vm.expectRevert(bytes("Unknown bid"));
        bm.topUpBid{value: 1 ether}();
    }

    function testUpdateRushFactorEdgeCases() public {
        vm.deal(bidder1, 2 ether);
        vm.prank(bidder1);
        bm.createBid{value: 1 ether}(0,0,10);

        // newRush > MAX_RUSH should revert
        vm.prank(bidder1);
        vm.expectRevert(bytes("rushFactor out of range"));
        bm.updateRushFactor(1001, 1);

        // non-bidder cannot updateRushFactor
        vm.prank(bidder2);
        vm.expectRevert(bytes("Unknown bid"));
        bm.updateRushFactor(20, 1);
    }
}