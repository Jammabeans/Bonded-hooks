// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Bonding} from "../src/Bonding.sol";
import {AccessControl} from "../src/AccessControl.sol";

contract BondingTest is Test {
    Bonding bonding;
    AccessControl accessControl;
    address owner;
    address alice;
    address bob;
    address target; // representative command/target address

    function setUp() public {
        owner = address(this);
        accessControl = new AccessControl();
        bonding = new Bonding(accessControl);
 
        // Grant admin role so tests can perform owner-only operations under the new ACL model
        bytes32 ROLE_BONDING_ADMIN = keccak256("ROLE_BONDING_ADMIN");
        accessControl.grantRole(ROLE_BONDING_ADMIN, address(this));
 
        alice = address(1);
        bob = address(2);
        target = address(0xBEEF);
 
        // give test addresses some ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_native_bond_and_reward_flow() public {
        // Alice deposits 1 ETH as bond for target
        vm.prank(alice);
        bonding.depositBondNative{value: 1 ether}(target);

        // Owner (this) enables itself as authorized publisher
        bonding.setAuthorizedPublisher(address(this), true);

        // Record a fee of 0.5 ETH for the same target/currency (native)
        bonding.recordFee{value: 0.5 ether}(target, address(0), 0.5 ether);

        // Pending reward for Alice should equal 0.5 ETH
        uint256 pending = bonding.pendingReward(target, alice, address(0));
        assertEq(pending, 0.5 ether);

        // Alice claims rewards
        uint256 beforeBal = alice.balance;
        address[] memory t = new address[](1);
        address[] memory c = new address[](1);
        t[0] = target;
        c[0] = address(0);
        vm.prank(alice);
        bonding.claimRewards(t, c);
        uint256 afterBal = alice.balance;

        assertEq(afterBal - beforeBal, 0.5 ether);
    }

    function test_erc20_bond_and_reward_split() public {
        // Deploy mock ERC20 and distribute to bob and this test contract
        MockERC20 token = new MockERC20("TST", "TST", 18);
        token.mint(bob, 1000 ether);
        token.mint(address(this), 1000 ether);

        // Bob approves bonding and deposits 100 tokens
        vm.prank(bob);
        token.approve(address(bonding), 100 ether);
        vm.prank(bob);
        bonding.depositBondERC20(target, address(token), 100 ether);

        // Owner enables this test as publisher and approves bonding to pull tokens for recordFee
        bonding.setAuthorizedPublisher(address(this), true);
        token.approve(address(bonding), 50 ether);

        // Record a 50-token fee for target
        bonding.recordFee(target, address(token), 50 ether);

        // Bob's pending reward should equal 50 tokens
        uint256 pending2 = bonding.pendingReward(target, bob, address(token));
        assertEq(pending2, 50 ether);

        // Bob claims rewards -> receives 50 tokens
        uint256 beforeToken = token.balanceOf(bob);
        address[] memory tt = new address[](1);
        address[] memory cc = new address[](1);
        tt[0] = target;
        cc[0] = address(token);
        vm.prank(bob);
        bonding.claimRewards(tt, cc);
        uint256 afterToken = token.balanceOf(bob);
        assertEq(afterToken - beforeToken, 50 ether);
    }


    // --- Additional tests: multiple bonders, unallocated fees, authorized-withdrawer ---

    function test_multiple_bonders_and_split() public {
        // Alice deposits 1 ETH, Bob deposits 3 ETH => total 4 ETH
        vm.prank(alice);
        bonding.depositBondNative{value: 1 ether}(target);
        vm.prank(bob);
        bonding.depositBondNative{value: 3 ether}(target);

        // Enable publisher
        bonding.setAuthorizedPublisher(address(this), true);

        // Record a 0.4 ETH fee (should split 0.1 to Alice, 0.3 to Bob)
        bonding.recordFee{value: 0.4 ether}(target, address(0), 0.4 ether);

        uint256 pendingAlice = bonding.pendingReward(target, alice, address(0));
        uint256 pendingBob = bonding.pendingReward(target, bob, address(0));
        assertEq(pendingAlice, 0.1 ether);
        assertEq(pendingBob, 0.3 ether);

        // Claim and verify balances
        uint256 beforeAlice = alice.balance;
        uint256 beforeBob = bob.balance;

        address[] memory t1 = new address[](1);
        address[] memory c1 = new address[](1);
        t1[0] = target;
        c1[0] = address(0);

        vm.prank(alice);
        bonding.claimRewards(t1, c1);
        vm.prank(bob);
        bonding.claimRewards(t1, c1);

        assertEq(alice.balance - beforeAlice, 0.1 ether);
        assertEq(bob.balance - beforeBob, 0.3 ether);
    }

    function test_unallocated_fees_when_no_bonders() public {
        // Ensure no bonders exist for fresh target2
        address target2 = address(0xCAFE);
        bonding.setAuthorizedPublisher(address(this), true);

        // Record fee when there are no bonders
        bonding.recordFee{value: 1 ether}(target2, address(0), 1 ether);

        uint256 unallocated = bonding.unallocatedFees(target2, address(0));
        assertEq(unallocated, 1 ether);
    }

    function test_authorized_withdrawer_can_withdraw_principal_native() public {
        // Alice deposits 2 ETH
        vm.prank(alice);
        bonding.depositBondNative{value: 2 ether}(target);

        // Authorize withdrawer
        address withdrawer = address(3);
        address recipient = address(4);
        bonding.setAuthorizedWithdrawer(withdrawer, true);

        // Withdraw 1 ETH of Alice's principal to recipient
        vm.prank(withdrawer);
        bonding.withdrawBondFrom(target, alice, address(0), 1 ether, recipient);

        // Recipient received 1 ETH
        assertEq(recipient.balance, 1 ether);

        // Alice's remaining bond should be 1 ETH
        uint256 remaining = bonding.bondedAmount(target, alice, address(0));
        assertEq(remaining, 1 ether);
    }
}