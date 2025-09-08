// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/PrizeBox.sol";
import "../../src/Shaker.sol";

contract MockAVS {
    // Create a box via PrizeBox (acts as the AVS caller)
    function createBox(PrizeBox pb, address owner) external returns (uint256) {
        return pb.createBox(owner);
    }

    // Register share tokens into a box (AVS-only on PrizeBox)
    function registerShare(PrizeBox pb, uint256 boxId, address token, uint256 amount) external {
        pb.registerShareTokens(boxId, token, amount);
    }

    // Deposit native ETH into a box (forwarded from the AVS caller)
    function depositToBox(PrizeBox pb, uint256 boxId) external payable {
        pb.depositToBox{value: msg.value}(boxId);
    }

    // Deposit ERC20 into a box (AVS helper)
    function depositERC20ToBox(PrizeBox pb, uint256 boxId, address token, uint256 amount) external {
        pb.depositToBoxERC20(boxId, token, amount);
    }

    // Award a box to `to`
    function awardBoxTo(PrizeBox pb, uint256 boxId, address to) external {
        pb.awardBoxTo(boxId, to);
    }

    // Shaker helpers
    function startRound(Shaker sh, uint256 poolId) external returns (uint256) {
        return sh.startRound(poolId);
    }

    function finalizeRound(Shaker sh, uint256 roundId, uint256[] calldata boxIds, uint256 seed) external {
        sh.finalizeRound(roundId, boxIds, seed);
    }

    function awardWinnerBox(Shaker sh, uint256 roundId, uint256 boxId) external {
        sh.awardWinnerBox(roundId, boxId);
    }

    receive() external payable {}
}