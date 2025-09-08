// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Bonding - per-command bonded pots and reward distribution
/// @notice Users may deposit ETH/ERC20 as bonds for a command/target. Bond principal is non-withdrawable by users.
///         Only authorized withdrawers (GasBank, ShareSplitter) may pull bonded principal from specific users.
///         Authorized publishers (e.g., MasterControl) may forward fees into this contract to be distributed pro-rata
///         to bonders of a target/currency via a rewards-per-share accounting model.
/// @dev This contract is intentionally conservative: users cannot withdraw their principal; only authorized withdrawers
///      can reduce a user's bonded amount. Reward distribution uses a fixed PRECISION constant.

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./AccessControl.sol";

contract Bonding {
    uint256 public constant PRECISION = 1e36;
 
    // Legacy owner (deployer) retained for backwards compatibility; prefer role-based checks via AccessControl.
    address public owner;
 
    // Central AccessControl registry (optional - zero address means legacy owner mode)
    AccessControl public accessControl;
 
    // Role constants
    bytes32 public constant ROLE_BONDING_PUBLISHER = keccak256("ROLE_BONDING_PUBLISHER");
    bytes32 public constant ROLE_BONDING_WITHDRAWER = keccak256("ROLE_BONDING_WITHDRAWER");
    bytes32 public constant ROLE_BONDING_ADMIN = keccak256("ROLE_BONDING_ADMIN");
 
    /// @notice Backwards-compatible toggle maps. During migration these remain valid;
    /// require either the boolean toggle OR the corresponding role in AccessControl.
    mapping(address => bool) public authorizedPublisher;
    mapping(address => bool) public authorizedWithdrawer;
 
    // Per-target per-currency total bonded principal
    // target => currency => total amount
    mapping(address => mapping(address => uint256)) public totalBonded;

    // Per-target per-currency cumulative rewards per share
    // rewardsPerShare[target][currency] measured in PRECISION units
    mapping(address => mapping(address => uint256)) public rewardsPerShare;

    // Per-user bonded principal
    // target => user => currency => amount
    mapping(address => mapping(address => mapping(address => uint256))) internal _bondedAmount;

    // Per-user reward debt for each target/currency: user.rewardDebt = user.amount * rewardsPerShare at deposit/adjust time
    mapping(address => mapping(address => mapping(address => uint256))) internal _rewardDebt;

    // Unallocated fees when no bonders exist for the target/currency
    mapping(address => mapping(address => uint256)) public unallocatedFees;

    // Events
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PublisherToggled(address indexed publisher, bool enabled);
    event WithdrawerToggled(address indexed withdrawer, bool enabled);
    event BondDeposited(address indexed target, address indexed user, address indexed currency, uint256 amount);
    event FeeRecorded(address indexed target, address indexed currency, uint256 amount);
    event RewardClaimed(address indexed target, address indexed user, address indexed currency, uint256 amount);
    // Note: limited to 3 indexed params per event
    event BondWithdrawnByAuthorized(address indexed target, address indexed user, address indexed currency, uint256 amount, address to);

    // Reentrancy guard
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Bonding: reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyOwner() {
        require(_isBondingAdmin(msg.sender), "Bonding: only owner");
        _;
    }

    modifier onlyPublisher() {
        require(
            authorizedPublisher[msg.sender] ||
            (address(accessControl) != address(0) && accessControl.hasRole(ROLE_BONDING_PUBLISHER, msg.sender)),
            "Bonding: only publisher"
        );
        _;
    }

    modifier onlyWithdrawer() {
        require(
            authorizedWithdrawer[msg.sender] ||
            (address(accessControl) != address(0) && accessControl.hasRole(ROLE_BONDING_WITHDRAWER, msg.sender)),
            "Bonding: only withdrawer"
        );
        _;
    }

    constructor(AccessControl _accessControl) {
        owner = msg.sender;
        accessControl = _accessControl;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // Owner management
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Bonding: zero owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    // Admin: toggle authorized publisher
    function setAuthorizedPublisher(address publisher, bool enabled) external onlyOwner {
        authorizedPublisher[publisher] = enabled;
        emit PublisherToggled(publisher, enabled);
    }

    // Admin: toggle authorized withdrawer (GasBank / ShareSplitter)
    function setAuthorizedWithdrawer(address withdrawer, bool enabled) external onlyOwner {
        authorizedWithdrawer[withdrawer] = enabled;
        emit WithdrawerToggled(withdrawer, enabled);
    }

    // View helpers

    /// @notice Return bonded amount for a user under a specific target and currency
    function bondedAmount(address target, address user, address currency) external view returns (uint256) {
        return _bondedAmount[target][user][currency];
    }

    /// @notice View pending reward for user for a target/currency
    function pendingReward(address target, address user, address currency) external view returns (uint256) {
        uint256 userAmount = _bondedAmount[target][user][currency];
        if (userAmount == 0) return 0;
        uint256 rps = rewardsPerShare[target][currency];
        uint256 accrued = (userAmount * rps) / PRECISION;
        uint256 debt = _rewardDebt[target][user][currency];
        if (accrued <= debt) return 0;
        return accrued - debt;
    }

    // --- Deposits (users deposit bonds) ---
    /// @notice Deposit native ETH as bond for target
    /// @param target The command/target contract address the bond is for
    function depositBondNative(address target) external payable nonReentrant {
        require(msg.value > 0, "Bonding: zero deposit");
        _deposit(msg.sender, target, address(0), msg.value);
        emit BondDeposited(target, msg.sender, address(0), msg.value);
    }

    /// @notice Deposit ERC20 tokens as bond for target
    /// @param target The command/target contract address the bond is for
    /// @param currency ERC20 token address (non-zero)
    /// @param amount Amount to deposit (must be approved beforehand)
    function depositBondERC20(address target, address currency, uint256 amount) external nonReentrant {
        require(currency != address(0), "Bonding: use native for ETH");
        require(amount > 0, "Bonding: zero deposit");
        // Transfer tokens from depositor into this contract
        _safeTransferFrom(currency, msg.sender, address(this), amount);
        _deposit(msg.sender, target, currency, amount);
        emit BondDeposited(target, msg.sender, currency, amount);
    }

    // Internal deposit bookkeeping
    function _deposit(address user, address target, address currency, uint256 amount) internal {
        // Update rewards for user before changing principal
        uint256 currentRPS = rewardsPerShare[target][currency];
        // increase totalBonded and userAmount
        uint256 prevAmount = _bondedAmount[target][user][currency];
        uint256 newAmount = prevAmount + amount;
        _bondedAmount[target][user][currency] = newAmount;
        totalBonded[target][currency] += amount;

        // Update reward debt so user does not receive past rewards
        // rewardDebt = newAmount * currentRPS / PRECISION
        _rewardDebt[target][user][currency] = (newAmount * currentRPS) / PRECISION;
    }

    // --- Publishers push fees to be distributed to bonders --- 
    /// @notice Record a fee for a target/currency. For native, sender must send ETH equal to amount.
    ///         For ERC20, this function will attempt to pull tokens from the caller (so caller must approve).
    /// @param target The command/target address the fee belongs to
    /// @param currency Currency address (address(0) for native)
    /// @param amount Amount of fee to record/distribute
    function recordFee(address target, address currency, uint256 amount) external payable nonReentrant onlyPublisher {
        require(amount > 0, "Bonding: zero fee");
        if (currency == address(0)) {
            require(msg.value == amount, "Bonding: incorrect native amount");
        } else {
            // pull ERC20 from publisher into this contract
            _safeTransferFrom(currency, msg.sender, address(this), amount);
        }

        uint256 total = totalBonded[target][currency];
        if (total == 0) {
            // No bonders for this target/currency — retain as unallocated
            unallocatedFees[target][currency] += amount;
            emit FeeRecorded(target, currency, amount);
            return;
        }

        // Add to rewardsPerShare: amount * PRECISION / total
        uint256 addition = (amount * PRECISION) / total;
        rewardsPerShare[target][currency] += addition;
        emit FeeRecorded(target, currency, amount);
    }

    // --- Claim rewards ---
    /// @notice Claim accumulated rewards for multiple (target,currency) pairs
    /// @param targets Array of targets to claim for
    /// @param currencies Array of currencies; must match `targets` length
    function claimRewards(address[] calldata targets, address[] calldata currencies) external nonReentrant {
        require(targets.length == currencies.length, "Bonding: length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            _claimOne(targets[i], currencies[i], msg.sender);
        }
    }

    // Internal claim for one pair to reduce stack
    function _claimOne(address target, address currency, address to) internal {
        uint256 userAmount = _bondedAmount[target][to][currency];
        if (userAmount == 0) {
            // nothing to claim; still update debt to current level
            _rewardDebt[target][to][currency] = (userAmount * rewardsPerShare[target][currency]) / PRECISION;
            return;
        }
        uint256 rps = rewardsPerShare[target][currency];
        uint256 accrued = (userAmount * rps) / PRECISION;
        uint256 debt = _rewardDebt[target][to][currency];
        if (accrued <= debt) {
            // update debt and return
            _rewardDebt[target][to][currency] = accrued;
            return;
        }
        uint256 payout = accrued - debt;
        // Update reward debt to current level
        _rewardDebt[target][to][currency] = accrued;

        // Transfer payout
        if (currency == address(0)) {
            _safeNativeTransfer(to, payout);
        } else {
            _safeTransfer(currency, to, payout);
        }
        emit RewardClaimed(target, to, currency, payout);
    }

    // --- Authorized withdrawers may reduce a user's bond (principal) and receive tokens/ETH ---
    /// @notice Withdraw principal from a specific user's bond for a target/currency. Only callable by authorized withdrawer.
    /// @param target Command/target address
    /// @param user The bonded user to deduct from
    /// @param currency Currency to withdraw
    /// @param amount Amount to withdraw (must be <= user's bonded amount)
    /// @param to Recipient of withdrawn funds
    function withdrawBondFrom(address target, address user, address currency, uint256 amount, address to) external nonReentrant onlyWithdrawer {
        require(amount > 0, "Bonding: zero withdraw");
        uint256 userAmount = _bondedAmount[target][user][currency];
        require(userAmount >= amount, "Bonding: insufficient bonded");
        // Reduce principal and totalBonded
        uint256 newUserAmount = userAmount - amount;
        _bondedAmount[target][user][currency] = newUserAmount;
        totalBonded[target][currency] -= amount;

        // Adjust user's rewardDebt to reflect the smaller principal:
        uint256 rps = rewardsPerShare[target][currency];
        _rewardDebt[target][user][currency] = (newUserAmount * rps) / PRECISION;

        // Transfer funds to `to`
        if (currency == address(0)) {
            _safeNativeTransfer(to, amount);
        } else {
            _safeTransfer(currency, to, amount);
        }
        emit BondWithdrawnByAuthorized(target, user, currency, amount, to);
    }

    // --- Utilities: safe transfers ---

    /// @notice Helper: is the supplied account an admin for bonding actions?
    /// Prefers role-based check when AccessControl is configured, otherwise falls back to legacy owner.
    function _isBondingAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_BONDING_ADMIN, user);
        }
        return user == owner;
    }
 
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Bonding: ERC20 transferFrom failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Bonding: ERC20 transfer failed");
    }

    function _safeNativeTransfer(address to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Bonding: native transfer failed");
    }

    // Fallback to accept native for situations where publisher calls recordFee with native
    receive() external payable {}
}