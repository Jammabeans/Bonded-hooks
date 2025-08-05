# CommandContext: MasterControl, Commands, and MemoryCard

## System Overview

This system is designed for modular, stateless command execution in a smart contract environment, using a central `MasterControl` contract, a generic `MemoryCard` storage contract, and a set of "commands" (stateless logic modules) that are executed via `delegatecall`.

### Key Components

- **MasterControl**: The central contract that manages pools, hooks, and command execution. Inherits from ERC1155 for minting points. All command execution happens via `delegatecall` from MasterControl, so `msg.sender` is always MasterControl.
- **Command**: A stateless logic module (e.g., PointsCommand) that implements business logic (minting, config, etc.). Commands must not store state in their own contract; all state must be read/written via MemoryCard.
- **MemoryCard**: A generic key-value storage contract. All persistent state (config, user balances, etc.) is stored here. Commands interact with MemoryCard using `msg.sender` as the namespace (which is always MasterControl).

### Command Struct

Commands are executed via the following struct:

```solidity
struct Command {
    address target;      // The contract to call (e.g., PointsCommand)
    bytes4 selector;     // The function selector to call
    bytes data;          // ABI-encoded arguments
    CallType callType;   // Delegate or Call
}
```

### Command Execution

- Commands are executed by MasterControl using `delegatecall` (for stateless logic that needs to access MasterControl's storage/context) or `call` (for external calls).
- The main execution functions are:
  - `runHooksWithValue` / `runHooks`: Used for hook-based execution (e.g., afterSwap).
  - `runCommandBatch`: Used for batch setup/configuration (e.g., setting MemoryCard values).

## Command Format and Lifecycle

### Creating a Command

To create a command for a setter in PointsCommand:

```solidity
Command memory cmd = Command({
    target: address(pointsCommand),
    selector: pointsCommand.setBonusThreshold.selector,
    data: abi.encode(memoryCardAddr, 1000),
    callType: CallType.Delegate
});
```

### Sending Commands

To execute a batch of commands (e.g., for setup):

```solidity
Command[] memory cmds = new Command[](3);
// ...populate cmds as above...
masterControl.runCommandBatch(cmds);
```

### Example: Setting Config and Minting Points

1. **Set Config via Batch:**
   ```solidity
   Command[] memory setupCmds = new Command[](3);
   setupCmds[0] = Command({
       target: address(pointsCommand),
       selector: pointsCommand.setBonusThreshold.selector,
       data: abi.encode(memoryCardAddr, 0),
       callType: CallType.Delegate
   });
   // ...set other config...
   masterControl.runCommandBatch(setupCmds);
   ```

2. **Mint Points via Hook:**
   - MasterControl executes afterSwap, which runs a Command with:
     - target: PointsCommand
     - selector: afterSwap(bytes)
     - data: ABI-encoded context (see below)
     - callType: Delegate

## ABI Encoding and Context

- When calling a command, the data field should be ABI-encoded arguments for the target function.
- For afterSwap, the input is a packed context containing all trade data, and commands must extract relevant fields from the input bytes (see PointsCommand for extraction logic).

## Rules for Command Design

- **Stateless:** Commands must not store state in their own contract. All persistent state must be read/written via MemoryCard.
- **Delegatecall Context:** All logic that needs to access MasterControl's storage or msg.sender must use delegatecall.
- **Memory Access:** All reads/writes to MemoryCard must use msg.sender as the namespace (which will be MasterControl).
- **No Hardcoded Addresses:** All addresses (e.g., MemoryCard) must be passed in via context or extracted from input.
- **No Storage Writes:** Commands must not write to their own storage; only to MemoryCard or via MasterControl's context.
- **Programming Style:** Use pure functions where possible, avoid side effects, and always check input lengths and types when extracting from bytes.

## AI Context and Implementation Notes

- When implementing new commands, always ensure:
  - All state is accessed via MemoryCard using msg.sender.
  - All minting or ERC1155 logic is performed via delegatecall context (i.e., call _mint or similar in MasterControl).
  - All config/setup is done via batch commands using runCommandBatch.
  - All input extraction from bytes is done carefully, matching the ABI encoding used by MasterControl.
- When writing tests, use runCommandBatch to set up config, and ensure all hooks/commands are registered with the correct selectors and call types.

## Sample Command Registration

```solidity
Command memory mintCmd = Command({
    target: address(pointsCommand),
    selector: pointsCommand.afterSwap.selector,
    data: abi.encodePacked(context), // context is ABI-encoded trade data
    callType: CallType.Delegate
});
```

## Summary

This system enables highly modular, stateless, and upgradable smart contract logic by using delegatecall, a central controller, and a generic memory store. All commands must follow the stateless pattern and interact with MemoryCard and MasterControl as described above.
