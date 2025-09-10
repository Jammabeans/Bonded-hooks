// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title IDegenPool
/// @notice Interface for the DegenPool points/rewards contract.
interface IDegenPool {
    event ShareSplitterUpdated(address indexed splitter);
    event DepositFromSplitter(address indexed from, uint256 amount, address currency);
    event DepositReceived(address indexed from, uint256 amount, address currency);
    event PointsMinted(address indexed account, uint256 pts, uint256 epoch);
    event PointsBatchMinted(address[] accounts, uint256[] pts, uint256 epoch);
    event SettlementRoleUpdated(address indexed operator, bool enabled);
    event RewardsMovedToPending(address indexed account, uint256 amount, address currency);
    event RewardsWithdrawn(address indexed account, address indexed currency, uint256 amount);
    event RewardCurrencyEnabled(address indexed currency, bool enabled);

    // getters
    function SCALE() external view returns (uint256);
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_DEGEN_ADMIN() external view returns (bytes32);
    function points(address user) external view returns (uint256);
    function totalPoints() external view returns (uint256);
    function settlementRole(address operator) external view returns (bool);
    function shareSplitter() external view returns (address);
    function cumulativeRewardPerPoint(address currency) external view returns (uint256);
    function userCumPerPoint(address user, address currency) external view returns (uint256);
    function pendingRewards(address user, address currency) external view returns (uint256);
    function rewardCurrencies(uint256 index) external view returns (address);
    function rewardCurrencyEnabled(address currency) external view returns (bool);

    // management
    function setRewardCurrency(address currency, bool enabled) external;
    function depositFromSplitter() external payable;
    function depositFromSplitterERC20(address token, uint256 amount) external;
    function setSettlementRole(address operator, bool enabled) external;
    function setShareSplitter(address splitter) external;

    // minting / settlement
    function batchMintPoints(address[] calldata accounts, uint256[] calldata pts, uint256 epoch) external;
    function mintPoints(address account, uint256 pts, uint256 epoch) external;

    // rewards
    function getPendingRewards(address account, address currency) external view returns (uint256);
    function withdrawRewards(address[] calldata currencies) external;

    // owner
    function ownerWithdraw(address payable to, uint256 amount) external;

    // helpers
    function getPoints(address user) external view returns (uint256);
    function getRewardCurrencies() external view returns (address[] memory);
}