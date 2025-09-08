// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import {Shaker} from "../src/Shaker.sol";
import {PrizeBox} from "../src/PrizeBox.sol";
import {MockShareSplitter, MockDegenShare, MockBondedShare} from "../src/interfaces/MocksAndInterfaces.sol";

contract ShakerTest is Test {
    Shaker public shaker;
    PrizeBox public prizeBox;
    MockShareSplitter public splitter;
    address public avs;
    address public alice = address(1);
    address public bob = address(2);

    function setUp() public {
        // Deploy ACL and mock components
        AccessControl acl = new AccessControl();
        splitter = new MockShareSplitter();
        avs = address(this);
        prizeBox = new PrizeBox(acl, avs);
        shaker = new Shaker(acl, address(splitter), address(prizeBox), avs);
 
        // grant admin roles so this test can call admin APIs
        acl.grantRole(keccak256("ROLE_PRIZEBOX_ADMIN"), address(this));
        acl.grantRole(keccak256("ROLE_SHAKER_ADMIN"), address(this));
 
        // Fund test contract so PrizeBox deposits succeed if needed
        vm.deal(address(this), 10 ether);
    }

    /// @notice Minimal test: start a round and buy tickets; verify pot, ticketCount and price behavior
    function test_buy_ticket_flow() public {
        uint256 rid = shaker.startRound(100);

        // initial price
        ( , , , , , , , uint256 initPrice, ) = shaker.rounds(rid);
        assertEq(initPrice, shaker.ticketStartPrice());

        // Alice buys at initPrice
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        shaker.buyTicket{value: initPrice}(rid);

        // read state after alice
        ( , , , , , uint256 pot1, uint256 tc1, uint256 price1, ) = shaker.rounds(rid);
        assertEq(tc1, 1);
        assertEq(pot1, initPrice);
        assertTrue(price1 > initPrice);

        // Bob buys and overpays
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        shaker.buyTicket{value: price1 + 0.001 ether}(rid);

        ( , , , , address leader, uint256 pot2, uint256 tc2, uint256 price2, ) = shaker.rounds(rid);
        assertEq(leader, bob);
        assertEq(tc2, 2);
        assertEq(pot2, pot1 + price1 + 0.001 ether);
        assertTrue(price2 > price1);
    }

    /// @notice Minimal finalize test: ensure splits forward to ShareSplitter as expected.
    /// This test keeps assertions small to avoid stack pressure in the compiler.
    function test_finalize_forward_splits_to_splitter() public {
        uint256 rid = shaker.startRound(200);

        // initial price
        ( , , , , , , , uint256 initPrice, ) = shaker.rounds(rid);

        // Two buys to create a pot
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        shaker.buyTicket{value: initPrice}(rid);

        ( , , , , , , , uint256 priceAfter1, ) = shaker.rounds(rid);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        shaker.buyTicket{value: priceAfter1}(rid);

        // read pot and deadline
        ( , , , uint256 deadline, , uint256 pot, , , ) = shaker.rounds(rid);

        // warp past deadline
        vm.warp(deadline + 1);

        // create some boxes to accept prize deposits (we won't assert box balances here)
        uint256 b1 = prizeBox.createBox(address(this));
        uint256 b2 = prizeBox.createBox(address(this));
        uint256[] memory boxes = new uint256[](2);
        boxes[0] = b1;
        boxes[1] = b2;

        // finalize (AVS)
        shaker.finalizeRound(rid, boxes, 0xDEADBEEF);

        // expected split amounts forwarded to splitter
        uint256 prizeBoxAmount = (pot * shaker.prizeBoxesBips()) / shaker.BIPS_DENOM();
        uint256 lpAmount = (pot * shaker.lpBips()) / shaker.BIPS_DENOM();
        uint256 otherAmount = pot - prizeBoxAmount - lpAmount;

        // splitter should have received lp + other forwarded
        assertEq(splitter.receivedPerPool(200), lpAmount + otherAmount);
    }
}