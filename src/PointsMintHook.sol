// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract PointsMintHook is ERC1155 {
    string public constant NAME = "Points Mint Hook";
    string public constant DESCRIPTION = "Mints ERC1155 points to users when they swap ETH for TOKEN in a V4 pool.";

    constructor(IPoolManager _manager)
        // BaseHook(_manager)
    {}

    // --- Metadata Getters for Plugin Info ---
    function getName() external pure returns (string memory) {
        return NAME;
    }

    function getDescription() external pure returns (string memory) {
        return DESCRIPTION;
    }

    // --- Hook Permissions ---
    function getHookPermissions()
        public
        pure
       // override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // --- ERC1155 URI ---
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    // --- Points Assignment Helper ---
    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        if (hookData.length == 0) return;
        address user = abi.decode(hookData, (address));
        if (user == address(0)) return;
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user, poolIdUint, points, "");
    }

    // --- afterSwap Hook Implementation ---
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal   {
        // Only for ETH-TOKEN pools
        if (!key.currency0.isAddressZero()) return ();
        // Only mint points if user is buying TOKEN with ETH
        if (!swapParams.zeroForOne) return ();

        // Mint points equal to 20% of the amount of ETH spent
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;
        _assignPoints(key.toId(), hookData, pointsForSwap);

        return ();
    }
}