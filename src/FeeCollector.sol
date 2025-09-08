// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AccessControl.sol";

/// @title FeeCollector
/// @notice Simple placeholder to collect platform fees.
contract FeeCollector {
    event DepositReceived(address indexed sender, uint256 amount);
    event SettingsUpdated(address indexed settings);
 
    // Legacy owner retained for compatibility; prefer role-based checks via AccessControl.
    address public owner;
    AccessControl public accessControl;
    bytes32 public constant ROLE_FEE_COLLECTOR_ADMIN = keccak256("ROLE_FEE_COLLECTOR_ADMIN");
 
    address public settings;
 
    constructor(AccessControl _accessControl) {
        owner = msg.sender;
        accessControl = _accessControl;
    }

    receive() external payable {
        emit DepositReceived(msg.sender, msg.value);
    }

    function setSettings(address settingsAddr) external {
        require(_isAdmin(msg.sender), "FeeCollector: not admin");
        settings = settingsAddr;
        emit SettingsUpdated(settingsAddr);
    }

    function ownerWithdraw(address payable to, uint256 amount) external {
        require(_isAdmin(msg.sender), "FeeCollector: not admin");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }
 
    function _isAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_FEE_COLLECTOR_ADMIN, user);
        }
        return user == owner;
    }
}