// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- Uniswap V4 Periphery Imports ---
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

// --- MemoryCard Interface ---
import {IMemoryCard} from "./IMemoryCard.sol";

/**
 * @title TakeProfitsCommand
 * @notice Stateless command for "take profits" logic, compatible with MasterControl/MemoryCard system.
 *         All persistent state is stored in MemoryCard, using msg.sender (MasterControl) as namespace.
 *         Uses ROM for large/infrequently updated data (pendingOrders).
 */
contract TakeProfitsCommand {
    using FixedPointMathLib for uint256;

    // --- Errors ---
    error InvalidOrder();
    error NothingToClaim();
    error NotEnoughToClaim();

    // --- MemoryCard Key Helpers ---
    // All keys are namespaced by poolId, tick, and zeroForOne as needed.
    function _pendingOrdersKey(bytes32 poolId, int24 tick, bool zeroForOne) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("pendingOrders:", poolId, ":", tick, ":", zeroForOne));
    }
    function _claimTokensSupplyKey(uint256 orderId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("claimTokensSupply:", orderId));
    }
    function _claimableOutputTokensKey(uint256 orderId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("claimableOutputTokens:", orderId));
    }

    // --- Tick Math ---
    function getLowerUsableTick(int24 tick, int24 tickSpacing) public pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) intervals--;
        return intervals * tickSpacing;
    }

    // --- OrderId ---
    function getOrderId(bytes32 poolId, int24 tick, bool zeroForOne) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(poolId, tick, zeroForOne)));
    }

    // --- Place Order ---
    function placeOrder(
        address memoryCardAddr,
        address poolManagerAddr,
        bytes32 poolId,
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmount,
        address user
    ) external {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        bytes32 pendingKey = _pendingOrdersKey(poolId, tick, zeroForOne);
        IMemoryCard mc = IMemoryCard(memoryCardAddr);

        // --- Use ROM for pendingOrders ---
        uint256 prevPending = _readPendingFromRom(mc, msg.sender, pendingKey);
        uint256 newPending = prevPending + inputAmount;
        mc.saveToRom(pendingKey, abi.encodePacked(newPending));

        // Mint claim tokens to user (delegatecall context: MasterControl)
        uint256 orderId = getOrderId(poolId, tick, zeroForOne);
        bytes32 claimSupplyKey = _claimTokensSupplyKey(orderId);
        uint256 prevSupply = _toUint256(mc.read(msg.sender, claimSupplyKey));
        mc.write(claimSupplyKey, abi.encode(prevSupply + inputAmount));
        _mintDelegate(user, orderId, inputAmount);

        // Token transfer must be handled by the caller (MasterControl) before/after this call.
    }

    // --- Cancel Order ---
    function cancelOrder(
        address memoryCardAddr,
        bytes32 poolId,
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 amountToCancel,
        address user
    ) external {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 orderId = getOrderId(poolId, tick, zeroForOne);
        bytes32 pendingKey = _pendingOrdersKey(poolId, tick, zeroForOne);
        bytes32 claimSupplyKey = _claimTokensSupplyKey(orderId);

        IMemoryCard mc = IMemoryCard(memoryCardAddr);

        // Check claim tokens
        uint256 positionTokens = _balanceOf(user, orderId);
        if (positionTokens < amountToCancel) revert NotEnoughToClaim();

        // --- Use ROM for pendingOrders ---
        uint256 prevPending = _readPendingFromRom(mc, msg.sender, pendingKey);
        uint256 newPending = prevPending - amountToCancel;
        mc.saveToRom(pendingKey, abi.encodePacked(newPending));

        // Update claimTokensSupply
        uint256 prevSupply = _toUint256(mc.read(msg.sender, claimSupplyKey));
        mc.write(claimSupplyKey, abi.encode(prevSupply - amountToCancel));

        // Burn claim tokens (delegatecall context)
        _burnDelegate(user, orderId, amountToCancel);

        // Token transfer must be handled by the caller (MasterControl) before/after this call.
    }

    // --- Redeem ---
    function redeem(
        address memoryCardAddr,
        bytes32 poolId,
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmountToClaimFor,
        address user
    ) external {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 orderId = getOrderId(poolId, tick, zeroForOne);
        bytes32 claimableKey = _claimableOutputTokensKey(orderId);
        bytes32 claimSupplyKey = _claimTokensSupplyKey(orderId);

        IMemoryCard mc = IMemoryCard(memoryCardAddr);

        uint256 claimable = _toUint256(mc.read(msg.sender, claimableKey));
        if (claimable == 0) revert NothingToClaim();

        uint256 claimTokens = _balanceOf(user, orderId);
        if (claimTokens < inputAmountToClaimFor) revert NotEnoughToClaim();

        uint256 totalInputAmountForPosition = _toUint256(mc.read(msg.sender, claimSupplyKey));
        uint256 outputAmount = inputAmountToClaimFor.mulDivDown(claimable, totalInputAmountForPosition);

        // Update claimableOutputTokens and claimTokensSupply
        mc.write(claimableKey, abi.encode(claimable - outputAmount));
        mc.write(claimSupplyKey, abi.encode(totalInputAmountForPosition - inputAmountToClaimFor));

        // Burn claim tokens (delegatecall context)
        _burnDelegate(user, orderId, inputAmountToClaimFor);

        // Token transfer must be handled by the caller (MasterControl) before/after this call.
    }

    // --- Execute Order (to be called by MasterControl after swap) ---
    function executeOrder(
        address memoryCardAddr,
        bytes32 poolId,
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {
        bytes32 pendingKey = _pendingOrdersKey(poolId, tick, zeroForOne);
        uint256 orderId = getOrderId(poolId, tick, zeroForOne);
        bytes32 claimableKey = _claimableOutputTokensKey(orderId);

        IMemoryCard mc = IMemoryCard(memoryCardAddr);

        // --- Use ROM for pendingOrders ---
        uint256 prevPending = _readPendingFromRom(mc, msg.sender, pendingKey);
        uint256 newPending = prevPending - inputAmount;
        mc.saveToRom(pendingKey, abi.encodePacked(newPending));

        // Update claimableOutputTokens
        uint256 prevClaimable = _toUint256(mc.read(msg.sender, claimableKey));
        mc.write(claimableKey, abi.encode(prevClaimable + outputAmount));
    }

    // --- ROM Read Helper for pendingOrders ---
    function _readPendingFromRom(IMemoryCard mc, address user, bytes32 key) internal view returns (uint256) {
        bytes memory data = mc.readFromRom(user, key);
        if (data.length == 0) return 0;
        // Compact: expect abi.encodePacked(uint256)
        uint256 v;
        assembly { v := mload(add(data, 0x20)) }
        return v;
    }

    // --- ERC1155 Mint/Burn via delegatecall context ---
    function _mintDelegate(address to, uint256 id, uint256 amount) internal {
        // Call MasterControl's mintPoints via delegatecall context
        bytes4 selector = bytes4(keccak256("mintPoints(address,uint256,uint256)"));
        (bool success, ) = address(this).call(abi.encodeWithSelector(selector, to, id, amount));
        require(success, "Delegatecall to _mint failed");
    }
    function _burnDelegate(address from, uint256 id, uint256 amount) internal {
        // Call MasterControl's burnPoints via delegatecall context (if implemented)
        bytes4 selector = bytes4(keccak256("burnPoints(address,uint256,uint256)"));
        (bool success, ) = address(this).call(abi.encodeWithSelector(selector, from, id, amount));
        require(success, "Delegatecall to _burn failed");
    }
    function _balanceOf(address user, uint256 id) internal view returns (uint256) {
        (bool success, bytes memory data) = address(this).staticcall(abi.encodeWithSignature("balanceOf(address,uint256)", user, id));
        require(success, "balanceOf failed");
        return abi.decode(data, (uint256));
    }

    // --- Utility: bytes to uint256 ---
    function _toUint256(bytes memory value) internal pure returns (uint256 v) {
        if (value.length < 32) return 0;
        assembly { v := mload(add(value, 0x20)) }
    }
}