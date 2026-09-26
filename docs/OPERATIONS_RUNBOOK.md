# Treasury Operations Runbook

## Before funding

1. Build and test with `forge build` and `forge test`.
2. Verify the deployed bytecode and source against the reviewed commit.
3. Record the treasury address, chain, deployer, owners, guardians, executors, and treasurers.
4. Confirm that at least two independent owner keys are available when the treasury is intended to operate as a multisignature.
5. Fund only after the role roster and emergency policy have been reviewed.

## Normal payment flow

1. A treasurer calls `submitTransaction(recipient, amount)`.
2. Confirm the `TransactionSubmitted` event and independently verify the recipient and amount.
3. Every owner calls `approveTransaction(transactionIndex)`.
4. An owner queues the fully approved transaction with `queueTransaction(transactionIndex)`.
5. Wait at least `EXECUTION_DELAY`.
6. An executor calls `execute(transactionIndex)`.
7. Confirm `TransactionExecuted`, the recipient balance change, and the treasury balance change.

A queued transaction can be cancelled by any owner with `cancelTransaction(transactionIndex)` while the contract is not paused. If the contract is paused, unpause it through a guardian before cancelling or executing normal transactions.

## Monitoring

Watch these events continuously:

- `TransactionSubmitted`, `TransactionApproved`, `TransactionQueued`, `TransactionCancelled`, and `TransactionExecuted`
- `OwnerAdded` and `OwnerRemoved`
- `RoleChangeProposed`, `RoleChangeQueued`, `RoleChangeCancelled`, and `RoleChangeExecuted`
- `Paused`, `Unpaused`, and `EmergencyWithdrawal`

Alert on an unexpected recipient, amount, owner change, role change, emergency withdrawal, or pause state change. Keep an off-chain record of every transaction and role-change index; the contract stores arrays but does not provide a built-in operator dashboard.

## Incident response

### Unexpected payment queued

1. Verify the transaction index, recipient, amount, approvals, and `executeAfter` timestamp.
2. If unauthorized, have an owner call `cancelTransaction` before the delay expires.
3. Pause the contract if other activity must be stopped.
4. Investigate owner and treasurer keys before unpausing.

### Suspected key compromise

1. Pause immediately with a trusted guardian.
2. If at least one trusted owner remains, use the delayed, all-owner-approved role workflow to revoke compromised operational roles.
3. Remove the compromised owner using the owner-management function and add a replacement owner.
4. Review all queued transactions and cancel anything unexpected.
5. Unpause only after the owner and role roster is independently verified.

### Emergency asset recovery

1. Pause normal activity if appropriate.
2. Verify the token address, recipient, amount, and remaining emergency allowance.
3. Have a trusted guardian or owner call `emergencyWithdraw`.
4. Confirm the `EmergencyWithdrawal` event and recipient balance.
5. Remember that emergency withdrawals bypass normal payment approvals and remain available while paused.

### Lost keys

- If one or more owners remain, the remaining owners can remove lost owners and add replacements. Coordinate this before removing the final usable owner.
- If all owner keys are lost, this contract has no recovery or upgrade mechanism. There is no safe on-chain procedure to recover governance; this is a deployment-level loss scenario.
- Guardians can still perform emergency withdrawals if their keys remain, but guardians cannot restore owner governance.

## Parameter policy

- `DAILY_WITHDRAWAL_LIMIT` should cap expected routine outflows while limiting damage from a compromised approval set. Revisit it whenever treasury balances or payment volume change.
- `EMERGENCY_WITHDRAWAL_LIMIT` should be large enough for incident response but small enough to contain a compromised guardian during one accounting window.
- `EXECUTION_DELAY` gives owners and monitoring systems time to detect and cancel an unauthorized payment. Longer delays improve review time but slow operations.
- `ROLE_CHANGE_DELAY` should be at least as long as the expected incident-detection window because a role change can alter who controls funds.

Document any parameter change in governance records and update monitoring thresholds with it.
