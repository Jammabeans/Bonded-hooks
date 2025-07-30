// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- Uniswap V4 Periphery Imports ---
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {console} from "forge-std/console.sol";

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

contract MasterControl is BaseHook {
    struct HookInstance {
        address hookAddress;
        bool enabled;
        string name;
    }

    enum CallType { Delegate, Call }

    struct Command {
        address target;
        bytes4 selector;
        bytes data; // optional extra data
        CallType callType;
    }

    // poolKeyHash => hookPath (bytes32) => array of commands
    mapping(bytes32 => mapping(bytes32 => Command[])) public poolCommands;

    mapping(bytes32 => HookInstance[]) private hooksByPath;
    bytes32[] public hookPaths;

    event HookAdded(bytes32 indexed hookPath, address indexed hook, string name);
    event HookToggled(bytes32 indexed hookPath, address indexed hook, bool enabled);
    event CommandsSet(bytes32 indexed poolKeyHash, bytes32 indexed hookPath, Command[] commands);

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function addHook(string memory hookPath, address hook, string memory name) external {
        bytes32 path = keccak256(bytes(hookPath));
        if (hooksByPath[path].length == 0) {
            hookPaths.push(path);
        }
        hooksByPath[path].push(HookInstance({hookAddress: hook, enabled: true, name: name}));
        emit HookAdded(path, hook, name);
    }

    function setHookEnabled(string memory hookPath, address hook, bool enabled) external {
        bytes32 path = keccak256(bytes(hookPath));
        HookInstance[] storage arr = hooksByPath[path];
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i].hookAddress == hook) {
                arr[i].enabled = enabled;
                emit HookToggled(path, hook, enabled);
                return;
            }
        }
        revert("Hook not found");
    }

    function getHooks(string memory hookPath) external view returns (HookInstance[] memory) {
        return hooksByPath[keccak256(bytes(hookPath))];
    }

    function getAllHookPaths() external view returns (bytes32[] memory) {
        return hookPaths;
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
        uint160
    ) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        runHooks(poolKeyHash, hookPath, abi.encode("beforeInitialize", key, ""));
        return this.beforeInitialize.selector;
    }

    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        runHooks(poolKeyHash, hookPath, abi.encode("afterInitialize", key, ""));
        return this.afterInitialize.selector;
    }

    // 2. Add Liquidity Hooks

    function _beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        console.log("----_beforeAddLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        
        runHooks(poolKeyHash, hookPath, abi.encode("beforeAddLiquidity", key, params, hookData));
        return (this.beforeAddLiquidity.selector);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        bytes32 poolKeyHash = getPoolKeyHash(key);
        bytes32 hookPath = getPoolHookPath(key);
        console.log("----_afterAddLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        // Encode delta as bytes, pass through runHooksWithValue, decode result
        bytes memory result_ = runHooksWithValue(poolKeyHash, hookPath, abi.encode("afterAddLiquidity", key, params, hookData), abi.encode(delta));
        BalanceDelta updatedDelta = abi.decode(result_, (BalanceDelta));
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
        bytes32 poolKeyHash = getPoolKeyHash(key);
        console.log("----_beforeRemoveLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        runHooks(poolKeyHash, hookPath, abi.encode("beforeRemoveLiquidity", key, params, hookData));
        return (this.beforeRemoveLiquidity.selector);
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        bytes32 poolKeyHash = getPoolKeyHash(key);
        bytes32 hookPath = getPoolHookPath(key);
        console.log("----_afterRemoveLiquidity sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        bytes memory result_ = runHooksWithValue(poolKeyHash, hookPath, abi.encode("afterRemoveLiquidity", key, params, hookData), abi.encode(delta));
        BalanceDelta updatedDelta = abi.decode(result_, (BalanceDelta));
        return (this.afterRemoveLiquidity.selector, updatedDelta);
    }

    // 4. Swap Hooks

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal override returns (bytes4, BeforeSwapDelta , uint24) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        console.log("");
        console.log("----_beforeSwap sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        console.log("Swap Params - Amount Specified: ", params.amountSpecified);
        console.log("Swap Params - Sqrt Price Limit: ", params.sqrtPriceLimitX96);
        console.log("Swap Params - Zero For One: ", params.zeroForOne);
        console.log("Pool Key Hash: ");
        console.logBytes32(getPoolKeyHash(key));
        console.log("Hook Path: ");
        console.logBytes32(getPoolHookPath(key));
        console.log("");

        // Run hooks with the context of "beforeSwap"
        runHooks(poolKeyHash, hookPath, abi.encode("beforeSwap", key, params, hookData));
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA , uint24(0));
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        bytes32 poolKeyHash = getPoolKeyHash(key);
        bytes32 hookPath = getPoolHookPath(key);
        console.log("");
        console.log("----_afterSwap sender: ", sender);
        console.log("tx.origin: ", tx.origin);
        console.log("msg.sender: ", msg.sender);
        console.log("this contract address: ", address(this));
        console.log("Swap Params:");
        console.log("Sender: ", sender);
        
        console.log("Pool Key Hash: ");
        console.logBytes32( getPoolKeyHash(key));
        console.log("Hook Path: ");
        console.logBytes32( getPoolHookPath(key));
        console.log("Swap Params - Amount Specified: ", params.amountSpecified);
        console.log("Swap Params - Sqrt Price Limit: ", params.sqrtPriceLimitX96);
        console.log("Swap Params - Zero For One: ", params.zeroForOne);
        console.log("Balance Delta - Amount 0: ", delta.amount0());
        console.log("Balance Delta - Amount 1: ", delta.amount1());
        console.log("");
        bytes memory result_ = runHooksWithValue(poolKeyHash, hookPath, abi.encode("afterSwap", key, params, hookData), abi.encode(delta));
        // If afterSwap expects int128, decode as such; adjust as needed for your use case
        //int128 updatedValue = abi.decode(result_, (int128));
        console.log("After swap hook updated value: ");
        return (this.afterSwap.selector, 0);
    }

    // 5. Donate Hooks

    function _beforeDonate(address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        runHooks(poolKeyHash, hookPath, abi.encode("beforeDonate", key, a, b, hookData));
        return this.beforeDonate.selector;
    }

    function _afterDonate(address sender, PoolKey calldata key, uint256 a, uint256 b, bytes calldata hookData) internal override returns (bytes4) {
        bytes32 hookPath = getPoolHookPath(key);
        bytes32 poolKeyHash = getPoolKeyHash(key);
        runHooks(poolKeyHash, hookPath, abi.encode("afterDonate", key, a, b, hookData));
        return this.afterDonate.selector;
    }

    // --- Universal Hook Runner ---

    // Passes a value (as bytes) through each command, updating it with each command's return value
    function runHooksWithValue(bytes32 poolKeyHash, bytes32 hookPath, bytes memory context, bytes memory initialValue) internal returns (bytes memory) {
        console.log("Running hooks with value:");
        
        Command[] storage cmds = poolCommands[poolKeyHash][hookPath];
        bytes memory value = initialValue;
        console.log("Initial value: ");
        console.logBytes32(bytes32(value));
        console.log( "comands length: ", cmds.length);
        for (uint i = 0; i < cmds.length; i++) {
            (bool success, bytes memory ret) = cmds[i].callType == CallType.Delegate
                ? cmds[i].target.delegatecall(abi.encodePacked(cmds[i].selector, context, value, cmds[i].data))
                : cmds[i].target.call(abi.encodePacked(cmds[i].selector, context, value, cmds[i].data));
            require(success, "Hook command failed");
            value = ret;
        }
        console.log("Final value after hooks: ");
        console.logBytes32(bytes32(value));
        return value;
    }

    function runHooks(bytes32 poolKeyHash, bytes32 hookPath, bytes memory context) internal {
        Command[] storage cmds = poolCommands[poolKeyHash][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodePacked(cmds[i].selector, context, cmds[i].data)
                );
                require(success, "Delegatecall failed");
            } else if (cmds[i].callType == CallType.Call) {
                (success, ) = cmds[i].target.call(
                    abi.encodePacked(cmds[i].selector, context, cmds[i].data)
                );
                require(success, "Call failed");
            }
        
            
        }
    }

    // --- User Command Management ---

    
        // Set commands for a poolKeyHash and hookPath
        function setCommands(bytes32 poolKeyHash, bytes32 hookPath, Command[] calldata commands) external {
            delete poolCommands[poolKeyHash][hookPath];
            for (uint i = 0; i < commands.length; i++) {
                poolCommands[poolKeyHash][hookPath].push(commands[i]);
            }
            emit CommandsSet(poolKeyHash, hookPath, commands);
        }

    function getCommands(bytes32 poolKeyHash, bytes32 hookPath) external view returns (Command[] memory) {
        return poolCommands[poolKeyHash][hookPath];
    }

    // --- Utility: Derive hook path from PoolKey (customize as needed) ---
    function getPoolHookPath(PoolKey calldata key) internal pure returns (bytes32) {
        // Use abi.encode (not abi.encodePacked) for struct types
        return keccak256(abi.encode(key));
    }

    // Utility: Derive poolKeyHash from PoolKey
    function getPoolKeyHash(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    
}