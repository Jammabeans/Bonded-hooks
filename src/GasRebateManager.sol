// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GasRebateManager
/// @notice Minimal on-chain contract to receive epoch batch credits from an off-chain AVS operator
/// and allow users to withdraw accumulated ETH rebates.
///
/// Off-chain operator watches `NewGasPaid` events (or other sources), computes per-user rebate amounts
/// in wei for an epoch, and calls `pushGasPoints(epoch, users, amounts)` to credit users.
///
/// Security / assumptions:
/// - A trusted operator (or set of operators) must be set by the contract owner via `setOperator`.
/// - The contract holds ETH which users withdraw via `withdrawGasRebate`.
/// - This is a simple starter implementation (Preset A). It intentionally keeps logic minimal so it can
///   be extended later (Merkle-style commitments, disputes/slashing, multiple operators, etc).
contract GasRebateManager is Ownable {
    // epoch => pushed
    mapping(uint256 => bool) public epochProcessed;

    // user => wei amount available to withdraw
    mapping(address => uint256) public rebateBalance;

    // operators allowed to push epoch credits
    mapping(address => bool) public operators;
    
    /// @notice Initialize Ownable with deployer as owner
    constructor() Ownable(msg.sender) {
        // owner set to deployer
    }

    event OperatorUpdated(address indexed operator, bool enabled);
    event GasPointsPushed(uint256 indexed epoch, address indexed operator, address[] users, uint256[] amounts);
    event RebateWithdrawn(address indexed user, uint256 amount);
    event Received(address indexed sender, uint256 amount);

    modifier onlyOperator() {
        require(operators[msg.sender], "Caller is not an operator");
        _;
    }

    /// @notice Allow the contract to accept ETH deposits to fund rebates
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Owner can set or unset operator addresses that are authorized to push epoch credits.
    /// @param operatorAddr operator address
    /// @param enabled true to enable, false to disable
    function setOperator(address operatorAddr, bool enabled) external onlyOwner {
        operators[operatorAddr] = enabled;
        emit OperatorUpdated(operatorAddr, enabled);
    }

    /// @notice Push per-user rebate amounts for a specific epoch. This is expected to be called once per epoch
    /// by an authorized operator. The operator provides arrays of users and corresponding amounts (in wei).
    /// @param epoch The epoch identifier (e.g., block range index)
    /// @param users Array of user addresses
    /// @param amounts Array of amounts in wei to credit to each user (same length as users)
    function pushGasPoints(
        uint256 epoch,
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOperator {
        require(users.length == amounts.length, "Mismatched arrays");
        require(users.length > 0, "Empty batch");
        require(!epochProcessed[epoch], "Epoch already processed");

        // Mark epoch processed to prevent double-submission for the same epoch
        epochProcessed[epoch] = true;

        // Credit balances
        for (uint256 i = 0; i < users.length; i++) {
            // safe to add; amounts are wei values computed off-chain
            rebateBalance[users[i]] += amounts[i];
        }

        emit GasPointsPushed(epoch, msg.sender, users, amounts);
    }

    /// @notice Withdraw accumulated rebate in ETH for the caller.
    function withdrawGasRebate() external {
        uint256 amount = rebateBalance[msg.sender];
        require(amount > 0, "No rebate available");

        // Effects
        rebateBalance[msg.sender] = 0;

        // Interaction
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "ETH transfer failed");

        emit RebateWithdrawn(msg.sender, amount);
    }

    /// @notice Emergency function: owner can withdraw any ETH balance from the contract.
    /// Use cautiously (e.g., for migration or recovery). Funds intended for rebates should be
    /// managed separately or with governance in production.
    function ownerWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "ETH transfer failed");
    }

    /// @notice Helper: batch view to check balances for multiple users
    /// @param users array of user addresses
    /// @return balances array of rebates for each user
    function getBalances(address[] calldata users) external view returns (uint256[] memory balances) {
        balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = rebateBalance[users[i]];
        }
    }
}