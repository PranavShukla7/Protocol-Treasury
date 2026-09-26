# Protocol Treasury

An owner-controlled treasury for ETH payments, with delayed execution, explicit operational roles, pause controls, and bounded emergency recovery.

The implementation is intentionally small. It does not attempt to be a general-purpose multisig, an upgradeable proxy, or an asset-management strategy. Its job is to make a narrow set of treasury actions visible, reviewable, and difficult to execute accidentally.

> **Status:** experimental. The contract has not been audited and should not hold production funds without an independent review.

## What It Does

- Accepts ETH through `deposit()` and the payable fallback.
- Lets treasurers submit ETH payment requests.
- Requires approval from every current owner before a payment can be queued.
- Enforces a one-day delay between queueing and execution.
- Separates submission, approval, queueing, and execution across treasurer, owner, and executor roles.
- Limits routine ETH execution to `100 ether` per accounting window.
- Allows guardians and owners to pause normal operations.
- Supports emergency ETH and ERC20 recovery while paused, with a separate per-token limit.
- Uses a safe low-level ERC20 transfer helper that supports both standard boolean-returning tokens and legacy no-return tokens.
- Governs role grants and revocations through unanimous owner approval and a one-day delay.

## Design At A Glance

| Control                 | Current policy                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------ |
| Normal payment approval | Every owner must approve                                                             |
| Payment delay           | `1 day`                                                                              |
| Routine ETH limit       | `100 ether` per accounting window                                                    |
| Role-change approval    | Every owner must approve                                                             |
| Role-change delay       | `1 day`                                                                              |
| Emergency limit         | `10 ether` units per token address per accounting window                             |
| Pause behavior          | Blocks deposits and normal treasury workflow; emergency withdrawal remains available |
| Upgradeability          | None                                                                                 |

The limits are compile-time constants. The emergency limit is denominated in the token's raw units; it is not decimal-aware for ERC20s.

## Payment Flow

```text
Treasurer                 Owners                 Executor
    |                        |                       |
    | submitTransaction      |                       |
    |----------------------->|                       |
    |                        | approveTransaction   |
    |                        |---------------------->|
    |                        | queueTransaction     |
    |                        |---------------------->|
    |                        |       one-day delay   |
    |                        |                       |
    |                        |                       | execute
    |                        |                       |------>
```

The recipient and amount are fixed when the transaction is submitted. A queued transaction cannot be edited. Any owner can cancel it before execution while the contract is not paused.

A failed ETH call, insufficient ETH balance, cancelled request, or exceeded daily limit causes execution to revert. Accounting is updated before the external call but rolls back with the transaction if the call fails.

## Roles

### Owners

Owners are the governance authority. They approve payments, queue and cancel transactions, manage the owner set, and approve delayed role changes. Owner addition and removal are currently immediate and can be performed by one existing owner. The final owner cannot be removed.

Because payments require unanimous approval, a lost or unavailable owner can stop normal payments. Keep owner keys independent and maintain a recovery procedure before funding the treasury.

### Treasurers

Treasurers can submit payment requests. They cannot approve, queue, or execute them.

### Executors

Executors can execute a fully approved and queued payment after its delay. They cannot change the recipient, amount, approvals, or queue timestamp.

### Guardians

Guardians can pause and unpause the normal workflow. Guardians and owners can perform emergency withdrawals, so guardians must be treated as trusted asset custodians rather than as a low-privilege pause-only role.

Role changes use this sequence:

1. `proposeRoleChange(account, role, grant)`
2. Every owner calls `approveRoleChange(roleChangeIndex)`
3. An owner calls `queueRoleChange(roleChangeIndex)`
4. Wait `ROLE_CHANGE_DELAY`
5. An owner calls `executeRoleChange(roleChangeIndex)`

Role changes can be cancelled before execution. The final guardian, executor, or treasurer cannot be removed.

## Emergency Recovery

`emergencyWithdraw(token, recipient, amount)` is available to an owner or guardian even while paused.

- Pass `address(0)` as `token` to recover ETH.
- Pass an ERC20 address to recover tokens.
- The recipient and amount must be nonzero.
- Each token address has its own emergency spending counter.
- A failed ETH transfer or ERC20 transfer reverts the entire operation and its accounting.

Emergency recovery intentionally bypasses normal payment approvals, the normal execution delay, and the routine ETH limit. This is an explicit trust decision. Monitor `EmergencyWithdrawal` and restrict guardian keys accordingly.

## Contract API

### Treasury operations

| Function                                      | Who can call it       | Purpose                                       |
| --------------------------------------------- | --------------------- | --------------------------------------------- |
| `deposit()` / payable fallback                | Anyone while unpaused | Deposit ETH                                   |
| `submitTransaction(recipient, amount)`        | Treasurer             | Create an ETH payment request                 |
| `approveTransaction(index)`                   | Owner                 | Approve a payment                             |
| `queueTransaction(index)`                     | Owner                 | Start the execution delay after all approvals |
| `execute(index)`                              | Executor              | Execute an eligible payment                   |
| `cancelTransaction(index)`                    | Owner while unpaused  | Cancel a pending payment                      |
| `pause()` / `unpause()`                       | Guardian              | Stop or resume normal operations              |
| `emergencyWithdraw(token, recipient, amount)` | Guardian or owner     | Recover ETH or ERC20s                         |

`approve()` and `queue()` are compatibility aliases for the corresponding transaction functions.

### Governance

| Function                   | Who can call it      | Purpose                       |
| -------------------------- | -------------------- | ----------------------------- |
| `addOwner(account)`        | Owner while unpaused | Add an owner immediately      |
| `removeOwner(account)`     | Owner while unpaused | Remove an existing owner      |
| `proposeRoleChange(...)`   | Owner while unpaused | Create a delayed role change  |
| `approveRoleChange(index)` | Owner while unpaused | Approve a role change         |
| `queueRoleChange(index)`   | Owner while unpaused | Start the role-change delay   |
| `executeRoleChange(index)` | Owner while unpaused | Apply an eligible role change |
| `cancelRoleChange(index)`  | Owner while unpaused | Cancel a pending role change  |

## Security Model

The important assumptions and incident procedures are documented in:

- [Threat model](docs/THREAT_MODEL.md)
- [Operations runbook](docs/OPERATIONS_RUNBOOK.md)

The most important limitation is key recovery: if every owner key is lost, this contract has no upgrade or administrative recovery path. Guardians may still recover assets if their keys remain, but they cannot restore owner governance.

## Development

This is a [Foundry](https://book.getfoundry.sh/) project.

```sh
forge build
forge test
forge fmt --check
```

Run the invariant suite separately when working on lifecycle or accounting behavior:

```sh
forge test --match-path test/TreasuryInvariant.t.sol
```

The tests include adversarial ETH recipients, insufficient balances, false-returning and no-return ERC20 mocks, role and owner changes, queued cancellation, exact limit boundaries, pause behavior, and stateful invariants.

## Repository Layout

```text
src/Treasury.sol                 Treasury contract
test/Treasury.t.sol              Unit, fuzz, and adversarial tests
test/TreasuryInvariant.t.sol     Stateful invariant tests
docs/THREAT_MODEL.md             Trust assumptions and threat analysis
docs/OPERATIONS_RUNBOOK.md       Payment, monitoring, and incident procedures
foundry.toml                     Foundry configuration
```

There is currently no deployment script in this repository. Deployment should be added only alongside a reviewed chain configuration, multisig setup, verification process, and post-deployment checklist.
