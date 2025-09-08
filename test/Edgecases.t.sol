// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import {Shaker} from "../src/Shaker.sol";
import {PrizeBox} from "../src/PrizeBox.sol";
import {MockShareSplitter, MockDegenShare} from "../src/interfaces/MocksAndInterfaces.sol";

contract EdgecasesTest is Test {
    Shaker shaker;
    PrizeBox prizeBox;
    MockShareSplitter splitter;
    MockDegenShare degen;
    address avs;
    address alice = address(1);
    address bob = address(2);

    function setUp() public {
        AccessControl acl = new AccessControl();
        avs = address(this);
        splitter = new MockShareSplitter();
        prizeBox = new PrizeBox(acl, avs);
        shaker = new Shaker(acl, address(splitter), address(prizeBox), avs);
        // register shaker as authorized awarder
        acl.grantRole(prizeBox.ROLE_PRIZEBOX_ADMIN(), address(this));
        acl.grantRole(shaker.ROLE_SHAKER_ADMIN(), address(this));
        prizeBox.setShaker(address(shaker));

        // mint a share token for tests
        degen = new MockDegenShare();
        degen.mint(address(this), 1000 ether);

        // fund accounts
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
    }

    /* ========== Shaker edge cases ========== */

    function test_finalize_before_deadline_reverts() public {
        uint256 rid = shaker.startRound(10);
        vm.expectRevert(bytes("Shaker: deadline not passed"));
        shaker.finalizeRound(rid, new uint256[](0), 0);
    }

    function test_buy_after_finalize_reverts() public {
        uint256 rid = shaker.startRound(11);
        // alice buys
        (, , , , , , , uint256 p, ) = shaker.rounds(rid);
        vm.prank(alice);
        shaker.buyTicket{value: p}(rid);

        // warp and finalize
        (, , , uint256 dl, , , , , ) = shaker.rounds(rid);
        vm.warp(dl + 1);
        uint256[] memory boxes = new uint256[](0);
        shaker.finalizeRound(rid, boxes, 0);

        // buy should revert
        vm.prank(bob);
        vm.expectRevert(bytes("Shaker: round finalized"));
        shaker.buyTicket{value: p}(rid);
    }

    function test_award_before_finalize_reverts_and_double_award_blocked() public {
        uint256 boxId = prizeBox.createBox(address(this));
        uint256 rid = shaker.startRound(12);
        (, , , , , , , uint256 p, ) = shaker.rounds(rid);
        vm.prank(alice);
        shaker.buyTicket{value: p}(rid);

        // Attempt to award before finalize should revert (round not finalized)
        vm.expectRevert(bytes("Shaker: round not finalized"));
        shaker.awardWinnerBox(rid, boxId);

        // finalize
        (, , , uint256 dl, , , , , ) = shaker.rounds(rid);
        vm.warp(dl + 1);
        uint256[] memory boxes = new uint256[](1);
        boxes[0] = boxId;
        shaker.finalizeRound(rid, boxes, 0);

        // award once — should succeed
        shaker.awardWinnerBox(rid, boxId);

        // second award should revert (already awarded)
        vm.expectRevert(bytes("Shaker: already awarded"));
        shaker.awardWinnerBox(rid, boxId);
    }

    /* ========== PrizeBox edge cases ========== */

    function test_open_without_shares_transfers_eth_and_reopen_reverts() public {
        uint256 boxId = prizeBox.createBox(alice);

        // deposit 1 ETH
        prizeBox.depositToBox{value: 1 ether}(boxId);

        // alice opens
        vm.prank(alice);
        prizeBox.openBox(boxId);

        // alice should have received 1 ETH
        assertEq(alice.balance, 6 ether); // started with 5 ether in setUp

        // reopen should revert
        vm.prank(alice);
        vm.expectRevert(bytes("PrizeBox: already opened"));
        prizeBox.openBox(boxId);
    }

    function test_register_shares_without_approval_reverts() public {
        uint256 boxId = prizeBox.createBox(address(this));
        // do NOT approve prizeBox to pull tokens
        degen.mint(address(this), 10 ether);
        // call registerShareTokens (msg.sender == avs in this test)
        vm.expectRevert();
        prizeBox.registerShareTokens(boxId, address(degen), 1 ether);
    }
}