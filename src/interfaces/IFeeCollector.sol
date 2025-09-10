// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title IFeeCollector
/// @notice Interface for the FeeCollector contract.
interface IFeeCollector {
    event DepositReceived(address indexed sender, uint256 amount);
    event SettingsUpdated(address indexed settings);

    // Public getters
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_FEE_COLLECTOR_ADMIN() external view returns (bytes32);
    function settings() external view returns (address);

    // Management
    function setSettings(address settingsAddr) external;
    function ownerWithdraw(address payable to, uint256 amount) external;
}