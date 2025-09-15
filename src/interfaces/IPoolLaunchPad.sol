// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title IPoolLaunchPad
/// @notice Interface for PoolLaunchPad helpers that create tokens and initialize pools.
interface IPoolLaunchPad {
    event TokenCreated(address indexed creator, address token);
    event PoolInitialized(address indexed creator, PoolId poolId);

    function manager() external view returns (address);
    function accessControl() external view returns (address);

    function createTokenFull(string calldata name, string calldata symbol, uint256 supply) external returns (address);

    function createNewTokenAndInitWithNative(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 tokenSupply,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr);

    function createSuppliedTokenAndInitWithNative(
        address existingTokenAddr,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr);

    function createNewTokenAndInitWithToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 tokenSupply,
        address otherTokenAddr,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr);

    function initWithSuppliedTokens(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId);

    /// @notice Return all PoolIds created through this LaunchPad.
    function allPools() external view returns (PoolId[] memory);

    receive() external payable;
}