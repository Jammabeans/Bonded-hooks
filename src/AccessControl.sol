// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Simple per-pool access control registry.
/// @dev Maps a bytes32 poolKeyHash (keccak256(abi.encode(poolKey))) to an admin address.
/// - setPoolAdmin: Only the configured PoolLaunchPad may set the initial admin for a pool.
///                 After initialization, only the current admin or the PoolLaunchPad may change it.
/// - poolAdmin / getPoolAdmin / isPoolAdmin: view helpers.
contract AccessControl {
    mapping(bytes32 => address) public poolAdmin;

    /// @notice Contract-level owner (deployer) who may configure the PoolLaunchPad address.
    address public owner;

    /// @notice Authorized PoolLaunchPad contract allowed to register initial admins.
    address public poolLaunchPad;

    event PoolAdminSet(bytes32 indexed poolKeyHash, address indexed admin);
    event PoolLaunchPadSet(address indexed poolLaunchPad);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Configure the PoolLaunchPad address. Only the deployer/owner may call this.
    function setPoolLaunchPad(address _pad) external {
        require(msg.sender == owner, "AccessControl: only owner");
        poolLaunchPad = _pad;
        emit PoolLaunchPadSet(_pad);
    }

    /// @notice Set the admin for a given poolKeyHash.
    /// @dev Initial admin may only be set by the configured PoolLaunchPad.
    ///      Subsequent changes may be performed by the current admin or the PoolLaunchPad.
    function setPoolAdmin(bytes32 poolKeyHash, address admin) external {
        address current = poolAdmin[poolKeyHash];
        if (current == address(0)) {
            require(poolLaunchPad != address(0), "AccessControl: poolLaunchPad not set");
            require(msg.sender == poolLaunchPad, "AccessControl: only PoolLaunchPad may set initial admin");
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