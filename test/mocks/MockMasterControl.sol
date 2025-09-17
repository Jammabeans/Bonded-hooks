// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal mock MasterControl used by operator integration tests.
/// It exposes the PoolRebateReady event and a function to emit it on-demand.
contract MockMasterControl {
    event PoolRebateReady(address indexed txOrigin, address indexed trader, uint256 indexed poolId, uint256 poolTotalFeeBips, uint256 baseGasPrice);

    /// @notice Emit PoolRebateReady for testing the off-chain operator.
    function emitPoolRebateReady(
        address txOrigin,
        address trader,
        uint256 poolId,
        uint256 poolTotalFeeBips,
        uint256 baseGasPrice
    ) external {
        emit PoolRebateReady(txOrigin, trader, poolId, poolTotalFeeBips, baseGasPrice);
    }
}