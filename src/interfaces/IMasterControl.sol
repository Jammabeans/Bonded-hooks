// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title IMasterControl
/// @notice Interface for the MasterControl dispatcher / admin contract.
interface IMasterControl {
    enum CallType { Delegate, Call }

    struct Command {
        bytes32 hookPath;
        address target;
        bytes4 selector;
        CallType callType;
    }

    // Events (subset)
    event BlockCreated(uint256 indexed blockId, bytes32 indexed hookPath, bytes32 commandsHash);
    event BlockRevoked(uint256 indexed blockId);
    event BlockApplied(uint256 indexed blockId, uint256 indexed poolId, bytes32 indexed hookPath);
    event CommandsSet(uint256 indexed poolId, bytes32 indexed hookPath, bytes32 commandsHash);
    event PoolFeeBipsUpdated(uint256 indexed poolId, uint256 totalFeeBips);
    event CommandApproved(bytes32 indexed hookPath, address indexed target, string name);
    event CommandToggled(bytes32 indexed hookPath, address indexed target, bool enabled);
    event MemoryCardDeployed(address indexed memoryCard);

    // Governance / approval
    function approveCommand(bytes32 hookPath, address target, string calldata name) external;
    function setCommandEnabled(bytes32 hookPath, address target, bool enabled) external;

    // Configuration
    function setAccessControl(address _accessControl) external;
    function setMemoryCard(address _mc) external;
    function setAllowedConfigKey(bytes32 key, bool allowed) external;
    function setPoolLaunchPad(address _pad) external;

    // Pool admin / config
    function setPoolConfigValue(uint256 poolId, bytes32 configKeyHash, bytes calldata value) external;
    function readPoolConfigValue(uint256 poolId, bytes32 configKeyHash) external view returns (bytes memory);

    // Pool admin registration (matches implementation)
    function registerPoolAdmin(PoolKey calldata key, address admin) external;

    // Command management
    function runCommandBatch(Command[] calldata commands) external;
    function getCommands(uint256 poolId, bytes32 hookPath) external view returns (Command[] memory);
    function setCommands(uint256 poolId, bytes32 hookPath, Command[] calldata cmds) external;
    function clearCommands(uint256 poolId, bytes32 hookPath) external;

    // Block management
    function createBlock(uint256 blockId, Command[] calldata commands, bool[] calldata immutableFlags, uint64 expiresAt) external;
    function setBlockMetadata(uint256 blockId, bool immutableForPools, bytes32 conflictGroup) external;
    function revokeBlock(uint256 blockId) external;
    function applyBlocksToPool(uint256 poolId, uint256[] calldata blockIds) external;

    // Views / metadata
    function getBlockMeta(uint256 blockId) external view returns (Command[] memory cmds, bool enabled, uint64 expiresAt, bool immutableForPools, bytes32 conflictGroup);
    function getPoolCommandFees(uint256 poolId) external view returns (address[] memory targets, uint256[] memory feeBips);
    function getLockedAndProvenance(
        uint256 poolId,
        bytes32 hookPath,
        address[] calldata targets,
        bytes4[] calldata selectors
    ) external view returns (bool[] memory locked, uint256[] memory originBlocks);
}