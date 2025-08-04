// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
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

    // Called by dispatcher (via delegatecall) with abi.encoded AfterSwapInput (or similar struct)
    function afterSwap(bytes calldata input) external {
        // Top-level debug log
        console.log("PointsCommand.afterSwap ENTRY");
        console.log("input.length: ", input.length);

        // Log first 64 bytes of input as hex for debugging
        // Log first 10 words of input for debugging
        for (uint i = 0; i < 19 && input.length >= (i+1)*32; i++) {
            bytes32 w;
            w = bytes32(input[i*32:(i+1)*32]);
            console.log("input word", i, ":");
            console.logBytes32(w);
        }

        // Try to decode input, log error if fails
        // Decode as (string, PoolKey, SwapParams, bytes)
        // Extract memoryCard address from word 14 and user address from word 17
        address memoryCardAddr;
        address user;
        if (input.length >= 18 * 32) {
            // Extract memoryCardAddr (word 14)
            bytes32 memCardWord;
            for (uint i = 0; i < 32; i++) {
                memCardWord |= bytes32(input[14*32 + i] & 0xFF) >> (i * 8);
            }
            memoryCardAddr = address(uint160(uint256(memCardWord)));
            // Extract user (word 17)
            bytes32 userWord;
            for (uint i = 0; i < 32; i++) {
                userWord |= bytes32(input[17*32 + i] & 0xFF) >> (i * 8);
            }
            user = address(uint160(uint256(userWord)));
            console.log("Extracted memoryCardAddr (word 14): ", memoryCardAddr);
            console.log("Extracted user (word 17): ", user);
        } else {
            console.log("Input too short to extract memoryCardAddr and user");
            return;
        }
        // Use amountSpecified from SwapParams (word 7 or 18 depending on struct layout)
        int256 amount0 = 0;
        if (input.length >= 8 * 32) {
            // Extract amount0 (word 7)
            bytes32 amtWord;
            for (uint i = 0; i < 32; i++) {
                amtWord |= bytes32(input[7*32 + i] & 0xFF) >> (i * 8);
            }
            amount0 = int256(uint256(amtWord));
            console.log("Extracted amount0 (word 7): ", amount0);
        }
        uint256 poolId = 0; // Set as needed

        IMemoryCard mc = IMemoryCard(memoryCardAddr);

        // Read all params from MemoryCard (could also allow them in input to save gas)
        uint256 threshold = toUint256(mc.read(address(this), KEY_BONUS_THRESHOLD));
        uint256 bonusPercent = toUint256(mc.read(address(this), KEY_BONUS_PERCENT));
        uint256 basePointsPercent = toUint256(mc.read(address(this), KEY_BASE_POINTS_PERCENT));
        console.log("Loaded config from MemoryCard:");
        console.log("  threshold: ", threshold);
        console.log("  bonusPercent: ", bonusPercent);
        console.log("  basePointsPercent: ", basePointsPercent);

        // Only run if a valid "buy" (positive amount ETH spent)
        if (amount0 >= 0) {
            console.log("Not a buy (amount0 >= 0), skipping");
            return;
        }

        uint256 ethSpendAmount = uint256(-amount0);
        uint256 pointsForSwap = (ethSpendAmount * basePointsPercent) / 100;
        console.log("ethSpendAmount: ", ethSpendAmount);
        console.log("pointsForSwap (before bonus): ", pointsForSwap);

        if (ethSpendAmount >= threshold) {
            uint256 bonusPoints = (pointsForSwap * bonusPercent) / 100;
            pointsForSwap += bonusPoints;
            console.log("Bonus applied, bonusPoints: ", bonusPoints);
        }

        // Mint points via MasterControl's ERC1155 (delegatecall context)
        // Extract poolId from PoolKey (words 2–6) or set as needed
        // For now, use word 16 as poolId (if that's the PoolKey hash)
        uint256 extractedPoolId = 0;
        if (input.length >= 17 * 32) {
            bytes32 poolIdWord;
            for (uint i = 0; i < 32; i++) {
                poolIdWord |= bytes32(input[16*32 + i] & 0xFF) >> (i * 8);
            }
            extractedPoolId = uint256(poolIdWord);
            console.log("Extracted poolId (word 16): ", extractedPoolId);
        }
        if (pointsForSwap > 0) {
            // This will call MasterControl's mintPoints via delegatecall context
            console.log("Calling mintPoints:");
            console.log("  user: ", user);
            console.log("  poolId: ", extractedPoolId);
            console.log("  pointsForSwap: ", pointsForSwap);
            _mintDelegate(user, extractedPoolId, pointsForSwap);
        } else {
            console.log("No points to mint");
        }

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

    function setBonusThreshold(address memoryCardAddr, uint256 newThreshold) external {
        IMemoryCard(memoryCardAddr).write(KEY_BONUS_THRESHOLD, abi.encode(newThreshold));
    }

    function setBonusPercent(address memoryCardAddr, uint256 newPercent) external {
        IMemoryCard(memoryCardAddr).write(KEY_BONUS_PERCENT, abi.encode(newPercent));
    }

    function setBasePointsPercent(address memoryCardAddr, uint256 newPercent) external {
        IMemoryCard(memoryCardAddr).write(KEY_BASE_POINTS_PERCENT, abi.encode(newPercent));
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