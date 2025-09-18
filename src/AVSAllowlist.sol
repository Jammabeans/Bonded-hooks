// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title AVSAllowlist
/// @notice Lightweight on-chain allowlist that lets bidders (or an admin) grant an AVS address
///         permission to read a bidder's encrypted bid from a given BidManager contract.
///         This is a minimal helper that avoids changing the BidManager implementation and
///         provides an on-chain attestation the AVS operator can check before unsealing off-chain.
contract AVSAllowlist {
    address public owner;

    // key = keccak256(abi.encodePacked(bidManager, bidder, avs))
    mapping(bytes32 => bool) public allowed;

    event AllowGranted(address indexed bidManager, address indexed bidder, address indexed avs);
    event AllowRevoked(address indexed bidManager, address indexed bidder, address indexed avs);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "AVSAllowlist: not owner");
        _;
    }

    /// @notice Grant permission for an AVS to read a bidder's encrypted bid stored in `bidManager`
    /// @dev Can be called by the bidder themselves or by the owner (admin).
    function grantRead(address bidManager, address bidder, address avs) external {
        require(msg.sender == bidder || msg.sender == owner, "AVSAllowlist: not bidder or owner");
        bytes32 k = keccak256(abi.encodePacked(bidManager, bidder, avs));
        allowed[k] = true;
        emit AllowGranted(bidManager, bidder, avs);
    }

    /// @notice Revoke permission for an AVS
    /// @dev Can be called by the bidder themselves or by the owner (admin).
    function revokeRead(address bidManager, address bidder, address avs) external {
        require(msg.sender == bidder || msg.sender == owner, "AVSAllowlist: not bidder or owner");
        bytes32 k = keccak256(abi.encodePacked(bidManager, bidder, avs));
        allowed[k] = false;
        emit AllowRevoked(bidManager, bidder, avs);
    }

    /// @notice Query whether the AVS is allowed to read the bidder for the given bidManager
    function isAllowed(address bidManager, address bidder, address avs) external view returns (bool) {
        bytes32 k = keccak256(abi.encodePacked(bidManager, bidder, avs));
        return allowed[k];
    }

    /// @notice Owner can transfer ownership
    function transferOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AVSAllowlist: zero owner");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }
}