// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAccessControl
/// @notice Interface for the AccessControl contract used across the system.
interface IAccessControl {
    event PoolAdminSet(uint256 indexed poolId, address indexed admin);
    event PoolLaunchPadSet(address indexed poolLaunchPad);
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event ContractsRegistered();

    // Public getters (generated for public state vars)
    function poolAdmin(uint256 poolId) external view returns (address);
    function owner() external view returns (address);
    function poolLaunchPad() external view returns (address);

    // Admin / configuration
    function setPoolLaunchPad(address _pad) external;
    function setPoolAdmin(uint256 poolId, address admin) external;

    // Roles
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);

    // Helpers / registry
    function getPoolAdmin(uint256 poolId) external view returns (address);
    function isPoolAdmin(uint256 poolId, address user) external view returns (bool);

    function registerDeployedContracts(address[] calldata addrs) external;
    function getContract(string calldata name) external view returns (address addr);
}