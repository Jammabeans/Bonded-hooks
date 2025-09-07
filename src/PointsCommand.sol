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

// Minimal MasterControl read interface used by commands at delegatecall-time
interface IMasterControl {
    function memoryCard() external view returns (address);
}

// Optional helper interface: some routers/wrappers expose a msgSender() helper to reveal the user
// that triggered a proxied call. We will try to call this on the `sender` address and skip minting
// if the call reverts or returns address(0).
interface IMsgSender {
    function msgSender() external view returns (address);
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
    // Fixed, contract-embedded hook fee (in basis points). Immutable for this command.
    // Use bips (1 bip = 0.01%). Example: 5 bips = 0.05% fee.
    uint256 public constant COMMAND_FEE_BIPS = 5;

    // --- Entry point for dispatcher via delegatecall ---
    // context must include memoryCard address, pointsToken address, config keys as needed
    struct AfterSwapInput {
        uint256 poolId; // canonical numeric PoolId
        address user; // trade recipient
        int256 amount0;
        int256 amount1;
        bytes swapParams; // if needed, or parse as more fields
    }

    // Typed entrypoint for dispatcher (MasterControl will call this via delegatecall).
    // Signature: afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
    // Returns an int128 (optional), encoded by the callee. Commands that do not need to return a value can return 0.
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata /*params*/,
        BalanceDelta delta,
        bytes calldata /*hookData*/
    ) external returns (int128) {

        // Obtain MemoryCard address from MasterControl (delegatecall context => address(this) == MasterControl)
        address mcAddr = IMasterControl(address(this)).memoryCard();
        require(mcAddr != address(0), "PointsCommand: memoryCard not set");
        IMemoryCard mc = IMemoryCard(mcAddr);

        // Derive canonical poolId from the PoolKey (copy calldata to memory to call toId())
        PoolKey memory mk = key;
        PoolId pid = mk.toId();
        uint256 poolId = uint256(PoolId.unwrap(pid));


        // Compute ETH spent from the BalanceDelta (negative amount0 indicates ETH spent)
        if (delta.amount0() >= 0) {
            return int128(0);
        }
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
 
        // Compute points using helper to reduce stack usage
        uint256 pointsForSwap = _computePointsForSwap(mc, poolId, ethSpendAmount);

        // Try to resolve the recipient using IMsgSender on the `sender` address.
        // If it reverts or returns address(0), skip minting for this call.
        address recipient = address(0);
        
        try IMsgSender(sender).msgSender() returns (address r) {
            recipient = r;
        } catch {
            return int128(0);
        }

        if (recipient == address(0)) return int128(0);

        

        if (pointsForSwap > 0) {
            // Mint points via MasterControl's mintPoints (will be called from delegatecall context)
            _mintDelegate(recipient, poolId, pointsForSwap);
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
    

    /// @notice Helper to compute points for a given ETH spend using configured percents and threshold.
    /// This function reads per-pool config from MemoryCard to avoid stacking many locals in afterSwap.
    function _computePointsForSwap(IMemoryCard mc, uint256 poolId, uint256 ethSpendAmount) internal view returns (uint256) {
        if (ethSpendAmount == 0) return 0;
        bytes32 thresholdKey = keccak256(abi.encode(KEY_BONUS_THRESHOLD, poolId));
        bytes32 bonusKey = keccak256(abi.encode(KEY_BONUS_PERCENT, poolId));
        bytes32 basePointsKey = keccak256(abi.encode(KEY_BASE_POINTS_PERCENT, poolId));
        uint256 threshold = toUint256(mc.read(address(this), thresholdKey));
        uint256 bonusPercent = toUint256(mc.read(address(this), bonusKey));
        uint256 basePointsPercent = toUint256(mc.read(address(this), basePointsKey));
        if (basePointsPercent == 0) return 0;
        uint256 points = (ethSpendAmount * basePointsPercent) / 100;
        if (ethSpendAmount >= threshold && bonusPercent > 0) {
            uint256 bonus = (points * bonusPercent) / 100;
            points += bonus;
        }
        return points;
    }

    /// @notice Returns minimal metadata needed by owner to approve this command
    /// target: contract address to call (this contract)
    /// selector: function selector for the hook entrypoint
    /// callType: 0 = Delegate, 1 = Call
    function commandMetadata() external view returns (address target, bytes4 selector, uint8 callType) {
        target = address(this);
        selector = this.afterSwap.selector;
        callType = 0; // Delegate
    }
 
    function toUint256(bytes memory value) internal pure returns (uint256 v) {
        if (value.length < 32) return 0;
        assembly { v := mload(add(value, 0x20)) }
    }
}