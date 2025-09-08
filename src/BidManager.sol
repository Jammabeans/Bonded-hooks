// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AccessControl.sol";

/// @title BidManager
/// @notice Minimal on-chain bid manager for GasRebate AVS
contract BidManager {
    // Legacy owner retained for compatibility; prefer role-based checks via AccessControl.
    address public owner;
    AccessControl public accessControl;
    bytes32 public constant ROLE_BID_MANAGER_ADMIN = keccak256("ROLE_BID_MANAGER_ADMIN");

    uint256 public constant MIN_BID_WEI = 0.01 ether;
    uint32 public constant MAX_RUSH = 1000;

    struct Bid {
        address bidder;
        uint256 totalBidAmount;
        uint256 maxSpendPerEpoch;
        uint256 minMintingRate;
        uint32 rushFactor;
        uint64 createdEpoch;
        uint64 lastUpdatedEpoch;
    }

    // One bid per bidder (keyed by address)
    mapping(address => Bid) public bids;
    mapping(uint256 => bool) public epochProcessed;
    mapping(address => bool) public settlementRole;

    event BidCreated(address indexed bidder, uint256 totalBidAmount, uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor);
    event BidToppedUp(address indexed bidder, uint256 amountWei);
    event BidUpdatedRush(address indexed bidder, uint32 newRushFactor, uint64 effectiveEpoch);
    event BidConsumed(address indexed bidder, uint256 amountConsumed);
    event EpochFinalized(uint256 indexed epoch, address indexed operator);
    event SettlementRoleUpdated(address indexed operator, bool enabled);

    modifier onlySettlement() {
        require(settlementRole[msg.sender], "Caller is not settlement role");
        _;
    }

    constructor(AccessControl _accessControl) {
        owner = msg.sender;
        accessControl = _accessControl;
    }

    function setSettlementRole(address operator, bool enabled) external {
        require(_isAdmin(msg.sender), "BidManager: not admin");
        settlementRole[operator] = enabled;
        emit SettlementRoleUpdated(operator, enabled);
    }

    /// @notice Create a bid for msg.sender. Each address may only have one active bid.
    function createBid(uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor) external payable {
        require(msg.value >= MIN_BID_WEI, "Bid below minimum");
        require(rushFactor <= MAX_RUSH, "rushFactor out of range");
        require(bids[msg.sender].bidder == address(0), "Bid exists");

        bids[msg.sender] = Bid({
            bidder: msg.sender,
            totalBidAmount: msg.value,
            maxSpendPerEpoch: maxSpendPerEpoch,
            minMintingRate: minMintingRate,
            rushFactor: rushFactor,
            createdEpoch: uint64(block.timestamp),
            lastUpdatedEpoch: uint64(block.timestamp)
        });

        emit BidCreated(msg.sender, msg.value, maxSpendPerEpoch, minMintingRate, rushFactor);
    }

    /// @notice Top up the caller's bid by sending ETH with this call.
    function topUpBid() external payable {
        Bid storage b = bids[msg.sender];
        require(b.bidder != address(0), "Unknown bid");
        require(msg.value > 0, "No ETH sent");
        b.totalBidAmount += msg.value;
        emit BidToppedUp(msg.sender, msg.value);
    }

    /// @notice Update caller's rush factor which may take effect per operator policy.
    function updateRushFactor(uint32 newRush, uint64 effectiveEpoch) external {
        require(newRush <= MAX_RUSH, "rushFactor out of range");
        Bid storage b = bids[msg.sender];
        require(b.bidder != address(0), "Unknown bid");
        b.rushFactor = newRush;
        b.lastUpdatedEpoch = effectiveEpoch;
        emit BidUpdatedRush(msg.sender, newRush, effectiveEpoch);
    }

    function getBid(address bidder) external view returns (Bid memory) {
        return bids[bidder];
    }

    /// @notice Finalize an epoch by consuming amounts from bidders' bids. `bidders` and `consumedAmounts` must match.
    function finalizeEpochConsumeBids(
        uint256 epoch,
        address[] calldata bidders,
        uint256[] calldata consumedAmounts
    ) external onlySettlement {
        require(!epochProcessed[epoch], "Epoch already processed");
        require(bidders.length == consumedAmounts.length, "Mismatched arrays");

        for (uint256 i = 0; i < bidders.length; i++) {
            address bidderAddr = bidders[i];
            Bid storage b = bids[bidderAddr];
            require(b.bidder != address(0), "Unknown bid");

            uint256 consume = consumedAmounts[i];
            if (consume > 0) {
                require(b.totalBidAmount >= consume, "Not enough bid balance");
                b.totalBidAmount -= consume;
                emit BidConsumed(b.bidder, consume);
            }
        }

        epochProcessed[epoch] = true;
        emit EpochFinalized(epoch, msg.sender);
    }

    function ownerRecoverBid(address bidderAddr, address payable to, uint256 amount) external {
        require(_isAdmin(msg.sender), "BidManager: not admin");
        Bid storage b = bids[bidderAddr];
        require(b.bidder != address(0), "Unknown bid");
        require(b.totalBidAmount >= amount, "Insufficient bid balance");
        b.totalBidAmount -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Transfer failed");
    }

    function ownerWithdraw(address payable to, uint256 amount) external {
        require(_isAdmin(msg.sender), "BidManager: not admin");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }
 
    function _isAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_BID_MANAGER_ADMIN, user);
        }
        return user == owner;
    }
}