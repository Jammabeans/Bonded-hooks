# Bonded Hooks — Threat Model

## Scope
This model covers key protocol and operational risks for Solidity contracts and operator-assisted flows in the Bonded Hooks repository.

## 1) `delegatecall` / Command Approval Risk
### Risk
If command execution paths permit overly broad target/function control, misuse of delegated execution can escalate privilege or mutate critical state unexpectedly.

### Impact
- Unauthorized state changes
- Bypass of intended access boundaries
- Fund movement through unintended call surfaces

### Mitigations
- Strict allowlisting of targets/selectors
- Separation of execution authority vs configuration authority
- Defense-in-depth checks before any delegated execution
- Dedicated tests for malformed command payloads and privilege escalation attempts

## 2) Centralized Operator Risk
### Risk
A single off-chain operator process can become a trust bottleneck or availability bottleneck.

### Impact
- Censorship or delayed execution
- Operational downtime
- Key compromise leading to harmful actions

### Mitigations
- Multi-operator architecture and failover runbooks
- Time delays and on-chain circuit breakers for sensitive actions
- Key rotation, scoped keys, and monitoring/alerting

## 3) Bonding Principal Withdrawal / Admin Risk
### Risk
Administrative pathways for principal handling may be abused or misconfigured.

### Impact
- User fund loss or lockup
- Governance disputes due to opaque admin behavior

### Mitigations
- Clearly separated admin roles with least privilege
- Timelocked admin withdrawals where practical
- Event-rich accounting and transparent withdrawal constraints

## 4) Gas Rebate Abuse / Sybil Risk
### Risk
Rebate logic can be gamed by split identities, low-value spam, or circular activity.

### Impact
- Economic drain
- Distorted incentive distribution
- Protocol cost inflation

### Mitigations
- Eligibility constraints and anti-spam thresholds
- Per-epoch/per-identity caps
- Anomaly monitoring and tunable parameters governed by transparent policy

## 5) Emergency/Admin Withdrawal Risk
### Risk
Emergency controls are necessary but can be abused without robust governance boundaries.

### Impact
- Centralization concerns
- Unexpected freezes or fund movements

### Mitigations
- Narrow emergency scope with explicit limits
- Timelocks + multisig approvals for non-immediate actions
- Post-incident disclosure and replayable forensic logs

## 6) `tx.origin` Limitations
### Risk
Authorization logic relying on `tx.origin` is fragile and can break under account abstraction, relayers, or contract-based wallets.

### Impact
- Incorrect authorization decisions
- Reduced compatibility with modern wallet tooling

### Mitigations
- Prefer `msg.sender`-based role checks and explicit signer verification
- Avoid `tx.origin` for security-sensitive authorization
- Add tests for relayed/meta-tx and contract wallet call patterns
