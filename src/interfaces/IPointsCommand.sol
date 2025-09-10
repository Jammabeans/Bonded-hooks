// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title IPointsCommand
/// @notice Interface for the PointsCommand hook implementation.
interface IPointsCommand {
    /// @notice Exposed constant indicating command fee in basis points.
    function COMMAND_FEE_BIPS() external view returns (uint256);

    /// @notice Hook entrypoint called after a swap. Returns an optional int128 encoded value.
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (int128);

    /// @notice Minimal metadata used when registering the command via MasterControl.
    function commandMetadata() external view returns (address target, bytes4 selector, uint8 callType);
}