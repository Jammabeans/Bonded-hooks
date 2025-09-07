// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "./masterControl.t.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract TestMasterControlSwapPaths is TestMasterControl {

    /// @notice Helper that performs a swap with the given direction and amount.
    /// Returns true on success, false and logs revert reason on failure.
    function doSwap(bool zeroForOne, int256 amount) public returns (bool) {
        PointsCommand.AfterSwapInput memory afterSwapInput = PointsCommand.AfterSwapInput({
            poolId: poolIdUint,
            user: address(this),
            amount0: zeroForOne ? amount : int256(0),
            amount1: zeroForOne ? int256(0) : amount,
            swapParams: ""
        });
        bytes memory hookData = abi.encode(afterSwapInput);

        uint256 value = 0;
        if (zeroForOne && amount < 0) {
            value = uint256(-amount);
        }

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({takeClaims:false, settleUsingBurn:false});

        try swapRouter.swap{value: value}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        ) returns (BalanceDelta /*delta*/) {
            return true;
        } catch (bytes memory reason) {
            // Log reason to make debugging easier in failing CI runs
            emit log_bytes(reason);
            return false;
        }
    }

    function test_exactInput_zeroForOne() public {
        bool ok = doSwap(true, -0.001 ether);
        assertTrue(ok, "exactInput zeroForOne failed");
    }

    function test_exactInput_oneForZero() public {
        bool ok = doSwap(false, -0.001 ether);
        assertTrue(ok, "exactInput oneForZero failed");
    }

    function test_exactOutput_zeroForOne() public {
        // exact-output native-input: supply a small msg.value buffer so settle has funds
        bool ok = doSwapWithValue(true, int256(1000), 0.01 ether);
        assertTrue(ok, "exactOutput zeroForOne failed with 0.01 ether provided");
    }

    function test_exactOutput_oneForZero() public {
        bool ok = doSwap(false, int256(1000));
        assertTrue(ok, "exactOutput oneForZero failed");
    }
    /// @notice Helper that allows specifying an explicit msg.value for the swap call.
    function doSwapWithValue(bool zeroForOne, int256 amount, uint256 value) public returns (bool) {
        PointsCommand.AfterSwapInput memory afterSwapInput = PointsCommand.AfterSwapInput({
            poolId: poolIdUint,
            user: address(this),
            amount0: zeroForOne ? amount : int256(0),
            amount1: zeroForOne ? int256(0) : amount,
            swapParams: ""
        });
        bytes memory hookData = abi.encode(afterSwapInput);

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({takeClaims:false, settleUsingBurn:false});

        try swapRouter.swap{value: value}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        ) returns (BalanceDelta /*delta*/) {
            return true;
        } catch (bytes memory reason) {
            // Log reason to make debugging easier in failing CI runs
            emit log_bytes(reason);
            return false;
        }
    }

    function test_exactOutput_zeroForOne_insufficientValue() public {
        // exact-output native-input with zero msg.value should revert / fail (insufficient funds)
        bool ok = doSwapWithValue(true, int256(1000), 0);
        assertTrue(!ok, "expected exact-output zeroForOne to fail with zero value");
    }

    function test_exactOutput_zeroForOne_sufficientValue() public {
        // Provide a small buffer for exact-output native path; expected to succeed
        bool ok = doSwapWithValue(true, int256(1000), 0.01 ether);
        assertTrue(ok, "exactOutput zeroForOne failed with small buffer");
    }

    function test_exactOutput_zeroForOne_excessValue() public {
        // Excessive value should also succeed and extra ETH should be refunded to the caller.
        uint256 beforeBal = address(this).balance;
        bool ok = doSwapWithValue(true, int256(1000), 1 ether);
        uint256 afterBal = address(this).balance;
        assertTrue(ok, "exactOutput zeroForOne failed with large value");
        // Ensure we were not charged anywhere near the full 1 ether we supplied.
        // Use a conservative threshold (0.02 ETH) — the swap should consume << 0.02 ETH for this small output.
        require(beforeBal >= afterBal, "balance increased unexpectedly");
        uint256 spent = beforeBal - afterBal;
        assertTrue(spent <= 0.02 ether, "excess value not refunded (spent too much)");
    }
}