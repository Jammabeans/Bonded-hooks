// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title IGasRebateManager
/// @notice Interface for GasRebateManager.
interface IGasRebateManager {
    event GasBankUpdated(address indexed gasBank);
    event OperatorUpdated(address indexed operator, bool enabled);
    event GasPointsPushed(uint256 indexed epoch, address indexed operator, address[] users, uint256[] amounts);
    event RebateWithdrawn(address indexed user, uint256 amount);
    event Received(address indexed sender, uint256 amount);

    // Public getters / state
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_GAS_REBATE_ADMIN() external view returns (bytes32);

    function epochProcessed(uint256 epoch) external view returns (bool);
    function rebateBalance(address user) external view returns (uint256);
    function operators(address operator) external view returns (bool);
    function gasBank() external view returns (address);

    // Admin / config
    function setGasBank(address gasBankAddr) external;
    function setOperator(address operatorAddr, bool enabled) external;

    // Operator actions
    function pushGasPoints(
        uint256 epoch,
        address[] calldata users,
        uint256[] calldata amounts
    ) external;

    // User actions
    function withdrawGasRebate() external;

    // Owner emergency withdrawal
    function ownerWithdraw(address payable to, uint256 amount) external;

    // Views
    function getBalances(address[] calldata users) external view returns (uint256[] memory balances);
}