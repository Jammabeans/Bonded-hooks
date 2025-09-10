// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title IGasBank
/// @notice Interface for the GasBank contract.
interface IGasBank {
    event DepositReceived(address indexed sender, uint256 amount);
    event RebateManagerUpdated(address indexed manager);
    event WithdrawnForRebate(address indexed to, uint256 amount);
    event ShareSplitterUpdated(address indexed splitter);
    event AllowPublicDepositsUpdated(bool allowed);

    // Public getters
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_GAS_BANK_ADMIN() external view returns (bytes32);

    function rebateManager() external view returns (address);
    function shareSplitter() external view returns (address);
    function allowPublicDeposits() external view returns (bool);

    // Admin / config
    function setRebateManager(address manager) external;
    function setShareSplitter(address splitter) external;
    function setAllowPublicDeposits(bool allowed) external;

    // Withdrawals
    function withdrawTo(address to, uint256 amount) external;
    function ownerWithdraw(address payable to, uint256 amount) external;
}