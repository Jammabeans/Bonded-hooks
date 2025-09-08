// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import {PrizeBox} from "../src/PrizeBox.sol";
import {Shaker} from "../src/Shaker.sol";
import {MockShareSplitter, MockBurnableERC20} from "../src/interfaces/MocksAndInterfaces.sol";

/// Malicious token that reverts on burnFrom to test openBox failure propagation
    contract MaliciousBurnToken {
        mapping(address => uint256) public balanceOf;
        mapping(address => mapping(address => uint256)) public allowance;
        string public name = "MB";
        string public symbol = "MB";
        uint8 public decimals = 18;

        function mint(address to, uint256 amount) external {
            balanceOf[to] += amount;
        }
        function approve(address spender, uint256 amount) external returns (bool) {
            allowance[msg.sender][spender] = amount;
            return true;
        }
        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            require(balanceOf[from] >= amount, "insufficient");
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            return true;
        }
        function transfer(address to, uint256 amount) external returns (bool) {
            require(balanceOf[msg.sender] >= amount, "insufficient");
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
            return true;
        }
        // burnFrom always reverts
        function burnFrom(address, uint256) external pure {
            revert("malicious burn");
        }
    }

/// @notice Additional edge-case tests: multiple ERC20 deposits, malicious burn behavior, and access control negatives.
contract MoreEdgecases is Test {
    PrizeBox prizeBox;
    Shaker shaker;
    MockShareSplitter splitter;
    MockBurnableERC20 tokenA;
    MockBurnableERC20 tokenB;
    address avs = address(this);
    address alice = address(1);
    address other = address(2);

    function setUp() public {
        AccessControl acl = new AccessControl();
        splitter = new MockShareSplitter();
        prizeBox = new PrizeBox(acl, avs);
        shaker = new Shaker(acl, address(splitter), address(prizeBox), avs);
        // authorize shaker as awarder
        acl.grantRole(prizeBox.ROLE_PRIZEBOX_ADMIN(), address(this));
        acl.grantRole(shaker.ROLE_SHAKER_ADMIN(), address(this));
        prizeBox.setShaker(address(shaker));

        tokenA = new MockBurnableERC20("A","A",18);
        tokenB = new MockBurnableERC20("B","B",18);

        // mint tokens to this test address for deposits/registrations
        tokenA.mint(address(this), 1000 ether);
        tokenB.mint(address(this), 1000 ether);

        vm.deal(alice, 5 ether);
    }

    function test_multiple_erc20_deposits_recorded() public {
        uint256 boxId = prizeBox.createBox(address(this));

        // approve and deposit tokenA and tokenB
        tokenA.approve(address(prizeBox), 10 ether);
        prizeBox.depositToBoxERC20(boxId, address(tokenA), 10 ether);

        tokenB.approve(address(prizeBox), 5 ether);
        prizeBox.depositToBoxERC20(boxId, address(tokenB), 5 ether);

        assertEq(prizeBox.boxERC20(boxId, address(tokenA)), 10 ether);
        assertEq(prizeBox.boxERC20(boxId, address(tokenB)), 5 ether);
    }    

    function test_open_with_malicious_burn_reverts() public {
        // Deploy malicious token and mint to AVS (this)
        MaliciousBurnToken mal = new MaliciousBurnToken();
        mal.mint(address(this), 100 ether);
        // approve prizeBox to pull tokens
        // Note: registerShareTokens will call transferFrom from AVS to prizeBox
        mal.approve(address(prizeBox), 100 ether);

        // create box assigned to alice
        uint256 boxId = prizeBox.createBox(alice);

        // register malicious shares (transfers tokens into PrizeBox)
        // Should succeed (transferFrom returns true)
        prizeBox.registerShareTokens(boxId, address(mal), 100 ether);

        // deposit 1 ETH so there's something to transfer
        prizeBox.depositToBox{value: 1 ether}(boxId);

        // Now opening should attempt to burn and that burn will revert -> openBox should revert
        vm.prank(alice);
        vm.expectRevert(bytes("malicious burn"));
        prizeBox.openBox(boxId);
    }

    function test_access_control_admin_methods_negative() public {
        // non-owner (alice) attempts to set AVS / shaker / shareSplitter
        vm.prank(alice);
        vm.expectRevert(bytes("PrizeBox: not admin"));
        prizeBox.setShaker(address(0x123));

        vm.prank(alice);
        vm.expectRevert(bytes("Shaker: not admin"));
        shaker.setAVS(address(0x123));

        vm.prank(alice);
        vm.expectRevert(bytes("Shaker: not admin"));
        shaker.setShareSplitter(address(0x123));
    }
}