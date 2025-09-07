// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "./masterControl.t.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MasterControlFeeDiagnostics is TestMasterControl {
    event Diagnostic(string msg, address addr, uint256 val);

    function _logManagerBalances(PoolId pid) internal {
        // currency0 / currency1 may be native (addr(0)) or ERC20
        Currency c0 = key.currency0;
        Currency c1 = key.currency1;
        emit Diagnostic("manager balance c0", address(manager), currencyBalance(c0));
        emit Diagnostic("manager balance c1", address(manager), currencyBalance(c1));
    }

    function currencyBalance(Currency c) internal view returns (uint256) {
        if (c.isAddressZero()) {
            // native balance of PoolManager (manager)
            return address(manager).balance;
        } else {
            address t = Currency.unwrap(c);
            return IERC20(t).balanceOf(address(manager));
        }
    }

    /// @notice Run a swap and print manager balances before/after to see what token was available to take from.
    function diag_swap_and_log(bool zeroForOne, int256 amount) public returns (bool ok) {
        PointsCommand.AfterSwapInput memory afterSwapInput = PointsCommand.AfterSwapInput({
            poolId: poolIdUint,
            user: address(this),
            amount0: zeroForOne ? amount : int256(0),
            amount1: zeroForOne ? int256(0) : amount,
            swapParams: ""
        });
        bytes memory hookData = abi.encode(afterSwapInput);

        // Snapshot manager balances before
        emit Diagnostic("BEFORE balance c0", address(manager), currencyBalance(key.currency0));
        emit Diagnostic("BEFORE balance c1", address(manager), currencyBalance(key.currency1));

        uint256 value = 0;
        // exact-input native swaps forward msg.value; for exact-output native-input tests supply a small buffer
        if (zeroForOne) {
            if (amount < 0) {
                value = uint256(-amount);
            } else {
                // provide a small test buffer for exact-output native path
                value = 0.01 ether;
            }
        }

        try swapRouter.swap{value: value}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims:false, settleUsingBurn:false}),
            hookData
        ) returns (BalanceDelta /*d*/) {
            ok = true;
        } catch (bytes memory reason) {
            emit Diagnostic("swap reverted", address(this), reason.length);
            ok = false;
        }

        // Snapshot manager balances after
        emit Diagnostic("AFTER balance c0", address(manager), currencyBalance(key.currency0));
        emit Diagnostic("AFTER balance c1", address(manager), currencyBalance(key.currency1));
    }

    function test_diag_exactInput_zeroForOne() public {
        bool ok = diag_swap_and_log(true, -0.001 ether);
        assertTrue(ok, "diag exactInput zeroForOne failed");
    }

    function test_diag_exactInput_oneForZero() public {
        bool ok = diag_swap_and_log(false, -0.001 ether);
        assertTrue(ok, "diag exactInput oneForZero failed");
    }

    function test_diag_exactOutput_zeroForOne() public {
        bool ok = diag_swap_and_log(true, int256(1000));
        assertTrue(ok, "diag exactOutput zeroForOne failed");
    }

    function test_diag_exactOutput_oneForZero() public {
        bool ok = diag_swap_and_log(false, int256(1000));
        assertTrue(ok, "diag exactOutput oneForZero failed");
    }
}