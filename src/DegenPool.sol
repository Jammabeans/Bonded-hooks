// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DegenPool
/// @notice Points-based reward pool with immediate deposit allocation and safe handling when minting points.
/// - Deposits (ETH) immediately update cumulativeRewardPerPoint if there are active points.
/// - When new points are minted to an account that already has active points, the user's owed rewards
///   (from previous cumulative increments) are moved into `pendingRewards` so new points don't
///   retroactively claim past deposits.
/// - On withdraw, the user receives (pendingRewards + owedFromActivePoints) and half of their points
///   are burned as a penalty.
contract DegenPool is Ownable, ReentrancyGuard {
    uint256 public constant SCALE = 1e18;

    // active points that participate in reward distribution
    mapping(address => uint256) public points;
    // pendingRewards denominated in wei (ETH) that were accumulated for the user when they received new points
    mapping(address => uint256) public pendingRewards;
    uint256 public totalPoints;

    // settlement role addresses allowed to mint (operator)
    mapping(address => bool) public settlementRole;

    // share splitter address and events
    address public shareSplitter;
    event ShareSplitterUpdated(address indexed splitter);
    event DepositFromSplitter(address indexed from, uint256 amount);
 
    // cumulative reward per point scaled by SCALE
    uint256 public cumulativeRewardPerPoint;
 
    // per-user last checkpoint of cumulativeRewardPerPoint
    mapping(address => uint256) public userCumPerPoint;

    event PointsMinted(address indexed account, uint256 pts, uint256 epoch);
    event PointsBatchMinted(address[] accounts, uint256[] pts, uint256 epoch);
    event SettlementRoleUpdated(address indexed operator, bool enabled);
    event DepositReceived(address indexed from, uint256 amount);
    event RewardsMovedToPending(address indexed account, uint256 amount);
    event RewardsWithdrawn(address indexed account, uint256 amountPaid, uint256 pointsBurned);

    modifier onlySettlement() {
        require(settlementRole[msg.sender], "Caller is not settlement role");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Receive ETH from pools or anyone. Immediately allocate to cumulativeRewardPerPoint
    /// if there are active points. If totalPoints == 0, funds remain in contract balance until
    /// points exist (there's no separate unallocated tracker per your design).
    receive() external payable {
        require(msg.value > 0, "No ETH");
        if (totalPoints > 0) {
            // increment cumulativeRewardPerPoint scaled by SCALE
            cumulativeRewardPerPoint += (msg.value * SCALE) / totalPoints;
        }
        emit DepositReceived(msg.sender, msg.value);
    }

    /// @notice Called by ShareSplitter to deposit funds on behalf of users.
    /// Only the configured shareSplitter address may call this.
    function depositFromSplitter() external payable {
        require(msg.sender == shareSplitter, "Not share splitter");
        require(msg.value > 0, "No ETH");
        if (totalPoints > 0) {
            cumulativeRewardPerPoint += (msg.value * SCALE) / totalPoints;
        }
        // use tx.origin as the original sender for logging purposes (splitter forwarded on behalf)
        emit DepositFromSplitter(tx.origin, msg.value);
    }

    /// @notice Set settlement role (operator).
    function setSettlementRole(address operator, bool enabled) external onlyOwner {
        settlementRole[operator] = enabled;
        emit SettlementRoleUpdated(operator, enabled);
    }

    /// @notice Set the ShareSplitter contract allowed to call depositFromSplitter
    function setShareSplitter(address splitter) external onlyOwner {
        shareSplitter = splitter;
        emit ShareSplitterUpdated(splitter);
    }

    /// @notice Mint points to multiple accounts in batch. For accounts that already have active points,
    /// move their owed rewards (based on current cumulativeRewardPerPoint) into pendingRewards before
    /// adding the new points so new points don't retroactively claim past deposits.
    function batchMintPoints(address[] calldata accounts, uint256[] calldata pts, uint256 epoch) external onlySettlement {
        require(accounts.length == pts.length, "Mismatched arrays");
        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; ++i) {
            address acct = accounts[i];
            uint256 addPts = pts[i];
            require(acct != address(0), "Zero address");
            require(addPts > 0, "Zero pts");

            // If account already has active points, compute owed rewards and move to pendingRewards
            uint256 existingPts = points[acct];
            if (existingPts > 0) {
                uint256 lastCum = userCumPerPoint[acct];
                if (cumulativeRewardPerPoint > lastCum) {
                    uint256 owed = (existingPts * (cumulativeRewardPerPoint - lastCum)) / SCALE;
                    if (owed > 0) {
                        pendingRewards[acct] += owed;
                        emit RewardsMovedToPending(acct, owed);
                    }
                }
            }

            // Add points and checkpoint to current cumulative so they don't retroactively get past rewards
            points[acct] += addPts;
            totalPoints += addPts;
            userCumPerPoint[acct] = cumulativeRewardPerPoint;

        }
        emit PointsBatchMinted(accounts, pts, epoch);
    }

    /// @notice Mint points immediately to a single account (settlement only). Handles owed => pending if account already had points.
    function mintPoints(address account, uint256 pts, uint256 epoch) external onlySettlement {
        require(account != address(0), "Zero addr");
        require(pts > 0, "Zero pts");

        uint256 existingPts = points[account];
        if (existingPts > 0) {
            uint256 lastCum = userCumPerPoint[account];
            if (cumulativeRewardPerPoint > lastCum) {
                uint256 owed = (existingPts * (cumulativeRewardPerPoint - lastCum)) / SCALE;
                if (owed > 0) {
                    pendingRewards[account] += owed;
                    emit RewardsMovedToPending(account, owed);
                }
            }
        }

        points[account] += pts;
        totalPoints += pts;
        userCumPerPoint[account] = cumulativeRewardPerPoint;

        emit PointsMinted(account, pts, epoch);
    }

    /// @notice View pending rewards for an account (wei)
    function getPendingRewards(address account) external view returns (uint256) {
        return pendingRewards[account];
    }

    /// @notice Withdraw rewards: pay user pendingRewards + owed from active points, then burn half of their points.
    /// The owed amount from active points is computed against cumulativeRewardPerPoint and userCumPerPoint.
    function withdrawRewards() external nonReentrant {
        uint256 activePts = points[msg.sender];
        uint256 owedActive = 0;
        uint256 lastCum = userCumPerPoint[msg.sender];

        if (activePts > 0 && cumulativeRewardPerPoint > lastCum) {
            owedActive = (activePts * (cumulativeRewardPerPoint - lastCum)) / SCALE;
        }

        uint256 pending = pendingRewards[msg.sender];

        uint256 payout = pending + owedActive;
        require(payout > 0, "Payout zero");
        require(address(this).balance >= payout, "Insufficient contract balance");

        // Reset pending rewards
        pendingRewards[msg.sender] = 0;

        // Update user's checkpoint to current cumulative so future rewards start from now
        userCumPerPoint[msg.sender] = cumulativeRewardPerPoint;

        // Burn half of user's points as penalty
        uint256 burned = 0;
        if (points[msg.sender] > 0) {
            burned = points[msg.sender] / 2;
            points[msg.sender] = points[msg.sender] - burned;
            totalPoints -= burned;
        }

        // Transfer payout
        (bool sent, ) = msg.sender.call{value: payout}("");
        require(sent, "ETH transfer failed");

        emit RewardsWithdrawn(msg.sender, payout, burned);
    }

    /// @notice Emergency: owner may withdraw ETH from contract (use with care).
    function ownerWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }
}