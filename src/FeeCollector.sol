// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title FeeCollector
/// @notice Simple placeholder to collect platform fees.
contract FeeCollector is Ownable {
    event DepositReceived(address indexed sender, uint256 amount);
    event SettingsUpdated(address indexed settings);

    address public settings;

    constructor() Ownable(msg.sender) {}

    receive() external payable {
        emit DepositReceived(msg.sender, msg.value);
    }

    function setSettings(address settingsAddr) external onlyOwner {
        settings = settingsAddr;
        emit SettingsUpdated(settingsAddr);
    }

    function ownerWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }
}