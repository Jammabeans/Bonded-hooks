// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PrizeBox} from "../src/PrizeBox.sol";
import {MockDegenShare, MockBondedShare} from "../src/interfaces/MocksAndInterfaces.sol";

contract PrizeBoxTest is Test {
    PrizeBox prizeBox;
    MockDegenShare degen;
    MockBondedShare bonded;
    address avs = address(this);
    address alice = address(1);

    function setUp() public {
        prizeBox = new PrizeBox(avs);
        degen = new MockDegenShare();
        bonded = new MockBondedShare();

        // Fund test + alice
        vm.deal(address(this), 10 ether);
        vm.deal(alice, 1 ether);
    }

    function test_create_register_and_open_box_burns_shares() public {
        // Mint share tokens to AVS (this) and approve PrizeBox to pull them
        uint256 amount = 100 ether;
        degen.mint(address(this), amount);
        degen.approve(address(prizeBox), amount);

        // Create a box owned by alice
        uint256 boxId = prizeBox.createBox(alice);

        // Register share tokens (transfers tokens from AVS/test into PrizeBox)
        prizeBox.registerShareTokens(boxId, address(degen), amount);

        // Deposit some ETH into the box
        uint256 ethDeposit = 1 ether;
        prizeBox.depositToBox{value: ethDeposit}(boxId);

        // Confirm box balance recorded
        (bool openedBefore, uint256 ethBalBefore) = prizeBox.boxes(boxId);
        assertFalse(openedBefore);
        assertEq(ethBalBefore, ethDeposit);

        // Now open the box as alice: should burn degen tokens and transfer ETH to alice
        // First check PrizeBox holds the degen tokens
        assertEq(degen.balanceOf(address(prizeBox)), amount);

        // Alice opens the box
        vm.prank(alice);
        prizeBox.openBox(boxId);

        // Box is now opened
        (bool openedAfter, uint256 ethBalAfter) = prizeBox.boxes(boxId);
        assertTrue(openedAfter);
        assertEq(ethBalAfter, 0);

        // Alice received ETH (initial 1 ETH + deposited 1 ETH)
        assertEq(alice.balance, 2 ether);

        // Degen tokens held by PrizeBox should be burned (balance decreased)
        assertEq(degen.balanceOf(address(prizeBox)), 0);
    }

    function test_erc721_transferability_and_award() public {
        // Create a box owned by this (avs)
        uint256 boxId = prizeBox.createBox(address(this));
        // Transfer box to alice via approve/transferFrom path
        prizeBox.approve(alice, boxId);
        vm.prank(alice);
        prizeBox.transferFrom(address(this), alice, boxId);

        // alice now owns it
        assertEq(prizeBox.ownerOf(boxId), alice);
    }
}