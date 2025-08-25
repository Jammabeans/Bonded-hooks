// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
// --- Uniswap V4 Periphery Imports ---
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {console} from "forge-std/console.sol";
import {AccessControl} from "./AccessControl.sol";

// --- Hook Interface for Dispatch ---
interface IHook {
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);
    // Add other hook entrypoints as needed...
}

contract MasterControl is BaseHook, ERC1155 {

    enum CallType { Delegate, Call }

    struct Command {
        address target;
        bytes4 selector;
        bytes data; // optional extra data
        CallType callType;
    }

    // poolId => hookPath (bytes32) => array of commands
    mapping(uint256 => mapping(bytes32 => Command[])) public poolCommands;
    
    // Access control registry (maps poolId => admin)
    AccessControl public accessControl;

    // MasterControl admin (contract-level)
    address public owner;

    // Approved commands registry per hookPath: hookPath => target => selector => enabled
    mapping(bytes32 => mapping(address => mapping(bytes4 => bool))) public commandEnabled;

    event CommandsSet(uint256 indexed poolId, bytes32 indexed hookPath, bytes32 commandsHash);
    
    event CommandApproved(bytes32 indexed hookPath, address indexed target, bytes4 selector, string name);
    event CommandToggled(bytes32 indexed hookPath, address indexed target, bytes4 selector, bool enabled);

    /// @notice Approve a command (target + selector) for a hookPath. Owner-only.
    function approveCommand(bytes32 hookPath, address target, bytes4 selector, string memory name) external {
        require(msg.sender == owner, "MasterControl: only owner");
        commandEnabled[hookPath][target][selector] = true;
        emit CommandApproved(hookPath, target, selector, name);
    }

    /// @notice Toggle approval for a command for a hookPath. Owner-only.
    function setCommandEnabled(bytes32 hookPath, address target, bytes4 selector, bool enabled) external {
        require(msg.sender == owner, "MasterControl: only owner");
        commandEnabled[hookPath][target][selector] = enabled;
        emit CommandToggled(hookPath, target, selector, enabled);
    }

    constructor(IPoolManager _manager) BaseHook(_manager) {
        owner = msg.sender;
    }
    
    
    /// @notice Owner-only: set the AccessControl contract used by MasterControl
    function setAccessControl(address _accessControl) external {
        require(msg.sender == owner, "MasterControl: only owner");
        require(_accessControl != address(0), "MasterControl: zero address");
        accessControl = AccessControl(_accessControl);
    }
    
    // Address of the authorized PoolLaunchPad contract that may register pool admins
    address public poolLaunchPad;

    /// @notice Owner-only: set the PoolLaunchPad address the MasterControl will accept registrations from
    function setPoolLaunchPad(address _pad) external {
        require(msg.sender == owner, "MasterControl: only owner");
        poolLaunchPad = _pad;
    }

    /// @notice Called by the PoolLaunchPad when it initializes a pool to register the pool admin.
    /// Only callable by the configured PoolLaunchPad contract.
    function registerPoolAdmin(PoolKey calldata key, address admin) external {
        require(poolLaunchPad != address(0), "MasterControl: poolLaunchPad not set");
        require(msg.sender == poolLaunchPad, "MasterControl: only PoolLaunchPad");
        uint256 poolId = getPoolId(key);
        accessControl.setPoolAdmin(poolId, admin);
    }

    // --- ERC1155 URI ---
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    // --- Mint function for PointsCommand ---
    function mintPoints(address to, uint256 id, uint256 amount) external {
        // Only allow delegatecall from this contract (PointsCommand runs via delegatecall)
        require(address(this) == msg.sender, "Only callable via delegatecall");
        _mint(to, id, amount, "");
    }





    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterAddLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: true,
                afterRemoveLiquidityReturnDelta: true
            });
    }

    // --- Hook Entrypoints (Dispatcher Pattern) ---
    // All hooks now forward to runHooks with a hookPath

    // 1. Initialize Hooks

    function _beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96
    ) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        // Forward full typed parameters to hook commands: sender, key, sqrtPriceX96
        runHooks_BeforeInitialize(poolId, hookPath, sender, key, sqrtPriceX96);
        return this.beforeInitialize.selector;
    }
 
    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        // Forward full typed parameters to hook commands: sender, key, sqrtPriceX96, tick
        runHooks_AfterInitialize(poolId, hookPath, sender, key, sqrtPriceX96, tick);
        return this.afterInitialize.selector;
    }
 
    // 2. Add Liquidity Hooks
 
    function _beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        console.log("----_beforeAddLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
 
        // Forward sender + typed args
        runHooks_BeforeAddLiquidity(poolId, hookPath, sender, key, params, hookData);
        return (this.beforeAddLiquidity.selector);
    }
 
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta /*unusedPreDelta*/,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        uint256 poolId = getPoolId(key);
        bytes32 hookPath = getPoolHookPath(key);
        console.log("----_afterAddLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        // Build full context including the BalanceDelta so delegate targets that parse bytes can extract it
        BalanceDelta updatedDelta = runHooks_AfterAddLiquidity(poolId, hookPath, sender, key, params, delta, hookData);
        return (this.afterAddLiquidity.selector, updatedDelta);
    }
 
    // 3. Remove Liquidity Hooks
 
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        console.log("----_beforeRemoveLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        runHooks_BeforeRemoveLiquidity(poolId, hookPath, sender, key, params, hookData);
        return (this.beforeRemoveLiquidity.selector);
    }
 
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta /*unused*/,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        uint256 poolId = getPoolId(key);
        bytes32 hookPath = getPoolHookPath(key);
        console.log("----_afterRemoveLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        BalanceDelta updatedDelta = runHooks_AfterRemoveLiquidity(poolId, hookPath, sender, key, params, delta, hookData);
        return (this.afterRemoveLiquidity.selector, updatedDelta);
    }
 
    // 4. Swap Hooks
 
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal override returns (bytes4, BeforeSwapDelta , uint24) {
        uint256 poolId = getPoolId(key);
        bytes32 hookPath = keccak256(
            abi.encodePacked(
                "beforeSwap",
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                key.hooks
            )
        );
        console.log("");
        console.log("----_beforeSwap sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        console.log("Swap Params - Amount Specified: ", params.amountSpecified);
        console.log("Swap Params - Sqrt Price Limit: ", params.sqrtPriceLimitX96);
        console.log("Swap Params - Zero For One: ", params.zeroForOne);
        console.log("Pool Id: ");
        console.logUint(poolId);
        console.log("Hook Path: ");
        console.logBytes32(getPoolHookPath(key));
        console.log("");
 
        // Forward structured args to typed hook runners
        (BeforeSwapDelta _bsd, uint24 _u) = runHooks_BeforeSwap(poolId, hookPath, sender, key, params, hookData);
        return (this.beforeSwap.selector, _bsd , _u);
    }
 
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        uint256 poolId = getPoolId(key);
        bytes32 hookPath = keccak256(
            abi.encodePacked(
                "afterSwap",
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                key.hooks
            )
        );
        console.log("");
        console.log("----_afterSwap sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        console.log("MasterControl contract address: ", address(this));
        console.log("Swap Params:");
        console.log("Sender: ", sender);
 
        console.log("Pool Id: ");
        console.logUint(poolId);
        console.log("Hook Path: ");
        console.logBytes32(getPoolHookPath(key));
        console.log("Swap Params - Amount Specified: ", params.amountSpecified);
        console.log("Swap Params - Sqrt Price Limit: ", params.sqrtPriceLimitX96);
        console.log("Swap Params - Zero For One: ", params.zeroForOne);
        console.log("Balance Delta - Amount 0: ", delta.amount0());
        console.log("Balance Delta - Amount 1: ", delta.amount1());
        console.log("");
        // Call typed afterSwap runners; they return an int128 if applicable
        int128 updatedValue = runHooks_AfterSwap(poolId, hookPath, sender, key, params, delta, hookData);
        console.log("After swap hook updated value: ");
        return (this.afterSwap.selector, updatedValue);
    }
 
    // 5. Donate Hooks
 
    function _beforeDonate(address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        runHooks_BeforeDonate(poolId, hookPath, sender, key, a, b, hookData);
        return this.beforeDonate.selector;
    }
 
    function _afterDonate(address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        runHooks_AfterDonate(poolId, hookPath, sender, key, a, b, hookData);
        return this.afterDonate.selector;
    }

    // --- Universal Hook Runner ---

    // Passes a value (as bytes) through each command, updating it with each command's return value
    function runHooksWithValue(uint256 poolId, bytes32 hookPath, bytes memory context, bytes memory initialValue) internal returns (bytes memory) {
        console.log("Running hooks with value:");
        
        Command[] storage cmds = poolCommands[poolId][hookPath];
        bytes memory value = initialValue;
        console.log("Initial value: ");
        console.logBytes32(bytes32(value));
        console.log( "comands length: ", cmds.length);
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            bytes memory ret;
            if (cmds[i].callType == CallType.Delegate) {
                // Log context length and first 10 bytes
                console.log("runHooksWithValue: context.length = ", context.length);
                bytes memory first10 = new bytes(context.length < 10 ? context.length : 10);
                for (uint j = 0; j < first10.length; j++) {
                    first10[j] = context[j];
                }
                console.log("runHooksWithValue: first 10 bytes of context:");
                for (uint j = 0; j < first10.length; j++) {
                    console.log(uint8(first10[j]));
                }
                // Delegate case: append the current 'value' after the context so targets receiving both context and value can decode them
                (success, ret) = cmds[i].target.delegatecall(abi.encodeWithSelector(cmds[i].selector, context, value, cmds[i].data));
            } else {
                // External call: pack selector + context + current value + extra data
                (success, ret) = cmds[i].target.call(abi.encodeWithSelector(cmds[i].selector, context, value, cmds[i].data));
            }
            require(success, "Hook command failed");
            value = ret;
        }
        console.log("Final value after hooks: ");
        console.logBytes32(bytes32(value));
        return value;
    }

    // --- Typed hook runners ---
    // Each runner passes structured ABI parameters (typed) to commands and appends the command's configured bytes as a trailing `bytes` param.
    // Commands are expected to implement a matching typed function signature with a trailing `bytes calldata extra` parameter.

    function runHooks_BeforeInitialize(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, uint160 sqrtPriceX96) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks_AfterInitialize(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, tick, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, tick, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks_BeforeAddLiquidity(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks_AfterAddLiquidity(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, bytes calldata hookData) internal returns (BalanceDelta) {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        BalanceDelta current = delta;
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            bytes memory ret;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ret) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData, cmds[i].data)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData, cmds[i].data)
                );
            }
            require(success, "Hook command failed");
            // Expect each command to return an encoded BalanceDelta when applicable
            current = abi.decode(ret, (BalanceDelta));
        }
        return current;
    }

    function runHooks_BeforeRemoveLiquidity(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks_AfterRemoveLiquidity(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, bytes calldata hookData) internal returns (BalanceDelta) {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        BalanceDelta current = delta;
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            bytes memory ret;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ret) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData, cmds[i].data)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData, cmds[i].data)
                );
            }
            require(success, "Hook command failed");
            current = abi.decode(ret, (BalanceDelta));
        }
        return current;
    }

    function runHooks_BeforeSwap(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) internal returns (BeforeSwapDelta, uint24) {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        BeforeSwapDelta resultDelta = BeforeSwapDeltaLibrary.ZERO_DELTA;
        uint24 resultUint = 0;
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            bytes memory ret;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ret) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData, cmds[i].data)
                );
            }
            require(success, "Hook command failed");
            // If the command returns a BeforeSwapDelta + uint24, decode and use it; otherwise ignore
            if (ret.length >= 32) {
                // decode as (BeforeSwapDelta, uint24) packed in ABI => decode to (int256, uint24)
                (int256 bsd, uint24 u) = abi.decode(ret, (int256, uint24));
                resultDelta = BeforeSwapDelta.wrap(bsd);
                resultUint = u;
            }
        }
        return (resultDelta, resultUint);
    }

    function runHooks_AfterSwap(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData) internal returns (int128) {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        int128 resultInt = int128(0);
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            bytes memory ret;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ret) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, delta, hookData, cmds[i].data)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, delta, hookData, cmds[i].data)
                );
            }
            require(success, "Hook command failed");
            if (ret.length >= 32) {
                resultInt = abi.decode(ret, (int128));
            }
        }
        return resultInt;
    }

    function runHooks_BeforeDonate(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks_AfterDonate(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData, cmds[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    // Batch run of Command[] for setup (global admin utility)
    // Now this function invokes commands using the typed-caller convention:
    // abi.encodeWithSelector(selector, <typed params...>, bytes extra)
    function runCommandBatch(Command[] calldata commands) external {
        for (uint i = 0; i < commands.length; i++) {
            bool success;
            // Each Command.data is treated as the trailing `bytes extra` parameter for typed functions
            if (commands[i].callType == CallType.Delegate) {
                (success, ) = commands[i].target.delegatecall(
                    abi.encodeWithSelector(commands[i].selector, commands[i].data)
                );
                require(success, "Delegatecall failed");
            } else if (commands[i].callType == CallType.Call) {
                (success, ) = commands[i].target.call(
                    abi.encodeWithSelector(commands[i].selector, commands[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    // Pool-scoped batch runner (requires pool admin) - now accepts poolId directly
    function runCommandBatchForPool(uint256 poolId, Command[] calldata commands) external {
        require(address(accessControl) != address(0), "AccessControl not configured");
        require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");

        for (uint i = 0; i < commands.length; i++) {
            bool success;
            if (commands[i].callType == CallType.Delegate) {
                (success, ) = commands[i].target.delegatecall(
                    abi.encodeWithSelector(commands[i].selector, commands[i].data)
                );
                require(success, "Delegatecall failed");
            } else if (commands[i].callType == CallType.Call) {
                (success, ) = commands[i].target.call(
                    abi.encodeWithSelector(commands[i].selector, commands[i].data)
                );
                require(success, "Call failed");
            }
        }
    }

    function runHooks(uint256 poolId, bytes32 hookPath, bytes memory context) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, context, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else if (cmds[i].callType == CallType.Call) {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, context, cmds[i].data)
                );
                require(success, "Call failed");
            }
        
            
        }
    }

    // --- User Command Management ---

    
        // Set commands for a pool (scoped) and hookPath — require pool admin and accept poolId directly
        function setCommands(uint256 poolId, bytes32 hookPath, Command[] calldata commands) external {
            require(address(accessControl) != address(0), "AccessControl not configured");
            require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");

            // Ensure each command in the list is approved by owner for this hookPath
            for (uint i = 0; i < commands.length; i++) {
                require(commandEnabled[hookPath][commands[i].target][commands[i].selector], "MasterControl: command not approved");
            }

            delete poolCommands[poolId][hookPath];
            for (uint i = 0; i < commands.length; i++) {
                poolCommands[poolId][hookPath].push(commands[i]);
            }
            bytes32 commandsHash = keccak256(abi.encode(commands));
            emit CommandsSet(poolId, hookPath, commandsHash);
        }

    function getCommands(uint256 poolId, bytes32 hookPath) external view returns (Command[] memory) {
        return poolCommands[poolId][hookPath];
    }

    // --- Utility: Derive hook path from PoolKey (customize as needed) ---
    function getPoolHookPath(PoolKey calldata key) internal pure returns (bytes32) {
        // Use abi.encode (not abi.encodePacked) for struct types
        return keccak256(abi.encode(key));
    }

    // Utility: Derive poolId from PoolKey
    function getPoolId(PoolKey calldata key) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(key)));
    }

    
}