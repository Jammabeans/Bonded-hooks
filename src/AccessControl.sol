// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Simple per-pool access control registry.
/// @dev Maps a uint256 poolId (PoolId.unwrap(poolId)) to an admin address.
/// - setPoolAdmin: Only the configured PoolLaunchPad may set the initial admin for a pool.
///                 After initialization, the current admin or the PoolLaunchPad may change it.
/// - poolAdmin / getPoolAdmin / isPoolAdmin: view helpers.
contract AccessControl {
    mapping(uint256 => address) public poolAdmin;

    /// @notice Contract-level owner (deployer) who may configure the PoolLaunchPad address.
    address public owner;

    /// @notice Authorized PoolLaunchPad contract allowed to register initial admins.
    address public poolLaunchPad;

    /// @notice Simple role registry: role => account => granted
    mapping(bytes32 => mapping(address => bool)) private roles;

    event PoolAdminSet(uint256 indexed poolId, address indexed admin);
    event PoolLaunchPadSet(address indexed poolLaunchPad);
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Configure the PoolLaunchPad address. Only the deployer/owner may call this.
    function setPoolLaunchPad(address _pad) external {
        require(msg.sender == owner, "AccessControl: only owner");
        poolLaunchPad = _pad;
        emit PoolLaunchPadSet(_pad);
    }

    /// @notice Set the admin for a given poolId.
    /// @dev Initial admin may only be set by the configured PoolLaunchPad.
    ///      Subsequent changes may be performed by the current admin or the PoolLaunchPad.
    function setPoolAdmin(uint256 poolId, address admin) external {
        address current = poolAdmin[poolId];
        if (current == address(0)) {
            require(poolLaunchPad != address(0), "AccessControl: poolLaunchPad not set");
            require(msg.sender == poolLaunchPad, "AccessControl: only PoolLaunchPad may set initial admin");
            poolAdmin[poolId] = admin;
            emit PoolAdminSet(poolId, admin);
        } else {
            require(msg.sender == current || msg.sender == poolLaunchPad, "AccessControl: not current admin or launchpad");
            poolAdmin[poolId] = admin;
            emit PoolAdminSet(poolId, admin);
        }
    }

    /// @notice Grant a named role to an account. Only contract owner may call.
    function grantRole(bytes32 role, address account) external {
        require(msg.sender == owner, "AccessControl: only owner");
        if (!roles[role][account]) {
            roles[role][account] = true;
            emit RoleGranted(role, account);
        }
    }

    /// @notice Revoke a previously granted role. Only contract owner may call.
    function revokeRole(bytes32 role, address account) external {
        require(msg.sender == owner, "AccessControl: only owner");
        if (roles[role][account]) {
            roles[role][account] = false;
            emit RoleRevoked(role, account);
        }
    }

    /// @notice Check whether an account holds a role.
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roles[role][account];
    }

    function getPoolAdmin(uint256 poolId) external view returns (address) {
        return poolAdmin[poolId];
    }

    function isPoolAdmin(uint256 poolId, address user) external view returns (bool) {
        return poolAdmin[poolId] == user;
    }
}