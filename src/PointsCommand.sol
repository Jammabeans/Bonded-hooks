// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
//import {IMemoryCard} from "./IMemoryCard.sol";

interface IMemoryCard {
    function read(address user, bytes32 key) external view returns (bytes memory);
    function write(bytes32 key, bytes calldata value) external;
}


contract PointsCommand {
    // "Pointers" to contract addresses you MUST pass in context/data:
    // - memoryCardAddr: our generic read/write state store (your MemoryCard address)
    // - pointsToken: ERC1155 NFT contract address (or use in-memory points if you want store-only points)
    // All config/admin state is stored in the memoryCard.

    // Encodes all context/state/config addresses as the first fields of calldata (`context`)
    // Any hardcoded byte keys should be defined as constants.

    // KEYS for MemoryCard storage slots (can be improved/scoped per pool/user if needed)
    bytes32 constant KEY_BONUS_THRESHOLD = keccak256("bonus_threshold");
    bytes32 constant KEY_BONUS_PERCENT = keccak256("bonus_percent");
    bytes32 constant KEY_BASE_POINTS_PERCENT = keccak256("base_points_percent");

    // --- Entry point for dispatcher via delegatecall ---
    // context must include memoryCard address, pointsToken address, config keys as needed
    struct AfterSwapInput {
        address memoryCardAddr;
        address pointsTokenAddr;
        uint256 poolId; // or PoolId type
        address user; // trade recipient
        int256 amount0;
        int256 amount1;
        bytes swapParams; // if needed, or parse as more fields
    }

    // Typed entrypoint for dispatcher (MasterControl will call this via delegatecall).
    // Signature: afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData, bytes calldata extra)
    // Returns an int128 (optional), encoded by the callee. Commands that do not need to return a value can return 0.
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData,
        bytes calldata extra
    ) external returns (int128) {

        // Require hookData to be present for this command's operation (MasterControl/test provides it).
        require(hookData.length > 0, "PointsCommand.afterSwap: missing hookData");

        // Decode authoritative AfterSwapInput from hookData. If malformed, revert.
        AfterSwapInput memory input = abi.decode(hookData, (AfterSwapInput));

        // Use memoryCard address from the decoded input (delegatecall context => address(this) == MasterControl)
        IMemoryCard mc = IMemoryCard(input.memoryCardAddr);
 
        // Derive poolKeyHash from the PoolKey param so settings are per-pool
        bytes32 poolKeyHash = keccak256(abi.encode(key));
        bytes32 thresholdKey = keccak256(abi.encode(KEY_BONUS_THRESHOLD, poolKeyHash));
        bytes32 bonusKey = keccak256(abi.encode(KEY_BONUS_PERCENT, poolKeyHash));
        bytes32 basePointsKey = keccak256(abi.encode(KEY_BASE_POINTS_PERCENT, poolKeyHash));
 
        // Read per-pool config from MemoryCard under this contract's caller slot (delegatecall context => address(this) == MasterControl)
        uint256 threshold = toUint256(mc.read(address(this), thresholdKey));
        uint256 bonusPercent = toUint256(mc.read(address(this), bonusKey));
        uint256 basePointsPercent = toUint256(mc.read(address(this), basePointsKey));

        // Use explicit amount from the decoded input (authoritative)
        int256 amount0 = input.amount0;

        // Only run for buys (negative amount0 indicates ETH spent)
        if (amount0 >= 0) {
            return int128(0);
        }

        uint256 ethSpendAmount = uint256(-amount0);
        uint256 pointsForSwap = (ethSpendAmount * basePointsPercent) / 100;

        if (ethSpendAmount >= threshold && bonusPercent > 0) {
            uint256 bonusPoints = (pointsForSwap * bonusPercent) / 100;
            pointsForSwap += bonusPoints;
        }

        // Determine poolId to use as token id — prefer the explicit input.poolId
        uint256 tokenId = input.poolId;

        if (pointsForSwap > 0) {
            // Mint points via MasterControl's mintPoints (will be called from delegatecall context)
            _mintDelegate(input.user, tokenId, pointsForSwap);
        } else {
        }

        // No meaningful int128 to return; return 0 for compatibility
        return int128(0);
    }
    function _mintDelegate(address to, uint256 id, uint256 amount) internal {
        // Call the ERC1155 _mint function in the delegatecall context (MasterControl)
        // function _mint(address to, uint256 id, uint256 amount, bytes memory data)
        bytes4 selector = bytes4(keccak256("mintPoints(address,uint256,uint256)"));
        (bool success, ) = address(this).call(abi.encodeWithSelector(selector, to, id, amount));
        require(success, "Delegatecall to _mint failed");
    }


    // Helper for try/catch decoding

    // --- Stateless admin "setters"/"getters" (callable via dispatcher with encoded input) ---

    function setBonusThreshold(bytes calldata data) external {
        // Expect encoded (address memoryCardAddr, bytes32 poolKeyHash, uint256 newThreshold)
        (address memoryCardAddr, bytes32 poolKeyHash, uint256 newThreshold) = abi.decode(data, (address, bytes32, uint256));
        bytes32 storageKey = keccak256(abi.encode(KEY_BONUS_THRESHOLD, poolKeyHash));
        IMemoryCard(memoryCardAddr).write(storageKey, abi.encode(newThreshold));
    }

    function setBonusPercent(bytes calldata data) external {
        // Expect encoded (address memoryCardAddr, bytes32 poolKeyHash, uint256 newPercent)
        (address memoryCardAddr, bytes32 poolKeyHash, uint256 newPercent) = abi.decode(data, (address, bytes32, uint256));
        bytes32 storageKey = keccak256(abi.encode(KEY_BONUS_PERCENT, poolKeyHash));
        IMemoryCard(memoryCardAddr).write(storageKey, abi.encode(newPercent));
    }

    function setBasePointsPercent(bytes calldata data) external {
        // Expect encoded (address memoryCardAddr, bytes32 poolKeyHash, uint256 newPercent)
        (address memoryCardAddr, bytes32 poolKeyHash, uint256 newPercent) = abi.decode(data, (address, bytes32, uint256));
        bytes32 storageKey = keccak256(abi.encode(KEY_BASE_POINTS_PERCENT, poolKeyHash));
        IMemoryCard(memoryCardAddr).write(storageKey, abi.encode(newPercent));
    }

    // This function will resolve to MasterControl's mintPoints via delegatecall
    function mintPoints(address to, uint256 id, uint256 amount) internal {
        // The actual implementation is in MasterControl
        // This is just a placeholder for the selector
        // The call will be handled by delegatecall context
        // (no-op here)
    }

    function toUint256(bytes memory value) internal pure returns (uint256 v) {
        if (value.length < 32) return 0;
        assembly { v := mload(add(value, 0x20)) }
    }
}