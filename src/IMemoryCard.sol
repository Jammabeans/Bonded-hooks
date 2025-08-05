// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMemoryCard
/// @notice Interface for reading and writing arbitrary persistent data for commands/controllers/hooks.
interface IMemoryCard {
    /// @notice Write a value into the caller's storage under a key.
    function write(bytes32 key, bytes calldata value) external;

    /// @notice Read a value for a user/key pair.
    function read(address user, bytes32 key) external view returns (bytes memory);

    /// @notice Clear the caller's value for a key.
    function clear(bytes32 key) external;

    
}