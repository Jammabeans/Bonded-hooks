// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @title IBidManager
/// @notice Interface for the BidManager contract.
interface IBidManager {
    // Struct types
    struct Bid {
        address bidder;
        uint256 totalBidAmount;
        uint256 maxSpendPerEpoch;
        uint256 minMintingRate;
        uint32 rushFactor;
        uint64 createdEpoch;
        uint64 lastUpdatedEpoch;
    }

    // Events
    event BidCreated(address indexed bidder, uint256 totalBidAmount, uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor);
    event BidToppedUp(address indexed bidder, uint256 amountWei);
    event BidUpdatedRush(address indexed bidder, uint32 newRushFactor, uint64 effectiveEpoch);
    event BidConsumed(address indexed bidder, uint256 amountConsumed);
    event EpochFinalized(uint256 indexed epoch, address indexed operator);
    event SettlementRoleUpdated(address indexed operator, bool enabled);

    // Public getters
    function owner() external view returns (address);
    function accessControl() external view returns (address);
    function ROLE_BID_MANAGER_ADMIN() external view returns (bytes32);
    function MIN_BID_WEI() external view returns (uint256);
    function MAX_RUSH() external view returns (uint32);

    function bids(address bidder) external view returns (Bid memory);
    function epochProcessed(uint256 epoch) external view returns (bool);
    function settlementRole(address operator) external view returns (bool);

    // Management
    function setSettlementRole(address operator, bool enabled) external;

    // Bid lifecycle
    function createBid(uint256 maxSpendPerEpoch, uint256 minMintingRate, uint32 rushFactor) external payable;
    function topUpBid() external payable;
    function updateRushFactor(uint32 newRush, uint64 effectiveEpoch) external;
    function getBid(address bidder) external view returns (Bid memory);

    // Settlement
    function finalizeEpochConsumeBids(
        uint256 epoch,
        address[] calldata bidders,
        uint256[] calldata consumedAmounts
    ) external;

    // Owner recovery
    function ownerRecoverBid(address bidderAddr, address payable to, uint256 amount) external;
    function ownerWithdraw(address payable to, uint256 amount) external;
}