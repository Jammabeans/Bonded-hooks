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
        vm.prank(owner);
        master.setAccessControl(address(access));

        launchpad = new PoolLaunchPad(manager, access);
        access.setPoolLaunchPad(address(launchpad));
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
        master.approveCommand(hookPath, address(t), sel, "noop");

        // create a block with one command
        MasterControl.Command[] memory cmds = new MasterControl.Command[](1);
        cmds[0] = MasterControl.Command({hookPath: hookPath, target: address(t), selector: sel, data: "", callType: MasterControl.CallType.Delegate});

        uint256 blockId = 100;
        vm.prank(owner);
        master.createBlock(blockId, cmds, 0);

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
        vm.expectRevert(bytes("MasterControl: contains locked command"));
        master.clearCommands(pidUint, hookPath);

        // Now create another block with same conflict group and try apply -> should revert
        uint256 block2 = 101;
        vm.prank(owner);
        master.createBlock(block2, cmds, 0);
        vm.prank(owner);
        master.setBlockMetadata(block2, false, bytes32("grp1"));

        uint256[] memory ids2 = new uint256[](1);
        ids2[0] = block2;
        vm.prank(address(this));
        vm.expectRevert(bytes("MasterControl: conflict group active"));
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
        master.approveCommand(hookA, address(t), sel, "noopA");
        vm.prank(owner);
        master.approveCommand(hookB, address(t), sel, "noopB");

        // create a block with two commands:
        // - cmd0: hookA, immutable flag set via data's first byte
        // - cmd1: hookB, mutable (empty data)
        MasterControl.Command[] memory cmds = new MasterControl.Command[](2);
        cmds[0] = MasterControl.Command({
            hookPath: hookA,
            target: address(t),
            selector: sel,
            data: abi.encodePacked(bytes1(0x01)), // IMMUTABLE_DATA_FLAG
            callType: MasterControl.CallType.Delegate
        });
        cmds[1] = MasterControl.Command({
            hookPath: hookB,
            target: address(t),
            selector: sel,
            data: "",
            callType: MasterControl.CallType.Delegate
        });

        uint256 blockId = 200;
        vm.prank(owner);
        master.createBlock(blockId, cmds, 0);

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
        vm.expectRevert(bytes("MasterControl: contains locked command"));
        master.clearCommands(pidUint, hookA);
    }
}