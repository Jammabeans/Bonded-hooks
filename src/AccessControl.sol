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

    /* ========== Deployed Contracts Registry ========== */
    // Allow the deploy script (owner) to register a canonical list of deployed contract addresses
    // so other contracts and off-chain tooling can rely on AccessControl as a single source of truth.
    event ContractsRegistered();

    // registry keyed by keccak256(name) -> address
    mapping(bytes32 => address) private contractRegistry;

    /// @notice Register deployed contracts in a predefined order.
    /// @dev Only the contract owner (deployer) may call this. The Deploy script passes an array
    ///      of addresses in the same order as the expected keys below.
    function registerDeployedContracts(address[] memory addrs) external {
        require(msg.sender == owner, "AccessControl: only owner");
        require(addrs.length >= 15, "AccessControl: insufficient addrs");

        bytes32[15] memory keys = [
            keccak256("PoolManager"),
            keccak256("AccessControl"),
            keccak256("PoolLaunchPad"),
            keccak256("MasterControl"),
            keccak256("FeeCollector"),
            keccak256("GasBank"),
            keccak256("DegenPool"),
            keccak256("Settings"),
            keccak256("ShareSplitter"),
            keccak256("Bonding"),
            keccak256("PrizeBox"),
            keccak256("Shaker"),
            keccak256("PointsCommand"),
            keccak256("BidManager"),
            keccak256("MockAVS")
        ];

        for (uint i = 0; i < 15; i++) {
            contractRegistry[keys[i]] = addrs[i];
        }

        emit ContractsRegistered();
    }

    /// @notice Retrieve a registered contract address by name (e.g. "DegenPool").
    /// @param name Human-readable name of the contract as a string.
    /// @return addr The registered contract address or zero if not set.
    function getContract(string calldata name) external view returns (address addr) {
        bytes32 k = keccak256(bytes(name));
        return contractRegistry[k];
    }
}