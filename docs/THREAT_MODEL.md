# Treasury Threat Model

## Scope

This document covers the `Treasury` contract in `src/Treasury.sol`. The contract holds ETH and ERC20 tokens, accepts deposits, and executes owner-approved ETH payments after a one-day delay.

## Trust roles

- **Owners:** The owners are the governance authority. Every owner must approve a payment before it can be queued. Owners can add or remove owners, and owner changes are currently immediate and require one existing owner.
- **Guardians:** Guardians can pause and unpause the contract. Guardians and owners can perform emergency withdrawals. Emergency withdrawals remain available while paused and are limited per asset to `EMERGENCY_WITHDRAWAL_LIMIT` per rolling 24-hour accounting window.
- **Executors:** Executors submit the final execution transaction after the payment delay. They cannot change payment data.
- **Treasurers:** Treasurers can submit payment requests but cannot approve or execute them.

The deployer initially holds all four roles. Role grants and revocations require all owners, are queued, and become executable after `ROLE_CHANGE_DELAY`.

## Assets and controls

- Normal ETH payments require approval from every owner, a one-day execution delay, and stay within `DAILY_WITHDRAWAL_LIMIT` per 24-hour accounting window.
- Emergency withdrawals bypass normal payment approvals and remain available while paused. They require an owner or guardian, a nonzero recipient and amount, and the separate per-asset emergency limit.
- ERC20 transfers accept standard boolean-returning tokens and legacy no-return tokens. False returns, failed calls, and malformed return data revert.
- ETH recipient calls are treated as untrusted external calls. A reverting recipient causes the entire execution to revert.
- A zero-address payment recipient is rejected at submission time.

## Main threats

1. **Compromised owner:** A compromised owner can approve payments, change owners, and participate in role changes. Use independent keys or a multisig-controlled owner set.
2. **Compromised guardian:** A compromised guardian can emergency-withdraw assets up to the emergency limit every accounting window and can pause or unpause the contract. Guardians must be treated as asset custodians.
3. **Lost owner keys:** If at least one owner remains, the remaining owner set can remove lost owners and add replacement owners. If every owner key is lost, there is no recovery or upgrade path in this contract; funds and administration may become permanently inaccessible.
4. **Malicious tokens:** ERC20 behavior is untrusted. The safe transfer helper prevents false-return and failed-call accounting errors, but it cannot make a malicious token economically honest or protect against rebasing, fee-on-transfer, or callback behavior.
5. **Malicious recipients:** Recipient contracts can revert or consume gas. Failed ETH calls revert the payment and roll back accounting. Only send to reviewed recipients.
6. **Operational delay:** A queued payment remains executable after the delay unless an owner cancels it. Monitor `TransactionQueued` and cancel unexpected requests promptly.

## Security assumptions

- Owner keys are stored separately and are not controlled by the same operator.
- Guardians are trusted to move assets during incidents.
- Operators monitor emitted events and maintain a current owner and role roster.
- The configured limits and delays are appropriate for the chain, asset value, and response time.
- Deployment is from a verified source and the deployed bytecode is checked before funding.
