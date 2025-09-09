# Bonded Hooks — Uniswap v4 Hook Management (UHI6 Hookathon)

Experimental project implementing owner-published, pool-applied hook "blocks" (bundles) for Uniswap v4.


Status

- In development for the UHI6 Hookathon.
- Not audited, may contain security issues.
- Not suitable for production. Use only on local testnets or sandboxes.

This repository implements an adaptive Uniswap V4 hook system that can be extended by "commands" composed and applied to pools. The core responsibilities and main contracts are summarized below to help new contributors get oriented quickly.

Core concepts
- MasterControl: hook dispatcher and command manager that routes Uniswap V4 hook events to ordered Command[] lists per pool and hookPath. See [`Bonded-hooks/src/MasterControl.sol:33`](Bonded-hooks/src/MasterControl.sol:33).
- Commands: small contracts (often executed via delegatecall) that implement hook behavior (e.g., mint points, forward fees). Example: [`Bonded-hooks/src/PointsCommand.sol:25`](Bonded-hooks/src/PointsCommand.sol:25).
- Blocks & provenance: commands are packaged into whitelisted blocks (ALL_REQUIRED semantics) that can be applied to pools; MasterControl records provenance and immutability. See block lifecycle in [`Bonded-hooks/src/MasterControl.sol:709`](Bonded-hooks/src/MasterControl.sol:709).

Fee, bonding, and rewards
- Bonding: bond principal + rewards-per-share accounting used to fund hooks and reward bonders. See [`Bonded-hooks/src/Bonding.sol:15`](Bonded-hooks/src/Bonding.sol:15).
- ShareSplitter: splits incoming ETH according to Settings (default or per-sender) and forwards to recipients (DegenPool, GasBank, FeeCollector). See [`Bonded-hooks/src/ShareSplitter.sol:7`](Bonded-hooks/src/ShareSplitter.sol:7).
- GasBank / GasRebateManager: GasBank holds ETH for gas rebates; GasRebateManager is credited by an off-chain AVS operator per epoch and users withdraw rebates. See [`Bonded-hooks/src/GasBank.sol:8`](Bonded-hooks/src/GasBank.sol:8) and [`Bonded-hooks/src/GasRebateManager.sol:19`](Bonded-hooks/src/GasRebateManager.sol:19).
- FeeCollector: simple placeholder vault for platform fees. See [`Bonded-hooks/src/FeeCollector.sol:6`](Bonded-hooks/src/FeeCollector.sol:6).

Pool lifecycle and auxiliary systems
- PoolLaunchPad: token + pool creation helper; registers pool admin in AccessControl on initialize. See [`Bonded-hooks/src/PoolLaunchPad.sol:26`](Bonded-hooks/src/PoolLaunchPad.sol:26).
- DegenPool: points-based reward pool that receives a portion of hook fees, mints/settles points, and pays rewards. See [`Bonded-hooks/src/DegenPool.sol:15`](Bonded-hooks/src/DegenPool.sol:15).
- MemoryCard: per-user key/value storage plus ROM-style storage (deploys a small contract with payload). Commands read/write per-pool config to MemoryCard. See [`Bonded-hooks/src/MemoryCard.sol:12`](Bonded-hooks/src/MemoryCard.sol:12).
- AccessControl: central role and per-pool admin registry used across contracts. See [`Bonded-hooks/src/AccessControl.sol:9`](Bonded-hooks/src/AccessControl.sol:9).

Other utilities
- BidManager: simple on-chain bid registry used by the AVS workflow for epoch bidding. See [`Bonded-hooks/src/BidManager.sol:6`](Bonded-hooks/src/BidManager.sol:6).
- Create2Factory: deterministic deploy helper used by scripts/tests. See [`Bonded-hooks/src/Create2Factory.sol:6`](Bonded-hooks/src/Create2Factory.sol:6).
- IMemoryCard: interface consumed by commands when interacting with MemoryCard. See [`Bonded-hooks/src/IMemoryCard.sol:6`](Bonded-hooks/src/IMemoryCard.sol:6).

Files referenced
- MasterControl: [`Bonded-hooks/src/MasterControl.sol:33`](Bonded-hooks/src/MasterControl.sol:33)
- Bonding: [`Bonded-hooks/src/Bonding.sol:15`](Bonded-hooks/src/Bonding.sol:15)
- MemoryCard: [`Bonded-hooks/src/MemoryCard.sol:12`](Bonded-hooks/src/MemoryCard.sol:12)
- ShareSplitter: [`Bonded-hooks/src/ShareSplitter.sol:7`](Bonded-hooks/src/ShareSplitter.sol:7)
- GasBank: [`Bonded-hooks/src/GasBank.sol:8`](Bonded-hooks/src/GasBank.sol:8)
- GasRebateManager: [`Bonded-hooks/src/GasRebateManager.sol:19`](Bonded-hooks/src/GasRebateManager.sol:19)
- DegenPool: [`Bonded-hooks/src/DegenPool.sol:15`](Bonded-hooks/src/DegenPool.sol:15)
- PointsCommand: [`Bonded-hooks/src/PointsCommand.sol:25`](Bonded-hooks/src/PointsCommand.sol:25)

1) Fee flow (per-swap)

Description
- A swap that triggers hooks flows through `MasterControl` which dispatches configured commands. See dispatcher in [`Bonded-hooks/src/MasterControl.sol:244`](Bonded-hooks/src/MasterControl.sol:244).
- Commands may collect a fixed command fee (`COMMAND_FEE_BIPS`) and forward ETH to `ShareSplitter` or `Bonding`. Example command: [`Bonded-hooks/src/PointsCommand.sol:40`](Bonded-hooks/src/PointsCommand.sol:40).

```mermaid
sequenceDiagram
    Trader->>Pool: swap()
    Pool->>MasterControl: afterSwap hook
    MasterControl->>Command: delegatecall afterSwap
    Command->>MasterControl: mintPoints (delegate)
    Command->>ShareSplitter: forward fee ETH
    ShareSplitter->>DegenPool: portion to degen pool
    ShareSplitter->>GasBank: portion to gas bank
    ShareSplitter->>FeeCollector: remainder to fee collector
    DegenPool->>DegenPool: update cumulativeRewardPerPoint
```

Notes
- `MasterControl` runs commands in order and supports delegatecall/call variants. See run loop at [`Bonded-hooks/src/MasterControl.sol:394`](Bonded-hooks/src/MasterControl.sol:394).
- Commands expose a `COMMAND_FEE_BIPS` getter which `MasterControl` reads when applying blocks to aggregate fees per-target. See `_getCommandFeeBips` at [`Bonded-hooks/src/MasterControl.sol:906`](Bonded-hooks/src/MasterControl.sol:906).

2) Rebate flow (AVS epoch processing)

Description
- An off-chain AVS operator computes per-user gas rebates for an epoch and pushes them on-chain.
- `GasRebateManager.pushGasPoints` pulls ETH from `GasBank` then credits users. See [`Bonded-hooks/src/GasRebateManager.sol:82`](Bonded-hooks/src/GasRebateManager.sol:82).

```mermaid
sequenceDiagram
    Operator->>AVS: compute epoch credits
    AVS->>GasRebateManager: pushGasPoints(epoch, users, amounts)
    GasRebateManager->>GasBank: withdrawTo(this, totalAmount)
    GasBank->>GasRebateManager: transfer ETH
    GasRebateManager->>Users: credit rebateBalance
    User->>GasRebateManager: withdrawGasRebate()
```

Notes
- `GasBank` only allows its configured `rebateManager` to call `withdrawTo`. See [`Bonded-hooks/src/GasBank.sol:55`](Bonded-hooks/src/GasBank.sol:55).
- `GasRebateManager` stores `rebateBalance` per-user; users call `withdrawGasRebate` to receive ETH.

3) applyBlocksToPool lifecycle (MasterControl block application)

Description
- Owner/ROLE_MASTER creates whitelisted blocks of commands (ALL_REQUIRED semantics). Blocks may be flagged immutable or assigned a conflict group.
- Pool admin calls `applyBlocksToPool` to append block commands to their pool. Provenance and immutability are recorded so that later `setCommands`/`clearCommands` cannot remove locked commands.

```mermaid
sequenceDiagram
    ROLE_MASTER->>MasterControl: createBlock(blockId, commands)
    MasterControl->>events: emit BlockCreated
    PoolAdmin->>MasterControl: applyBlocksToPool(poolId, [blockId])
    MasterControl->>poolCommands: append commands for pool/hookPath
    MasterControl->>storage: record commandOriginBlock and commandLockedForPool if immutable
    MasterControl->>events: emit BlockApplied
```

Notes
- `applyBlocksToPool` validates block enabled status, expiry, conflict groups, and approved targets before applying. See validation starting at [`Bonded-hooks/src/MasterControl.sol:773`](Bonded-hooks/src/MasterControl.sol:773).

4) MemoryCard ROM lifecycle (saveToRom / readFromRom)

Description
- `MemoryCard` provides caller-scoped key/value storage and a ROM path where arbitrary data is saved into a tiny deployed contract (creation code + payload). This can store immutable blobs retrievable via `readFromRom`.

```mermaid
sequenceDiagram
    Command->>MemoryCard: write(key, value)
    MemoryCard->>storage: store[msg.sender][key] = value
    Command->>MemoryCard: saveToRom(value)
    MemoryCard->>EVM: create(contract with value in runtime code)
    MemoryCard->>store2: store2[msg.sender] = deployedAddress
    AnyReader->>MemoryCard: readFromRom(user)
    MemoryCard->>EVM: extcodecopy deployedAddress -> return code
```

Notes
- `saveToRom` deploys a minimal contract with the payload as runtime bytecode and stores the deployed address in `store2` keyed by sender. See implementation at [`Bonded-hooks/src/MemoryCard.sol:47`](Bonded-hooks/src/MemoryCard.sol:47).

Appendix and further reading
- For command examples see [`Bonded-hooks/src/PointsCommand.sol:25`](Bonded-hooks/src/PointsCommand.sol:25).
- For bonding and rewards-per-share distribution see [`Bonded-hooks/src/Bonding.sol:15`](Bonded-hooks/src/Bonding.sol:15).
- For pool lifecycle and admin registration see [`Bonded-hooks/src/PoolLaunchPad.sol:26`](Bonded-hooks/src/PoolLaunchPad.sol:26).

## High-level architecture
- Master dispatcher: [`Bonded-hooks/src/MasterControl.sol:33`] accepts Uniswap V4 hook callbacks and dispatches them to ordered Command lists per pool.
- Per-pool storage: configuration and state for commands and controllers lives in [`Bonded-hooks/src/MemoryCard.sol:12`].
- Bonding and rewards: fee bonds and rewards accounting implemented in [`Bonded-hooks/src/Bonding.sol:15`].
- Fee splitting and payout infrastructure: [`Bonded-hooks/src/ShareSplitter.sol:7`], [`Bonded-hooks/src/GasBank.sol:8`], [`Bonded-hooks/src/GasRebateManager.sol:19`], [`Bonded-hooks/src/FeeCollector.sol:6`].
- Auxiliary: pool creation via [`Bonded-hooks/src/PoolLaunchPad.sol:26`], points pool [`Bonded-hooks/src/DegenPool.sol:15`].

## Components

### MasterControl
Responsibilities:
- Receives Uniswap V4 hook callbacks and translates `PoolKey` into internal hookPath and poolId.
- Runs ordered `Command[]` for a given pool/hook and supports both delegatecall and call execution modes.
- Manages approved command targets and whitelisted command blocks (createBlock, applyBlocksToPool, revokeBlock).
- Tracks provenance and immutability for commands applied to pools.
See implementation at [`Bonded-hooks/src/MasterControl.sol:33`].

### Command model
- Commands are small contracts exposing typed hook entrypoints (for example `afterSwap`) and may run via delegatecall.
- Commands should expose a `COMMAND_FEE_BIPS()` getter if they charge per-call fees; MasterControl reads this value when blocks are applied.
- Commands use `MemoryCard` for persistent per-pool or per-user configuration.
Example command: [`Bonded-hooks/src/PointsCommand.sol:25`].

### MemoryCard
- Provides caller-scoped key/value storage (`write`, `read`, `clear`) and ROM-style storage via `saveToRom`/`readFromRom`.
- ROM storage deploys a minimal contract whose runtime bytecode contains the payload. The deployed address is stored per-sender.
See [`Bonded-hooks/src/MemoryCard.sol:12`].

### Bonding and Fee Routing
- Bonding contract ([`Bonded-hooks/src/Bonding.sol:15`]) holds bonded principal and calculates per-target rewards via `rewardsPerShare`.
- Fee routing is expected to forward command fees into Bonding and/or ShareSplitter depending on command logic.
- ShareSplitter ([`Bonded-hooks/src/ShareSplitter.sol:7`]) consumes ETH and forwards portions to recipients defined in `Settings`.
- GasBank ([`Bonded-hooks/src/GasBank.sol:8`]) holds ETH for gas rebates; GasRebateManager ([`Bonded-hooks/src/GasRebateManager.sol:19`]) pulls funds per epoch to credit users.

### DegenPool and Prizes
- DegenPool ([`Bonded-hooks/src/DegenPool.sol:15`]) accumulates a portion of hook fees as points rewards. Points are minted by commands or the AVS operator and are used for reward distribution and games.
- PrizeBox and Shaker (not fully covered here) coordinate timed bonus games that draw from split fees and DegenPool credits.

## Key data flows
- Fee flow per swap: trader -> pool -> MasterControl -> command -> ShareSplitter/Bonding/GasBank. See `docs/flows.md` for diagrams.
- Rebate flow: AVS operator computes per-user rebates -> GasRebateManager.pushGasPoints -> GasBank.withdrawTo -> user balances -> withdrawGasRebate.
- Block apply lifecycle: ROLE_MASTER creates block(s) -> pool admin applies block to pool -> MasterControl validates and appends commands -> provenance recorded; commands may be locked/immutable.

## Extensibility points
- New commands: implement typed hook entrypoints, expose `commandMetadata()` and optional `COMMAND_FEE_BIPS()`.
- MemoryCard: use per-pool keys (keccak256 of key + poolId) to store configuration without expanding MasterControl storage.
- Additional AVS integrations: `GasRebateManager` and `BidManager` are designed to accept off-chain operator input; these can be extended to accept Merkle proofs or multisig operator sets.

## Security considerations
- Delegatecall usage: Many commands run via delegatecall into MasterControl context. Commands MUST be audited because they execute with MasterControl storage context.
- Immutable provenance: use block immutability and per-command locks to prevent pool admins from removing critical commands.
- Funds custody: GasBank and FeeCollector hold ETH; ensure admin keys and AccessControl are secured. GasBank allows only `rebateManager` to withdraw.
- Reentrancy: Bonding uses a simple nonReentrant guard. Commands and any external ERC20 transfers should use safe calls and checks.

## Testing Notes
- Tests present in `Bonded-hooks/test/` cover MasterControl blocks, Bonding, DegenPool, and GasRebateManager behaviors. Key tests to review: `masterControl.t.sol`, `Bonding.t.sol`, `DegenPool.t.sol`, `GasRebateManager.t.sol`.

Notes:
- All role definitions are declared as bytes32 public constant ROLE_* in the contract files.
- AccessControl registry is the on-chain central role store: [`Bonded-hooks/src/AccessControl.sol:9`]
- Many contracts implement a helper that prefers AccessControl.hasRole when configured and falls back to owner equality when AccessControl is zero address.

Roles

1) ROLE_MASTER
- Declared in: [`Bonded-hooks/src/MasterControl.sol:60`]
- Enforced by: MasterControl (checks via _isMasterAdmin) when configuring commands, blocks, memoryCard, poolLaunchPad, etc. See [`Bonded-hooks/src/MasterControl.sol:62`]
- Legacy owner fallback: yes (owner defined at [`Bonded-hooks/src/MasterControl.sol:57`], fallback in `_isMasterAdmin` at [`Bonded-hooks/src/MasterControl.sol:64`])
- Purpose: master-level contract operations (approve commands, create/revoke blocks, set memoryCard)

2) ROLE_SETTINGS_ADMIN
- Declared in: [`Bonded-hooks/src/Settings.sol:18`]
- Enforced by: Settings via `_isSettingsAdmin` at [`Bonded-hooks/src/Settings.sol:129`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/Settings.sol:16`])
- Purpose: manage default/custom share splits used by ShareSplitter

3) ROLE_FEE_COLLECTOR_ADMIN
- Declared in: [`Bonded-hooks/src/FeeCollector.sol:15`]
- Enforced by: FeeCollector methods like `setSettings` and `ownerWithdraw` via `_isAdmin` at [`Bonded-hooks/src/FeeCollector.sol:41`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/FeeCollector.sol:13`])
- Purpose: manage FeeCollector config and withdrawals

4) ROLE_GAS_BANK_ADMIN
- Declared in: [`Bonded-hooks/src/GasBank.sol:12`]
- Enforced by: GasBank admin methods (`setRebateManager`, `setShareSplitter`, `ownerWithdraw`) via `_isGasBankAdmin` at [`Bonded-hooks/src/GasBank.sol:72`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/GasBank.sol:10`])
- Purpose: manage vault settings and recovery

5) ROLE_GAS_REBATE_ADMIN
- Declared in: [`Bonded-hooks/src/GasRebateManager.sol:23`]
- Enforced by: GasRebateManager admin methods (`setGasBank`, `setOperator`, `ownerWithdraw`) via `_isAdmin` at [`Bonded-hooks/src/GasRebateManager.sol:139`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/GasRebateManager.sol:21`])
- Purpose: configure gas rebate contract, operators, and perform emergency withdraws

6) ROLE_SHARE_ADMIN
- Declared in: [`Bonded-hooks/src/ShareSplitter.sol:17`]
- Enforced by: ShareSplitter `setSettings` via `_isShareAdmin` at [`Bonded-hooks/src/ShareSplitter.sol:75`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/ShareSplitter.sol:15`])
- Purpose: change Settings reference used to derive share splits

7) ROLE_DEGEN_ADMIN
- Declared in: [`Bonded-hooks/src/DegenPool.sol:21`]
- Enforced by: DegenPool admin methods (`setSettlementRole`, `setShareSplitter`, `ownerWithdraw`) via `_isDegenAdmin` at [`Bonded-hooks/src/DegenPool.sol:207`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/DegenPool.sol:18`])
- Purpose: manage points pool operators and emergency withdrawals

8) ROLE_BONDING_ADMIN / ROLE_BONDING_PUBLISHER / ROLE_BONDING_WITHDRAWER
- Declared in: [`Bonded-hooks/src/Bonding.sol:24`]
- Enforced by: Bonding admin checks (owner fallback via `_isBondingAdmin` at [`Bonded-hooks/src/Bonding.sol:277`]) and role checks for publishers/withdrawers in modifiers `onlyPublisher`/`onlyWithdrawer` (lines [`Bonded-hooks/src/Bonding.sol:76`], [`Bonded-hooks/src/Bonding.sol:85`])
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/Bonding.sol:19`])
- Purpose: control which actors may publish fees, withdraw bonded principal, and administer the Bonding contract

9) ROLE_BID_MANAGER_ADMIN
- Declared in: [`Bonded-hooks/src/BidManager.sol:12`]
- Enforced by: BidManager admin paths (`setSettlementRole`, `ownerRecoverBid`, `ownerWithdraw`) via `_isAdmin` at [`Bonded-hooks/src/BidManager.sol:139`]
- Legacy owner fallback: yes (owner at [`Bonded-hooks/src/BidManager.sol:10`])
- Purpose: configure bid settlement operators and recover funds

AccessControl notes
- Central role storage is implemented in: [`Bonded-hooks/src/AccessControl.sol:9`]
- Roles are stored with mapping(bytes32 => mapping(address => bool)) (see [`Bonded-hooks/src/AccessControl.sol:18`]) and can be granted/revoked by the `owner` of AccessControl via `grantRole`/`revokeRole`.
- Per-pool admins are stored via `poolAdmin` mapping and manipulated by [`Bonded-hooks/src/AccessControl.sol:40`]
