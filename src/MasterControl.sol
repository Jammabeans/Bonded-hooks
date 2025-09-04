// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
// --- Uniswap V4 Periphery Imports ---
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {console} from "forge-std/console.sol";
import {AccessControl} from "./AccessControl.sol";
import {MemoryCard} from "./MemoryCard.sol";

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

// Minimal MemoryCard interface used by MasterControl for pool-scoped config reads/writes
interface IMemoryCard {
    function read(address user, bytes32 key) external view returns (bytes memory);
    function write(bytes32 key, bytes calldata value) external;
}

contract MasterControl is BaseHook, ERC1155 {

    enum CallType { Delegate, Call }
 
    struct Command {
        bytes32 hookPath;
        address target;
        bytes4 selector;
        CallType callType;
    }

    // poolId => hookPath (bytes32) => array of commands
    mapping(uint256 => mapping(bytes32 => Command[])) public poolCommands;
    
    // Access control registry (maps poolId => admin)
    AccessControl public accessControl;
 
    // MasterControl admin (contract-level)
    address public owner;
 
    // Approved commands registry per hookPath: hookPath => target => approved (selectors validated at block/apply time)
    mapping(bytes32 => mapping(address => bool)) public commandEnabled;

    // --- Whitelisted command blocks (owner-managed, ALL_REQUIRED semantics) ---
    // blockId => array of commands (the whitelisted command list for this block)
    mapping(uint256 => Command[]) internal blockCommands;
    // block enabled flag
    mapping(uint256 => bool) public blockEnabled;
    // optional expiry timestamp (0 = no expiry)
    mapping(uint256 => uint64) public blockExpiresAt;
    // Maximum number of commands permitted in a single block to guard against gas exhaustion
    uint256 constant MAX_COMMANDS_PER_BLOCK = 64;
    // Per-block/per-command immutability marker (blockId => commandIndex => immutable)
    mapping(uint256 => mapping(uint256 => bool)) internal blockCommandImmutable;
    // Per-pool lock registry: poolId => hookPath => target => selector => locked (immutable for that pool)
    mapping(uint256 => mapping(bytes32 => mapping(address => mapping(bytes4 => bool)))) public commandLockedForPool;
    // Maximum total commands that may be applied in a single applyBlocksToPool call
    uint256 constant MAX_APPLY_COMMANDS = 256;
    // Address of the authorized PoolLaunchPad contract that may register pool admins
    address public poolLaunchPad;
    
    // MemoryCard used for storing per-pool configuration (owner must set)
    address public memoryCard;
    // Whitelist of allowed config keys for pool admin writes (owner-managed)
    mapping(bytes32 => bool) public allowedConfigKey;
// Bundle semantics (block-level):
// If a block is marked immutable, any commands applied from that block are immutable for that pool.
mapping(uint256 => bool) public blockImmutable;
// Optional conflict group for a block — blocks sharing a non-zero group are mutually exclusive per-pool.
mapping(uint256 => bytes32) public blockConflictGroup;
// Tracks whether a conflict group is active for a given pool (poolId => conflictGroup => active)
mapping(uint256 => mapping(bytes32 => bool)) public poolConflictActive;
// Provenance: record origin blockId for each command applied to a pool
mapping(uint256 => mapping(bytes32 => mapping(address => mapping(bytes4 => uint256)))) public commandOriginBlock;

    event BlockCreated(uint256 indexed blockId, bytes32 indexed hookPath, bytes32 commandsHash);
    event BlockRevoked(uint256 indexed blockId);
    event BlockApplied(uint256 indexed blockId, uint256 indexed poolId, bytes32 indexed hookPath);
    
    event CommandsSet(uint256 indexed poolId, bytes32 indexed hookPath, bytes32 commandsHash);
    
    event CommandApproved(bytes32 indexed hookPath, address indexed target, string name);
    event CommandToggled(bytes32 indexed hookPath, address indexed target, bool enabled);
    event MemoryCardDeployed(address indexed memoryCard);

    /// @notice Approve a command target for a hookPath. Owner-only.
    function approveCommand(bytes32 hookPath, address target, string memory name) external {
        require(msg.sender == owner, "MasterControl: only owner");
        commandEnabled[hookPath][target] = true;
        emit CommandApproved(hookPath, target, name);
    }
    
    /// @notice Toggle approval for a command target for a hookPath. Owner-only.
    function setCommandEnabled(bytes32 hookPath, address target, bool enabled) external {
        require(msg.sender == owner, "MasterControl: only owner");
        commandEnabled[hookPath][target] = enabled;
        emit CommandToggled(hookPath, target, enabled);
    }

    constructor(IPoolManager _manager) BaseHook(_manager) {
        owner = msg.sender;
        // Deploy a MemoryCard by default and set it (owner may override later)
        MemoryCard mc = new MemoryCard();
        memoryCard = address(mc);
        emit MemoryCardDeployed(memoryCard);
    }
    
    
    /// @notice Owner-only: set the AccessControl contract used by MasterControl
    function setAccessControl(address _accessControl) external {
        require(msg.sender == owner, "MasterControl: only owner");
        require(_accessControl != address(0), "MasterControl: zero address");
        accessControl = AccessControl(_accessControl);
    }    
        
    /// @notice Owner-only: set the MemoryCard address used for pool config storage
    function setMemoryCard(address _mc) external {
        require(msg.sender == owner, "MasterControl: only owner");
        require(_mc != address(0), "MasterControl: zero address");
        memoryCard = _mc;
    }
    
    /// @notice Owner-only: toggle allowed config keys that pool admins may write
    /// Pass the canonical key constant (e.g., KEY_BONUS_THRESHOLD) as `key`
    function setAllowedConfigKey(bytes32 key, bool allowed) external {
        require(msg.sender == owner, "MasterControl: only owner");
        allowedConfigKey[key] = allowed;
    }
    
    /// @notice Owner-only: set the PoolLaunchPad address the MasterControl will accept registrations from
    function setPoolLaunchPad(address _pad) external {
        require(msg.sender == owner, "MasterControl: only owner");
        poolLaunchPad = _pad;
    }
    
    /// @notice Pool-admin API to set a per-pool config value into MemoryCard.
    /// storageKey = keccak256(abi.encode(configKeyHash, poolId))
    function setPoolConfigValue(uint256 poolId, bytes32 configKeyHash, bytes calldata value) external {
        require(address(accessControl) != address(0), "AccessControl not configured");
        require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");
        require(memoryCard != address(0), "MasterControl: memoryCard not set");
        require(allowedConfigKey[configKeyHash], "MasterControl: key not allowed");
        bytes32 storageKey = keccak256(abi.encode(configKeyHash, poolId));
        IMemoryCard(memoryCard).write(storageKey, value);
    }
    
    /// @notice Read a per-pool config value from MemoryCard (reads MasterControl's slot)
    function readPoolConfigValue(uint256 poolId, bytes32 configKeyHash) external view returns (bytes memory) {
        require(memoryCard != address(0), "MasterControl: memoryCard not set");
        bytes32 storageKey = keccak256(abi.encode(configKeyHash, poolId));
        return IMemoryCard(memoryCard).read(address(this), storageKey);
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
        require(poolLaunchPad != address(0), "MasterControl: poolLaunchPad not set");
        require(sender == poolLaunchPad, "MasterControl: only PoolLaunchPad");
        bytes32 hookPath = getPoolHookPath(key);
        uint256 poolId = getPoolId(key);
        // Forward full typed parameters to hook commands: sender, key, sqrtPriceX96
        runHooks_BeforeInitialize(poolId, hookPath, sender, key, sqrtPriceX96);
        console.log("sender MC _beforeInitialize", sender);
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
                                                                                                                                                // Call typed afterSwap runners; they return an int128 if applicable
        int128 updatedValue = runHooks_AfterSwap(poolId, hookPath, sender, key, params, delta, hookData);
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


    // --- Typed hook runners ---
    // Each runner passes structured ABI parameters (typed) to commands and appends the command's configured bytes as a trailing `bytes` param.
    // Commands are expected to implement a matching typed function signature with a trailing `bytes calldata extra` parameter.

    function runHooks_BeforeInitialize(uint256 poolId, bytes32 hookPath, address sender, PoolKey calldata key, uint160 sqrtPriceX96) internal {
        Command[] storage cmds = poolCommands[poolId][hookPath];
        for (uint i = 0; i < cmds.length; i++) {
            bool success;
            if (cmds[i].callType == CallType.Delegate) {
                (success, ) = cmds[i].target.delegatecall(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, tick)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, sqrtPriceX96, tick)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, current, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, delta, hookData)
                );
            } else {
                (success, ret) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, params, delta, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData)
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
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData)
                );
                require(success, "Delegatecall failed");
            } else {
                (success, ) = cmds[i].target.call(
                    abi.encodeWithSelector(cmds[i].selector, sender, key, a, b, hookData)
                );
                require(success, "Call failed");
            }
        }
    }

    // Batch run of Command[] for setup (owner-only utility)
    // Owner-only: execute target commands. For backward compatibility with legacy command
    // implementations that expect a trailing `bytes` parameter, commands will be invoked with a
    // single empty `bytes` parameter.
    function runCommandBatch(Command[] calldata commands) external {
        require(msg.sender == owner, "MasterControl: only owner");
        bytes memory emptyBytes = "";
        for (uint i = 0; i < commands.length; i++) {
            bool success;
            if (commands[i].callType == CallType.Delegate) {
                (success, ) = commands[i].target.delegatecall(
                    abi.encodeWithSelector(commands[i].selector, emptyBytes)
                );
                require(success, "Delegatecall failed");
            } else if (commands[i].callType == CallType.Call) {
                (success, ) = commands[i].target.call(
                    abi.encodeWithSelector(commands[i].selector, emptyBytes)
                );
                require(success, "Call failed");
            }
        }
    }
    
    // --- User Command Management ---

    

    function getCommands(uint256 poolId, bytes32 hookPath) external view returns (Command[] memory) {
        return poolCommands[poolId][hookPath];
    }

    /// @notice Replace the commands for a given pool and hookPath. Only callable by pool admin.
    /// This will fail if any existing locked/immutable command would be removed by the replacement.
    function setCommands(uint256 poolId, bytes32 hookPath, Command[] calldata cmds) external {
        require(address(accessControl) != address(0), "AccessControl not configured");
        require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");

        // Ensure we do not remove any command that is locked via per-command lock or originated from an immutable block
        Command[] storage existing = poolCommands[poolId][hookPath];
        for (uint i = 0; i < existing.length; i++) {
            // per-command explicit lock
            if (commandLockedForPool[poolId][hookPath][existing[i].target][existing[i].selector]) {
                bool found = false;
                for (uint j = 0; j < cmds.length; j++) {
                    if (cmds[j].target == existing[i].target && cmds[j].selector == existing[i].selector) {
                        found = true;
                        break;
                    }
                }
                require(found, "MasterControl: cannot remove locked command");
            }

            // provenance-based immutability
            uint256 origin = commandOriginBlock[poolId][hookPath][existing[i].target][existing[i].selector];
            if (origin != 0 && blockImmutable[origin]) {
                bool found2 = false;
                for (uint j = 0; j < cmds.length; j++) {
                    if (cmds[j].target == existing[i].target && cmds[j].selector == existing[i].selector) {
                        found2 = true;
                        break;
                    }
                }
                require(found2, "MasterControl: cannot remove command from immutable block");
            }
        }

        // Replace storage array atomically
        delete poolCommands[poolId][hookPath];
        for (uint k = 0; k < cmds.length; k++) {
            poolCommands[poolId][hookPath].push(cmds[k]);
            emit CommandsSet(poolId, hookPath, keccak256(abi.encode(cmds[k])));
        }
    }

    /// @notice Clear commands for a given pool/hookPath. Only callable by pool admin.
    /// Will revert if any existing command is locked for this pool (either per-command or by originating immutable block).
    function clearCommands(uint256 poolId, bytes32 hookPath) external {
        require(address(accessControl) != address(0), "AccessControl not configured");
        require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");

        Command[] storage existing = poolCommands[poolId][hookPath];
        for (uint i = 0; i < existing.length; i++) {
            require(!commandLockedForPool[poolId][hookPath][existing[i].target][existing[i].selector], "MasterControl: contains locked command");
            uint256 origin = commandOriginBlock[poolId][hookPath][existing[i].target][existing[i].selector];
            require(!(origin != 0 && blockImmutable[origin]), "MasterControl: contains immutable block command");
        }
        delete poolCommands[poolId][hookPath];
        emit CommandsSet(poolId, hookPath, keccak256(abi.encodePacked("cleared")));
    }

    // --- Command Block Management (ALL_REQUIRED semantics) ---

    /// @notice Owner creates a whitelisted block of commands.
    /// blockId is an arbitrary numeric id chosen by owner; each Command must include its hookPath.
    function createBlock(uint256 blockId, Command[] calldata commands, bool[] calldata immutableFlags, uint64 expiresAt) external {
        require(msg.sender == owner, "MasterControl: only owner");
        require(!blockEnabled[blockId], "MasterControl: block exists");
        require(commands.length > 0, "MasterControl: empty block");
        require(commands.length <= MAX_COMMANDS_PER_BLOCK, "MasterControl: too many commands");
        require(immutableFlags.length == commands.length, "MasterControl: immutableFlags length mismatch");
 
        // validate that each command's target is approved for its declared hookPath and push into storage
        for (uint i = 0; i < commands.length; i++) {
            bytes32 cmdHook = commands[i].hookPath;
            require(cmdHook != bytes32(0), "MasterControl: command hookPath zero");
            require(commandEnabled[cmdHook][commands[i].target], "MasterControl: command target not approved for hook");
            // push a copy into storage (preserve hookPath)
            blockCommands[blockId].push(
                Command({
                    hookPath: cmdHook,
                    target: commands[i].target,
                    selector: commands[i].selector,
                    callType: commands[i].callType
                })
            );
            // Use explicit immutableFlags array to mark immutability per-index
            if (immutableFlags[i]) {
                blockCommandImmutable[blockId][i] = true;
            }
        }
 
        blockEnabled[blockId] = true;
        blockExpiresAt[blockId] = expiresAt;
 
        // commandsHash uses targets/selectors/hookPath (no per-command data anymore)
        bytes32 commandsHash = keccak256(abi.encode(commands));
        // emit BlockCreated with a representative hookPath (hash of commands)
        bytes32 representativeHook = keccak256(abi.encode(commands));
        emit BlockCreated(blockId, representativeHook, commandsHash);
    }
/// @notice Owner may set block-level metadata after creating a block (immutable flag / conflict group).
function setBlockMetadata(uint256 blockId, bool immutableForPools, bytes32 conflictGroup) external {
    require(msg.sender == owner, "MasterControl: only owner");
    require(blockEnabled[blockId], "MasterControl: block not found");
    blockImmutable[blockId] = immutableForPools;
    blockConflictGroup[blockId] = conflictGroup;
}

    /// @notice Revoke a block so it cannot be applied in the future.
    function revokeBlock(uint256 blockId) external {
        require(msg.sender == owner, "MasterControl: only owner");
        require(blockEnabled[blockId], "MasterControl: block not found");
        blockEnabled[blockId] = false;
        delete blockCommands[blockId];
        blockExpiresAt[blockId] = 0;
        emit BlockRevoked(blockId);
    }

    /// @notice Apply whitelisted block(s) to a pool. Only pool admin can call.
    /// For ALL_REQUIRED semantics, applying a block will set the pool's commands for the hookPath
    /// to be the ordered list of commands from the block once all commands are validated.
    function applyBlocksToPool(uint256 poolId, uint256[] calldata blockIds) external {
        require(address(accessControl) != address(0), "AccessControl not configured");
        require(accessControl.getPoolAdmin(poolId) == msg.sender, "MasterControl: not pool admin");
        require(blockIds.length > 0, "MasterControl: no blocks");

        // Pre-validate all referenced blocks and commands before applying (fail early)
        uint256 totalCommands = 0;
        for (uint i = 0; i < blockIds.length; i++) {
            uint256 bId = blockIds[i];
            require(blockEnabled[bId], "MasterControl: block disabled");

            // ensure not expired
            uint64 exp = blockExpiresAt[bId];
            if (exp != 0) {
                require(exp >= uint64(block.timestamp), "MasterControl: block expired");
            }

            // conflict group validation: disallow applying a block whose conflictGroup is already active on the pool
            bytes32 cg = blockConflictGroup[bId];
            if (cg != bytes32(0)) {
                require(!poolConflictActive[poolId][cg], "MasterControl: conflict group active");
            }

            Command[] storage cmds = blockCommands[bId];
            require(cmds.length <= MAX_COMMANDS_PER_BLOCK, "MasterControl: block too large");

            for (uint j = 0; j < cmds.length; j++) {
                bytes32 cmdHook = cmds[j].hookPath;
                require(cmdHook != bytes32(0), "MasterControl: block command hookPath zero");
                require(commandEnabled[cmdHook][cmds[j].target], "MasterControl: block contains unapproved command target");
                totalCommands++;
                require(totalCommands <= MAX_APPLY_COMMANDS, "MasterControl: too many commands in apply");
            }
        }

        // All validation passed — now apply each block (append commands and emit events)
        for (uint i = 0; i < blockIds.length; i++) {
            uint256 bId = blockIds[i];
            Command[] storage cmds = blockCommands[bId];

            // Track a representative hookPath for the block (use first command's hookPath if present)
            bytes32 representativeHook = bytes32(0);
            if (cmds.length > 0) {
                representativeHook = cmds[0].hookPath;
            }

            // If the block has a conflictGroup, mark it as active for this pool
            bytes32 cg = blockConflictGroup[bId];
            if (cg != bytes32(0)) {
                poolConflictActive[poolId][cg] = true;
            }

            for (uint j = 0; j < cmds.length; j++) {
                bytes32 cmdHook = cmds[j].hookPath;

                // Append this command into the pool's command list for the command's hookPath
                poolCommands[poolId][cmdHook].push(cmds[j]);

                // Record provenance for this command (origin block id)
                commandOriginBlock[poolId][cmdHook][cmds[j].target][cmds[j].selector] = bId;

                // If this command was flagged immutable in the originating block, or the block is immutable,
                // mark it locked for this pool
                if (blockCommandImmutable[bId][j] || blockImmutable[bId]) {
                    commandLockedForPool[poolId][cmdHook][cmds[j].target][cmds[j].selector] = true;
                }

                bytes32 cmdHash = keccak256(abi.encode(cmds[j]));
                emit CommandsSet(poolId, cmdHook, cmdHash);
            }

            // Emit BlockApplied with a representative hookPath (tests expect the hookPath to be emitted)
            emit BlockApplied(bId, poolId, representativeHook);
        }
    }

    // --- Utility: Derive hook path from PoolKey (customize as needed) ---
    function getPoolHookPath(PoolKey calldata key) internal pure returns (bytes32) {
        // Use abi.encode (not abi.encodePacked) for struct types
        return keccak256(abi.encode(key));
    }

    // Utility: Derive poolId from PoolKey using canonical PoolId API
    function getPoolId(PoolKey calldata key) internal pure returns (uint256) {
        // copy calldata struct into memory so we can call the memory-based toId helper
        PoolKey memory mk = key;
        PoolId id = mk.toId();
        return uint256(PoolId.unwrap(id));
    }

    
}