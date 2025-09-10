// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DegenPool (multi-currency)
/// @notice Points-based reward pool supporting multiple reward currencies (native + ERC20).
/// Points are a single global supply; rewards accrue per-currency using a per-currency cumulative reward-per-point.
contract DegenPool is ReentrancyGuard {
    uint256 public constant SCALE = 1e18;

    // Legacy owner retained for compatibility; prefer role-based checks via AccessControl.
    address public owner;
    AccessControl public accessControl;
    bytes32 public constant ROLE_DEGEN_ADMIN = keccak256("ROLE_DEGEN_ADMIN");

    // Points accounting (single points balance per user)
    mapping(address => uint256) public points;
    uint256 public totalPoints;

    // settlement role addresses allowed to mint (operator)
    mapping(address => bool) public settlementRole;

    // share splitter address and events
    address public shareSplitter;
    event ShareSplitterUpdated(address indexed splitter);
    event DepositFromSplitter(address indexed from, uint256 amount, address currency);

    // Multi-currency reward accounting:
    // cumulative reward per point scaled by SCALE for each currency (address(0) = native)
    mapping(address => uint256) public cumulativeRewardPerPoint;
    // per-user last checkpoint of cumulativeRewardPerPoint per currency: user => currency => lastCum
    mapping(address => mapping(address => uint256)) public userCumPerPoint;
    // per-user pending rewards per currency: user => currency => amount
    mapping(address => mapping(address => uint256)) public pendingRewards;

    // list of enabled reward currencies and quick lookup (address(0) allowed for native)
    address[] public rewardCurrencies;
    mapping(address => bool) public rewardCurrencyEnabled;

    // Events
    event PointsMinted(address indexed account, uint256 pts, uint256 epoch);
    event PointsBatchMinted(address[] accounts, uint256[] pts, uint256 epoch);
    event SettlementRoleUpdated(address indexed operator, bool enabled);
    event DepositReceived(address indexed from, uint256 amount, address currency);
    event RewardsMovedToPending(address indexed account, uint256 amount, address currency);
    event RewardsWithdrawn(address indexed account, address indexed currency, uint256 amount);
    event RewardCurrencyEnabled(address indexed currency, bool enabled);

    modifier onlySettlement() {
        require(settlementRole[msg.sender], "Caller is not settlement role");
        _;
    }

    constructor(AccessControl _accessControl) {
        owner = msg.sender;
        accessControl = _accessControl;
        // enable native by default
        rewardCurrencyEnabled[address(0)] = true;
        rewardCurrencies.push(address(0));
    }

    /// @notice Enable or disable a reward currency (admin)
    function setRewardCurrency(address currency, bool enabled) external {
        require(_isDegenAdmin(msg.sender), "DegenPool: not admin");
        if (enabled && !rewardCurrencyEnabled[currency]) {
            rewardCurrencyEnabled[currency] = true;
            rewardCurrencies.push(currency);
            emit RewardCurrencyEnabled(currency, true);
        } else if (!enabled && rewardCurrencyEnabled[currency]) {
            rewardCurrencyEnabled[currency] = false;
            // remove from array (best-effort)
            for (uint256 i = 0; i < rewardCurrencies.length; i++) {
                if (rewardCurrencies[i] == currency) {
                    rewardCurrencies[i] = rewardCurrencies[rewardCurrencies.length - 1];
                    rewardCurrencies.pop();
                    break;
                }
            }
            emit RewardCurrencyEnabled(currency, false);
        }
    }

    /// @notice Receive native ETH and credit to native reward pool (address(0))
    receive() external payable {
        require(msg.value > 0, "No ETH");
        _depositReward(address(0), msg.value);
        emit DepositReceived(msg.sender, msg.value, address(0));
    }

    /// @notice Deposit native ETH from ShareSplitter on behalf of users.
    function depositFromSplitter() external payable {
        require(msg.sender == shareSplitter, "Not share splitter");
        require(msg.value > 0, "No ETH");
        _depositReward(address(0), msg.value);
        emit DepositFromSplitter(tx.origin, msg.value, address(0));
    }

    /// @notice Deposit ERC20 tokens from ShareSplitter on behalf of users.
    function depositFromSplitterERC20(address token, uint256 amount) external {
        require(msg.sender == shareSplitter, "Not share splitter");
        require(amount > 0, "No amount");
        require(rewardCurrencyEnabled[token], "Currency not enabled");
        // transferFrom split -> this
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, msg.sender, address(this), amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "ERC20 transferFrom failed");
        _depositReward(token, amount);
        emit DepositFromSplitter(tx.origin, amount, token);
    }

    function _depositReward(address currency, uint256 amount) internal {
        if (totalPoints > 0) {
            cumulativeRewardPerPoint[currency] += (amount * SCALE) / totalPoints;
        }
    }

    /// @notice Set settlement role (operator).
    function setSettlementRole(address operator, bool enabled) external {
        require(_isDegenAdmin(msg.sender), "DegenPool: not admin");
        settlementRole[operator] = enabled;
        emit SettlementRoleUpdated(operator, enabled);
    }

    /// @notice Set the ShareSplitter contract allowed to call deposits
    function setShareSplitter(address splitter) external {
        require(_isDegenAdmin(msg.sender), "DegenPool: not admin");
        shareSplitter = splitter;
        emit ShareSplitterUpdated(splitter);
    }

    /// @notice Mint points to multiple accounts in batch. Handles multi-currency pending rewards.
    function batchMintPoints(address[] calldata accounts, uint256[] calldata pts, uint256 epoch) external onlySettlement {
        require(accounts.length == pts.length, "Mismatched arrays");
        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; ++i) {
            address acct = accounts[i];
            uint256 addPts = pts[i];
            require(acct != address(0), "Zero address");
            require(addPts > 0, "Zero pts");

            uint256 existingPts = points[acct];
            if (existingPts > 0) {
                for (uint256 c = 0; c < rewardCurrencies.length; c++) {
                    address cur = rewardCurrencies[c];
                    uint256 lastCum = userCumPerPoint[acct][cur];
                    uint256 curCum = cumulativeRewardPerPoint[cur];
                    if (curCum > lastCum) {
                        uint256 owed = (existingPts * (curCum - lastCum)) / SCALE;
                        if (owed > 0) {
                            pendingRewards[acct][cur] += owed;
                            emit RewardsMovedToPending(acct, owed, cur);
                        }
                    }
                }
            }

            points[acct] += addPts;
            totalPoints += addPts;

            for (uint256 c2 = 0; c2 < rewardCurrencies.length; c2++) {
                address cur2 = rewardCurrencies[c2];
                userCumPerPoint[acct][cur2] = cumulativeRewardPerPoint[cur2];
            }
        }
        emit PointsBatchMinted(accounts, pts, epoch);
    }

    /// @notice Mint points immediately to a single account (settlement only). Handles multi-currency owed => pending.
    function mintPoints(address account, uint256 pts, uint256 epoch) external onlySettlement {
        require(account != address(0), "Zero addr");
        require(pts > 0, "Zero pts");

        uint256 existingPts = points[account];
        if (existingPts > 0) {
            for (uint256 c = 0; c < rewardCurrencies.length; c++) {
                address cur = rewardCurrencies[c];
                uint256 lastCum = userCumPerPoint[account][cur];
                uint256 curCum = cumulativeRewardPerPoint[cur];
                if (curCum > lastCum) {
                    uint256 owed = (existingPts * (curCum - lastCum)) / SCALE;
                    if (owed > 0) {
                        pendingRewards[account][cur] += owed;
                        emit RewardsMovedToPending(account, owed, cur);
                    }
                }
            }
        }

        points[account] += pts;
        totalPoints += pts;

        for (uint256 c2 = 0; c2 < rewardCurrencies.length; c2++) {
            address cur2 = rewardCurrencies[c2];
            userCumPerPoint[account][cur2] = cumulativeRewardPerPoint[cur2];
        }

        emit PointsMinted(account, pts, epoch);
    }

    /// @notice View pending rewards for an account for a specific currency
    function getPendingRewards(address account, address currency) external view returns (uint256) {
        return pendingRewards[account][currency];
    }

function withdrawRewards(address[] calldata currencies) external nonReentrant {
        require(currencies.length > 0, "No currencies");
        uint256 activePts = points[msg.sender];

        // First pass: compute total payout across requested currencies (without mutating storage)
        uint256 totalPayout = 0;
        for (uint256 i = 0; i < currencies.length; i++) {
            address cur = currencies[i];
            uint256 owedActive = 0;
            if (activePts > 0) {
                uint256 lastCum = userCumPerPoint[msg.sender][cur];
                uint256 curCum = cumulativeRewardPerPoint[cur];
                if (curCum > lastCum) {
                    owedActive = (activePts * (curCum - lastCum)) / SCALE;
                }
            }
            uint256 pending = pendingRewards[msg.sender][cur];
            totalPayout += (pending + owedActive);
        }

        // Require at least one non-zero payout to proceed (preserves previous test expectations)
        require(totalPayout > 0, "Payout zero");

        // Second pass: perform checkpointing, zero pending, transfer payouts and emit events
        for (uint256 i = 0; i < currencies.length; i++) {
            address cur = currencies[i];
            uint256 owedActive = 0;
            if (activePts > 0) {
                uint256 lastCum = userCumPerPoint[msg.sender][cur];
                uint256 curCum = cumulativeRewardPerPoint[cur];
                if (curCum > lastCum) {
                    owedActive = (activePts * (curCum - lastCum)) / SCALE;
                }
            }
            uint256 pending = pendingRewards[msg.sender][cur];
            uint256 payout = pending + owedActive;

            // checkpoint and zero pending
            userCumPerPoint[msg.sender][cur] = cumulativeRewardPerPoint[cur];
            pendingRewards[msg.sender][cur] = 0;

            if (payout == 0) {
                // nothing to transfer for this currency
                continue;
            }

            if (cur == address(0)) {
                require(address(this).balance >= payout, "Insufficient contract balance");
                (bool sent, ) = msg.sender.call{value: payout}("");
                require(sent, "ETH transfer failed");
            } else {
                (bool ok, bytes memory data) = cur.call(abi.encodeWithSelector(0xa9059cbb, msg.sender, payout)); // transfer
                require(ok && (data.length == 0 || abi.decode(data, (bool))), "ERC20 transfer failed");
            }
            emit RewardsWithdrawn(msg.sender, cur, payout);
        }

        // Burn half of user's points as penalty once per withdraw call
        uint256 burned = 0;
        if (points[msg.sender] > 0) {
            burned = points[msg.sender] / 2;
            points[msg.sender] = points[msg.sender] - burned;
            totalPoints -= burned;
        }
    }

    /// @notice Emergency: admin may withdraw ETH from contract (use with care).
    function ownerWithdraw(address payable to, uint256 amount) external {
        require(_isDegenAdmin(msg.sender), "DegenPool: not admin");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }

    /// @notice Helper to read user's points
    function getPoints(address user) external view returns (uint256) {
        return points[user];
    }

    /// @notice Helper to read enabled reward currencies
    function getRewardCurrencies() external view returns (address[] memory) {
        return rewardCurrencies;
    }

    /// @notice Helper that prefers role-based checks when AccessControl is configured,
    /// otherwise falls back to legacy owner semantics for compatibility.
    function _isDegenAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_DEGEN_ADMIN, user);
        }
        return user == owner;
    }
}