 // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
 
import "@openzeppelin/contracts/access/Ownable.sol";
 
/// @title GasBank
/// @notice Holds ETH earmarked for gas rebates. Only the configured rebateManager may withdraw funds for rebate payouts.
contract GasBank is Ownable {
    address public rebateManager;
    address public shareSplitter;
    bool public allowPublicDeposits = true;
 
    event DepositReceived(address indexed sender, uint256 amount);
    event RebateManagerUpdated(address indexed manager);
    event WithdrawnForRebate(address indexed to, uint256 amount);
    event ShareSplitterUpdated(address indexed splitter);
    event AllowPublicDepositsUpdated(bool allowed);
 
    constructor() Ownable(msg.sender) {}
 
    receive() external payable {
        require(allowPublicDeposits || msg.sender == shareSplitter, "Deposits not allowed");
        emit DepositReceived(msg.sender, msg.value);
    }
 
    /// @notice Owner sets the rebate manager contract that is allowed to pull funds for rebates.
    function setRebateManager(address manager) external onlyOwner {
        rebateManager = manager;
        emit RebateManagerUpdated(manager);
    }
 
    /// @notice Owner sets the ShareSplitter contract allowed to deposit when public deposits are disabled.
    function setShareSplitter(address splitter) external onlyOwner {
        shareSplitter = splitter;
        emit ShareSplitterUpdated(splitter);
    }
 
    /// @notice Owner may toggle whether public deposits are allowed.
    function setAllowPublicDeposits(bool allowed) external onlyOwner {
        allowPublicDeposits = allowed;
        emit AllowPublicDepositsUpdated(allowed);
    }
 
    /// @notice Withdraw funds to a destination. Only callable by the configured rebateManager.
    function withdrawTo(address to, uint256 amount) external {
        require(msg.sender == rebateManager, "Not rebate manager");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Transfer failed");
        emit WithdrawnForRebate(to, amount);
    }
 
    /// @notice Owner recovery method
    function ownerWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }
}