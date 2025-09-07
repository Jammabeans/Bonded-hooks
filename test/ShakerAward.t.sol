// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Shaker} from "../src/Shaker.sol";
import {PrizeBox} from "../src/PrizeBox.sol";
import {MockShareSplitter} from "../src/interfaces/MocksAndInterfaces.sol";

contract ShakerAwardTest is Test {
    Shaker shaker;
    PrizeBox prizeBox;
    MockShareSplitter splitter;
    address avs = address(this);
    address alice = address(1);

    function setUp() public {
        splitter = new MockShareSplitter();
        prizeBox = new PrizeBox(avs);
        shaker = new Shaker(address(splitter), address(prizeBox), avs);
        // Register shaker as authorized awarder in PrizeBox
        prizeBox.setShaker(address(shaker));

        // fund test contract so prize box deposits succeed if needed
        vm.deal(address(this), 5 ether);
        // fund alice for ticket buys
        vm.deal(alice, 1 ether);
    }

    function test_award_winner_box() public {
        // Create a box (AVS)
        uint256 boxId = prizeBox.createBox(address(this));
        // Start a round and make alice buy the last ticket (become leader)
        uint256 rid = shaker.startRound(300);

        // Read initial price and have alice buy
        ( , , , , , , , uint256 initPrice, ) = shaker.rounds(rid);
        vm.prank(alice);
        shaker.buyTicket{value: initPrice}(rid);

        // Warp past deadline
        ( , , , uint256 deadline, , , , , ) = shaker.rounds(rid);
        vm.warp(deadline + 1);

        // Finalize the round (AVS)
        uint256[] memory boxes = new uint256[](1);
        boxes[0] = boxId;
        shaker.finalizeRound(rid, boxes, 0xBEEF);

        // At this point the round is finalized and alice is the leader/winner
        ( , , , , address leader, , , , bool fin) = shaker.rounds(rid);
        assertTrue(fin);
        assertEq(leader, alice);

        // Now award the box to the round winner (AVS calls)
        shaker.awardWinnerBox(rid, boxId);

        // Verify prizeBox ownership is now alice
        address ownerOfBox = prizeBox.ownerOf(boxId);
        assertEq(ownerOfBox, alice);
    }
}