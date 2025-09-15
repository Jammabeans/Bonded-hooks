// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IBonding
/// @notice Interface for the Bonding contract.
interface IBonding {
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PublisherToggled(address indexed publisher, bool enabled);
    event WithdrawerToggled(address indexed withdrawer, bool enabled);
    event BondDeposited(address indexed target, address indexed user, address indexed currency, uint256 amount);
    event FeeRecorded(address indexed target, address indexed currency, uint256 amount);
    event RewardClaimed(address indexed target, address indexed user, address indexed currency, uint256 amount);
    event BondWithdrawnByAuthorized(address indexed target, address indexed user, address indexed currency, uint256 amount, address to);

    // Hook request events
    event HookRequested(uint256 indexed requestId, address indexed creator, address syntheticTarget, string ipfs);
    event HookActivated(uint256 indexed requestId, address indexed hookAddress);

    // constants / getters
    function PRECISION() external view returns (uint256);
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_BONDING_PUBLISHER() external view returns (bytes32);
    function ROLE_BONDING_WITHDRAWER() external view returns (bytes32);
    function ROLE_BONDING_ADMIN() external view returns (bytes32);

    function authorizedPublisher(address publisher) external view returns (bool);
    function authorizedWithdrawer(address withdrawer) external view returns (bool);

    function totalBonded(address target, address currency) external view returns (uint256);
    function rewardsPerShare(address target, address currency) external view returns (uint256);
    function unallocatedFees(address target, address currency) external view returns (uint256);

    // request getters added
    function nextRequestId() external view returns (uint256);
    function requests(uint256 requestId) external view returns (
        address creator,
        string memory ipfs,
        address synthetic,
        address hookAddress,
        bool active,
        uint256 bounty
    );
    function requestTarget(uint256 requestId) external view returns (address);
    function requestTargetRedirect(address hookAddress) external view returns (address);
    function getRequest(uint256 requestId)
        external
        view
        returns (
            address creator,
            address synthetic,
            address hookAddress,
            bool active,
            uint256 bounty,
            string memory ipfs
        );

    // owner / admin
    function transferOwnership(address newOwner) external;
    function setAuthorizedPublisher(address publisher, bool enabled) external;
    function setAuthorizedWithdrawer(address withdrawer, bool enabled) external;

    // views
    function bondedAmount(address target, address user, address currency) external view returns (uint256);
    function pendingReward(address target, address user, address currency) external view returns (uint256);
    function getTargetTotals(address target, address[] calldata currencies) external view returns (uint256[] memory totals);
    function getUserPrincipalAndPending(address target, address user, address[] calldata currencies)
        external
        view
        returns (uint256[] memory principals, uint256[] memory pendings);

    // deposits
    function depositBondNative(address target) external payable;
    function depositBondERC20(address target, address currency, uint256 amount) external;

    // publishers
    function recordFee(address target, address currency, uint256 amount) external payable;

    // request flow
    function requestHook(string calldata ipfs) external payable returns (uint256 requestId);
    function activateRequest(uint256 requestId, address hookAddress) external;

    // claims and withdraws
    function claimRewards(address[] calldata targets, address[] calldata currencies) external;
    function withdrawBondFrom(address target, address user, address currency, uint256 amount, address to) external;
}