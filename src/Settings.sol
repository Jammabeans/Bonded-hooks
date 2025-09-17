// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AccessControl.sol";

/// @title Settings
/// @notice Stores default and per-sender share splits used by ShareSplitter.
/// Shares are simple (recipient, weight). Owner may update default shares or set per-sender overrides.
contract Settings {
    struct Share {
        address recipient;
        uint256 weight;
    }
 
    // Legacy owner retained for backward compatibility; prefer role-based checks via AccessControl.
    address public owner;
    AccessControl public accessControl;
    bytes32 public constant ROLE_SETTINGS_ADMIN = keccak256("ROLE_SETTINGS_ADMIN");
 
    // default shares array
    Share[] internal defaultShares;
    
    // per-sender override shares
    mapping(address => Share[]) internal customShares;
    mapping(address => bool) public hasCustomShares;
    
    event DefaultSharesUpdated(address[] recipients, uint256[] weights);
    event CustomSharesUpdated(address indexed ownerAddr, address[] recipients, uint256[] weights);

    // --- Generic settings maps for AVS configuration ---
    mapping(bytes32 => uint256) public settingsUint;
    mapping(bytes32 => int256) public settingsInt;

    event SettingUintUpdated(bytes32 indexed key, uint256 value);
    event SettingIntUpdated(bytes32 indexed key, int256 value);

    // Hook refund tables (wei per invocation)
    mapping(address => uint256) public globalHookRefund;
    mapping(uint256 => mapping(address => uint256)) public perPoolHookRefund;

    event GlobalHookRefundUpdated(address indexed hookAddress, uint256 weiPerCall);
    event PoolHookRefundUpdated(uint256 indexed poolId, address indexed hookAddress, uint256 weiPerCall);
 
    /// @notice Initialize Settings with deployer as owner and set initial default split.
    /// @param gasBank address for GasBank share
    /// @param degenPool address for DegenPool share
    /// @param feeCollector address for FeeCollector share
    constructor(address gasBank, address degenPool, address feeCollector, AccessControl _accessControl) {
        owner = msg.sender;
        accessControl = _accessControl;
        require(gasBank != address(0) && degenPool != address(0) && feeCollector != address(0), "Zero addr");
        address[] memory recips = new address[](3);
        uint256[] memory weights = new uint256[](3);
        recips[0] = gasBank;
        recips[1] = degenPool;
        recips[2] = feeCollector;
        // default weights per spec: GasBank=400, DegenPool=250, Fees=100
        weights[0] = 400;
        weights[1] = 250;
        weights[2] = 100;
        _setDefaultShares(recips, weights);
    }

    /// @notice Admin can replace the default shares entirely.
    function setDefaultShares(address[] calldata recipients, uint256[] calldata weights) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        _setDefaultShares(recipients, weights);
    }

    function _setDefaultShares(address[] memory recipients, uint256[] memory weights) internal {
        require(recipients.length == weights.length, "Mismatched arrays");
        // clear existing
        delete defaultShares;
        uint256 len = recipients.length;
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero recipient");
            require(weights[i] > 0, "Zero weight");
            defaultShares.push(Share({recipient: recipients[i], weight: weights[i]}));
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight zero");
        emit DefaultSharesUpdated(recipients, weights);
    }

    /// @notice Admin may set per-sender custom shares (override default).
    function setCustomSharesFor(address ownerAddr, address[] calldata recipients, uint256[] calldata weights) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        require(ownerAddr != address(0), "Zero owner");
        _setCustomShares(ownerAddr, recipients, weights);
    }

    function _setCustomShares(address ownerAddr, address[] memory recipients, uint256[] memory weights) internal {
        require(recipients.length == weights.length, "Mismatched arrays");
        delete customShares[ownerAddr];
        uint256 len = recipients.length;
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero recipient");
            require(weights[i] > 0, "Zero weight");
            customShares[ownerAddr].push(Share({recipient: recipients[i], weight: weights[i]}));
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight zero");
        hasCustomShares[ownerAddr] = true;
        emit CustomSharesUpdated(ownerAddr, recipients, weights);
    }

    /// @notice Admin may clear custom shares for an address (revert to default)
    function clearCustomSharesFor(address ownerAddr) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        delete customShares[ownerAddr];
        hasCustomShares[ownerAddr] = false;
        emit CustomSharesUpdated(ownerAddr, new address[](0), new uint256[](0));
    }

    /// @notice Get the shares (recipients and weights) that apply for a given address. Returns default if no custom override.
    function getSharesFor(address ownerAddr) external view returns (address[] memory recipients, uint256[] memory weights) {
        if (hasCustomShares[ownerAddr]) {
            Share[] storage s = customShares[ownerAddr];
            uint256 len = s.length;
            recipients = new address[](len);
            weights = new uint256[](len);
            for (uint256 i = 0; i < len; i++) {
                recipients[i] = s[i].recipient;
                weights[i] = s[i].weight;
            }
            return (recipients, weights);
        } else {
            uint256 len = defaultShares.length;
            recipients = new address[](len);
            weights = new uint256[](len);
            for (uint256 i = 0; i < len; i++) {
                recipients[i] = defaultShares[i].recipient;
                weights[i] = defaultShares[i].weight;
            }
            return (recipients, weights);
        }
    }
 
    /// @notice Helper that prefers role-based checks when AccessControl is configured,
    ///         otherwise falls back to legacy owner semantics for compatibility.
    function _isSettingsAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_SETTINGS_ADMIN, user);
        }
        return user == owner;
    }

    /// @notice Get default shares explicitly
    function getDefaultShares() external view returns (address[] memory recipients, uint256[] memory weights) {
        uint256 len = defaultShares.length;
        recipients = new address[](len);
        weights = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            recipients[i] = defaultShares[i].recipient;
            weights[i] = defaultShares[i].weight;
        }
        return (recipients, weights);
    }

    /// @notice Admin: set a uint256 setting by key (key = keccak256("name"))
    function setUintSetting(bytes32 key, uint256 value) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        settingsUint[key] = value;
        emit SettingUintUpdated(key, value);
    }

    /// @notice Admin: set an int256 setting by key
    function setIntSetting(bytes32 key, int256 value) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        settingsInt[key] = value;
        emit SettingIntUpdated(key, value);
    }

    /// @notice Read helpers for settings
    function getUint(bytes32 key) external view returns (uint256) {
        return settingsUint[key];
    }
    function getInt(bytes32 key) external view returns (int256) {
        return settingsInt[key];
    }

    /// @notice Admin: set global per-hook refund (wei per invocation)
    function setGlobalHookRefund(address hookAddress, uint256 weiPerCall) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        globalHookRefund[hookAddress] = weiPerCall;
        emit GlobalHookRefundUpdated(hookAddress, weiPerCall);
    }

    /// @notice Admin: set per-pool per-hook refund (overrides global)
    function setPerPoolHookRefund(uint256 poolId, address hookAddress, uint256 weiPerCall) external {
        require(_isSettingsAdmin(msg.sender), "Settings: not admin");
        perPoolHookRefund[poolId][hookAddress] = weiPerCall;
        emit PoolHookRefundUpdated(poolId, hookAddress, weiPerCall);
    }

    /// @notice Get effective hook refund for hook (checks per-pool override then global)
    function getHookRefundFor(uint256 poolId, address hookAddress) external view returns (uint256) {
        uint256 v = perPoolHookRefund[poolId][hookAddress];
        if (v != 0) return v;
        return globalHookRefund[hookAddress];
    }
}