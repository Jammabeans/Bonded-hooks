// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MasterControl} from "../src/MasterControl.sol";
import {AccessControl} from "../src/AccessControl.sol";
import {PoolLaunchPad, ERC20Deployer} from "../src/PoolLaunchPad.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

contract MockTarget {
    event Called(bytes data);
    function doNothing(bytes calldata) external pure returns (bytes memory) { return abi.encodePacked(""); }
}

contract BlockProvenanceTest is Test, Deployers {
    MasterControl master;
    AccessControl access;
    PoolLaunchPad launchpad;
    address owner;

    function setUp() public {
        deployFreshManagerAndRouters();

        // Deploy MasterControl using the same pattern as other tests
        uint160 flags = uint160(Hooks.ALL_HOOK_MASK);
        deployCodeTo("MasterControl.sol:MasterControl", abi.encode(manager), address(flags));
        master = MasterControl(address(flags));
        owner = master.owner();

        access = new AccessControl();
        // grant ROLE_MASTER in AccessControl to the deployed MasterControl owner so master admin calls work
        access.grantRole(master.ROLE_MASTER(), owner);
        vm.prank(owner);
        master.setAccessControl(address(access));
 
        launchpad = new PoolLaunchPad(manager, access);
        access.setPoolLaunchPad(address(launchpad));
        vm.prank(owner);
        master.setPoolLaunchPad(address(launchpad));
    }

    function test_apply_immutable_block_prevents_removal_and_conflict_groups() public {
        // create pool via launchpad
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithNative("X","X",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 pidUint = uint256(PoolId.unwrap(pid));

        // set this contract as pool admin (force)
        vm.prank(address(launchpad));
        access.setPoolAdmin(pidUint, address(this));

        // deploy mock target
        MockTarget t = new MockTarget();
        bytes32 hookPath = keccak256("hookA");
        bytes4 sel = MockTarget.doNothing.selector;

        // owner approves command
        vm.prank(owner);
        master.approveCommand(hookPath, address(t), "noop");

        // create a block with one command
        MasterControl.Command[] memory cmds = new MasterControl.Command[](1);
        cmds[0] = MasterControl.Command({hookPath: hookPath, target: address(t), selector: sel, callType: MasterControl.CallType.Delegate});
 
        uint256 blockId = 100;
        vm.prank(owner);
        bool[] memory blkFlags = new bool[](cmds.length);
        master.createBlock(blockId, cmds, blkFlags, 0);

        // mark block immutable and set conflict group
        vm.prank(owner);
        master.setBlockMetadata(blockId, true, bytes32("grp1"));

        // apply block to pool as pool admin
        uint256[] memory ids = new uint256[](1);
        ids[0] = blockId;
        vm.prank(address(this));
        master.applyBlocksToPool(pidUint, ids);

        // verify provenance recorded
        uint256 origin = master.commandOriginBlock(pidUint, hookPath, address(t), sel);
        assertEq(origin, blockId);

        // verify locked
        bool locked = master.commandLockedForPool(pidUint, hookPath, address(t), sel);
        assert(locked);

        // attempt to clear should revert
        vm.prank(address(this));
        vm.expectRevert();
        master.clearCommands(pidUint, hookPath);

        // Now create another block with same conflict group and try apply -> should revert
        uint256 block2 = 101;
        vm.prank(owner);
        {
            bool[] memory flags2 = new bool[](cmds.length);
            master.createBlock(block2, cmds, flags2, 0);
        }
        vm.prank(owner);
        master.setBlockMetadata(block2, false, bytes32("grp1"));

        uint256[] memory ids2 = new uint256[](1);
        ids2[0] = block2;
        vm.prank(address(this));
        vm.expectRevert();
        master.applyBlocksToPool(pidUint, ids2);
    }
    function test_mixed_immutable_and_mutable_in_same_block() public {
        // create pool via launchpad
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithNative("Y","Y",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 pidUint = uint256(PoolId.unwrap(pid));

        // set this contract as pool admin (force)
        vm.prank(address(launchpad));
        access.setPoolAdmin(pidUint, address(this));

        // deploy mock target
        MockTarget t = new MockTarget();
        bytes32 hookA = keccak256("hookA");
        bytes32 hookB = keccak256("hookB");
        bytes4 sel = MockTarget.doNothing.selector;

        // owner approves command for both hook paths
        vm.prank(owner);
        master.approveCommand(hookA, address(t), "noopA");
        vm.prank(owner);
        master.approveCommand(hookB, address(t), "noopB");

        // create a block with two commands:
        // - cmd0: hookA, immutable via explicit flag
        // - cmd1: hookB, mutable
        MasterControl.Command[] memory cmds = new MasterControl.Command[](2);
        cmds[0] = MasterControl.Command({
            hookPath: hookA,
            target: address(t),
            selector: sel,
            callType: MasterControl.CallType.Delegate
        });
        cmds[1] = MasterControl.Command({
            hookPath: hookB,
            target: address(t),
            selector: sel,
            callType: MasterControl.CallType.Delegate
        });
 
        uint256 blockId = 200;
        vm.prank(owner);
        bool[] memory flags = new bool[](2);
        flags[0] = true; // first command immutable
        master.createBlock(blockId, cmds, flags, 0);

        // apply block to pool
        uint256[] memory ids = new uint256[](1);
        ids[0] = blockId;
        vm.prank(address(this));
        master.applyBlocksToPool(pidUint, ids);

        // Clearing the mutable hook (hookB) should succeed
        vm.prank(address(this));
        master.clearCommands(pidUint, hookB);
        // Ensure it's cleared (length == 0)
        MasterControl.Command[] memory readBack = master.getCommands(pidUint, hookB);
        assertEq(readBack.length, 0);

        // Clearing the immutable hook (hookA) should revert
        vm.prank(address(this));
        vm.expectRevert();
        master.clearCommands(pidUint, hookA);
    }

    function test_owner_revoke_does_not_remove_applied_commands() public {
        // create pool via launchpad
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithNative("Z","Z",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 pidUint = uint256(PoolId.unwrap(pid));

        // set this contract as pool admin (force)
        vm.prank(address(launchpad));
        access.setPoolAdmin(pidUint, address(this));

        // deploy mock target
        MockTarget t = new MockTarget();
        bytes32 hookPath = keccak256("hookRevoke");
        bytes4 sel = MockTarget.doNothing.selector;

        // owner approves command
        vm.prank(owner);
        master.approveCommand(hookPath, address(t), "noop");
 
        // create a block and mark immutable
        MasterControl.Command[] memory cmds = new MasterControl.Command[](1);
        cmds[0] = MasterControl.Command({hookPath: hookPath, target: address(t), selector: sel, callType: MasterControl.CallType.Delegate});
 
        uint256 blockId = 300;
        vm.prank(owner);
        bool[] memory flags1 = new bool[](1);
        flags1[0] = true;
        master.createBlock(blockId, cmds, flags1, 0);
 
        vm.prank(owner);
        master.setBlockMetadata(blockId, true, bytes32(0));

        // apply to pool
        uint256[] memory ids = new uint256[](1);
        ids[0] = blockId;
        vm.prank(address(this));
        master.applyBlocksToPool(pidUint, ids);

        // owner revokes the block (prevents future applies) — should not remove already-applied commands
        vm.prank(owner);
        master.revokeBlock(blockId);

        // verify that the command still exists on the pool and remains locked
        MasterControl.Command[] memory readBack = master.getCommands(pidUint, hookPath);
        assertEq(readBack.length, 1);
        bool locked = master.commandLockedForPool(pidUint, hookPath, address(t), sel);
        assert(locked);

        // Attempt to apply the same block to a different pool should fail because block is revoked
        (PoolId pid2, address tokenAddr2) = launchpad.createNewTokenAndInitWithNative("Z2","Z2",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 pid2Uint = uint256(PoolId.unwrap(pid2));
        vm.prank(address(launchpad));
        access.setPoolAdmin(pid2Uint, address(this));

        uint256[] memory ids2 = new uint256[](1);
        ids2[0] = blockId;
        vm.prank(address(this));
        vm.expectRevert();
        master.applyBlocksToPool(pid2Uint, ids2);
    }

    function test_conflict_group_alternatives_prevent_dual_apply() public {
        // create two pools
        (PoolId pid1, address token1) = launchpad.createNewTokenAndInitWithNative("C1","C1",100 ether,3000,60,1<<96, IHooks(address(master)));
        (PoolId pid2, address token2) = launchpad.createNewTokenAndInitWithNative("C2","C2",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 p1 = uint256(PoolId.unwrap(pid1));
        uint256 p2 = uint256(PoolId.unwrap(pid2));

        // set this contract as pool admin for both
        vm.prank(address(launchpad));
        access.setPoolAdmin(p1, address(this));
        vm.prank(address(launchpad));
        access.setPoolAdmin(p2, address(this));

        // deploy mock targets and approve
        MockTarget t1 = new MockTarget();
        MockTarget t2 = new MockTarget();
        bytes32 hp = keccak256("hookConflict");
        bytes4 sel = MockTarget.doNothing.selector;
        vm.prank(owner);
        master.approveCommand(hp, address(t1), "t1");
        vm.prank(owner);
        master.approveCommand(hp, address(t2), "t2");

        // Build two distinct blocks representing alternative implementations, same conflict group "alt"
        MasterControl.Command[] memory cmdsA = new MasterControl.Command[](1);
        cmdsA[0] = MasterControl.Command({hookPath: hp, target: address(t1), selector: sel, callType: MasterControl.CallType.Delegate});
        MasterControl.Command[] memory cmdsB = new MasterControl.Command[](1);
        cmdsB[0] = MasterControl.Command({hookPath: hp, target: address(t2), selector: sel, callType: MasterControl.CallType.Delegate});

        uint256 a = 400;
        uint256 b = 401;
        vm.prank(owner);
        bool[] memory fa = new bool[](cmdsA.length);
        master.createBlock(a, cmdsA, fa, 0);
        vm.prank(owner);
        bool[] memory fb = new bool[](cmdsB.length);
        master.createBlock(b, cmdsB, fb, 0);

        // mark both with same conflict group
        vm.prank(owner);
        master.setBlockMetadata(a, false, bytes32("alt"));
        vm.prank(owner);
        master.setBlockMetadata(b, false, bytes32("alt"));

        // apply block A to pool1 -> should succeed
        uint256[] memory idsA = new uint256[](1);
        idsA[0] = a;
        vm.prank(address(this));
        master.applyBlocksToPool(p1, idsA);

        // attempting to apply block B to same pool should revert due to conflict group
        uint256[] memory idsB = new uint256[](1);
        idsB[0] = b;
        vm.prank(address(this));
        vm.expectRevert();
        master.applyBlocksToPool(p1, idsB);

        // applying block B to pool2 (which has no active group) should succeed
        vm.prank(address(this));
        master.applyBlocksToPool(p2, idsB);
        // verify that pool2 has command from block B
        MasterControl.Command[] memory readBack2 = master.getCommands(p2, hp);
        assertEq(readBack2.length, 1);
        assertEq(readBack2[0].target, address(t2));
    }

    function test_setCommands_cannot_remove_immutable_command() public {
        // create pool via launchpad
        (PoolId pid, address tokenAddr) = launchpad.createNewTokenAndInitWithNative("S1","S1",100 ether,3000,60,1<<96, IHooks(address(master)));
        uint256 pidUint = uint256(PoolId.unwrap(pid));

        // set this contract as pool admin (force)
        vm.prank(address(launchpad));
        access.setPoolAdmin(pidUint, address(this));

        // deploy mock target and approve
        MockTarget t = new MockTarget();
        bytes32 hookA = keccak256("hookSetA");
        bytes4 sel = MockTarget.doNothing.selector;
        vm.prank(owner);
        master.approveCommand(hookA, address(t), "noopA");

        // create a block with one immutable command for hookA
        MasterControl.Command[] memory cmds = new MasterControl.Command[](1);
        cmds[0] = MasterControl.Command({
            hookPath: hookA,
            target: address(t),
            selector: sel,
            callType: MasterControl.CallType.Delegate
        });

        uint256 blockId = 500;
        vm.prank(owner);
        bool[] memory flags1 = new bool[](cmds.length);
        flags1[0] = false;
        master.createBlock(blockId, cmds, flags1, 0);
        vm.prank(owner);
        master.setBlockMetadata(blockId, true, bytes32(0));

        // apply the block to the pool
        uint256[] memory ids = new uint256[](1);
        ids[0] = blockId;
        vm.prank(address(this));
        master.applyBlocksToPool(pidUint, ids);

        // Attempt to remove immutable command via setCommands (empty array) should revert
        MasterControl.Command[] memory empty = new MasterControl.Command[](0);
        vm.prank(address(this));
        vm.expectRevert();
        master.setCommands(pidUint, hookA, empty);

        // Now perform a valid replacement that preserves the immutable command (same command re-inserted)
        MasterControl.Command[] memory keep = new MasterControl.Command[](1);
        keep[0] = MasterControl.Command({
            hookPath: hookA,
            target: address(t),
            selector: sel,
            callType: MasterControl.CallType.Delegate
        });
        vm.prank(address(this));
        master.setCommands(pidUint, hookA, keep);

        // Verify the command remains
        MasterControl.Command[] memory readBack = master.getCommands(pidUint, hookA);
        assertEq(readBack.length, 1);
        assertEq(readBack[0].target, address(t));
    }

}
