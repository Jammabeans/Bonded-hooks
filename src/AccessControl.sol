// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Simple per-pool access control registry.
/// @dev Maps a bytes32 poolKeyHash (keccak256(abi.encode(poolKey))) to an admin address.
/// - setPoolAdmin: If a pool has no admin yet, anyone may set the admin (used by PoolLaunchPad during initialization).
///                 Once set, only the current admin can change it.
/// - poolAdmin / getPoolAdmin / isPoolAdmin: view helpers.
contract AccessControl {
    mapping(bytes32 => address) public poolAdmin;

    event PoolAdminSet(bytes32 indexed poolKeyHash, address indexed admin);

    /// @notice Set the admin for a given poolKeyHash.
    /// @dev If no admin exists for the pool, anyone may set it (this allows the pool launcher to register the caller).
    ///      If an admin exists, only the current admin may update it.
    function setPoolAdmin(bytes32 poolKeyHash, address admin) external {
        address current = poolAdmin[poolKeyHash];
        if (current == address(0)) {
            poolAdmin[poolKeyHash] = admin;
            emit PoolAdminSet(poolKeyHash, admin);
        } else {
            require(msg.sender == current, "AccessControl: not current admin");
            poolAdmin[poolKeyHash] = admin;
            emit PoolAdminSet(poolKeyHash, admin);
        }
    }

    function getPoolAdmin(bytes32 poolKeyHash) external view returns (address) {
        return poolAdmin[poolKeyHash];
    }

    function isPoolAdmin(bytes32 poolKeyHash, address user) external view returns (bool) {
        return poolAdmin[poolKeyHash] == user;
    }
}