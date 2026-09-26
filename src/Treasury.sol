// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

/// @title Treasury
/// @notice Treasury that can receive ETH and lets owners submit transactions.
contract Treasury {
    struct Transaction {
        address recipient;
        uint256 amount;
        bool executed;
        bool cancelled;
        uint256 confirmations;
        uint256 executeAfter;
        bool queued;
    }

    enum Role {
        Guardian,
        Executor,
        Treasurer
    }

    struct RoleChange {
        address account;
        Role role;
        bool grant;
        bool executed;
        bool cancelled;
        uint256 confirmations;
        uint256 executeAfter;
        bool queued;
    }

    uint256 public constant EXECUTION_DELAY = 1 days;
    uint256 public constant ROLE_CHANGE_DELAY = 1 days;
    uint256 public constant DAILY_WITHDRAWAL_LIMIT = 100 ether;
    uint256 public constant EMERGENCY_WITHDRAWAL_LIMIT = 10 ether;

    address[] public owners;
    mapping(address => bool) public isOwner;
    mapping(address => bool) public isGuardian;
    mapping(address => bool) public isExecutor;
    mapping(address => bool) public isTreasurer;
    uint256 public guardianCount;
    uint256 public executorCount;
    uint256 public treasurerCount;
    mapping(uint256 => mapping(address => bool)) public approved;
    Transaction[] public transactions;
    RoleChange[] public roleChanges;
    mapping(uint256 => mapping(address => bool)) public roleChangeApproved;
    bool public paused;
    uint256 public spentToday;
    uint256 public lastReset;
    mapping(address => uint256) public emergencySpentToday;
    mapping(address => uint256) public emergencyLastReset;

    error NotOwner();
    error NotGuardian();
    error NotExecutor();
    error NotTreasurer();
    error ZeroAmount();
    error AlreadyOwner();
    error AlreadyApproved();
    error AlreadyExecuted();
    error AlreadyCancelled();
    error AlreadyQueued();
    error InsufficientApprovals();
    error TransactionNotQueued();
    error ExecutionDelayNotElapsed();
    error TransactionFailed();
    error TransactionIsCancelled();
    error AlreadyPaused();
    error NotPaused();
    error ContractPaused();
    error DailyWithdrawalLimitExceeded();
    error NotGuardianOrOwner();
    error TokenTransferFailed();
    error ZeroAddress();
    error OwnerNotFound();
    error LastOwner();
    error EmergencyDailyWithdrawalLimitExceeded();
    error LastRoleMember();

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event TransactionApproved(uint256 indexed transactionIndex, address indexed owner, uint256 confirmations);
    event TransactionQueued(uint256 indexed transactionIndex, uint256 executeAfter);
    event TransactionCancelled(uint256 indexed transactionIndex);
    event TransactionExecuted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event GuardianRoleGranted(address indexed account);
    event GuardianRoleRevoked(address indexed account);
    event ExecutorRoleGranted(address indexed account);
    event ExecutorRoleRevoked(address indexed account);
    event TreasurerRoleGranted(address indexed account);
    event TreasurerRoleRevoked(address indexed account);
    event RoleChangeProposed(uint256 indexed roleChangeIndex, address indexed account, Role role, bool grant);
    event RoleChangeApproved(uint256 indexed roleChangeIndex, address indexed owner, uint256 confirmations);
    event RoleChangeQueued(uint256 indexed roleChangeIndex, uint256 executeAfter);
    event RoleChangeCancelled(uint256 indexed roleChangeIndex);
    event RoleChangeExecuted(uint256 indexed roleChangeIndex, address indexed account, Role role, bool grant);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event EmergencyWithdrawal(address indexed caller, address indexed token, address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyGuardian() {
        if (!isGuardian[msg.sender]) revert NotGuardian();
        _;
    }

    modifier onlyExecutor() {
        if (!isExecutor[msg.sender]) revert NotExecutor();
        _;
    }

    modifier onlyTreasurer() {
        if (!isTreasurer[msg.sender]) revert NotTreasurer();
        _;
    }

    modifier onlyGuardianOrOwner() {
        if (!isGuardian[msg.sender] && !isOwner[msg.sender]) revert NotGuardianOrOwner();
        _;
    }

    constructor() {
        owners.push(msg.sender);
        isOwner[msg.sender] = true;
        isGuardian[msg.sender] = true;
        isExecutor[msg.sender] = true;
        isTreasurer[msg.sender] = true;
        guardianCount = 1;
        executorCount = 1;
        treasurerCount = 1;
        lastReset = block.timestamp;
    }

    receive() external payable whenNotPaused {
        _deposit();
    }

    /// @notice Deposit ETH into the treasury.
    function deposit() external payable whenNotPaused {
        _deposit();
    }

    /// @notice Returns the current ETH balance held by the treasury.
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Recover ETH or ERC20 tokens in an emergency.
    /// @dev Pass address(0) as token to withdraw ETH. This remains available while paused.
    /// @param token The ERC20 token address, or address(0) for ETH.
    /// @param recipient The address receiving the recovered funds.
    /// @param amount The amount to recover.
    function emergencyWithdraw(address token, address payable recipient, uint256 amount) external onlyGuardianOrOwner {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 reset = emergencyLastReset[token];
        /// forge-lint: disable-next-line(block-timestamp)
        if (reset == 0 || block.timestamp >= reset + 1 days) {
            emergencySpentToday[token] = 0;
            emergencyLastReset[token] = block.timestamp;
        }

        if (emergencySpentToday[token] + amount > EMERGENCY_WITHDRAWAL_LIMIT) {
            revert EmergencyDailyWithdrawalLimitExceeded();
        }

        emergencySpentToday[token] += amount;

        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert TransactionFailed();
        } else {
            _safeTransfer(token, recipient, amount);
        }

        emit EmergencyWithdrawal(msg.sender, token, recipient, amount);
    }

    /// @notice Add a new treasury owner.
    /// @param owner The address to add as an owner.
    function addOwner(address owner) external onlyOwner whenNotPaused {
        if (owner == address(0)) revert ZeroAddress();
        if (isOwner[owner]) revert AlreadyOwner();

        owners.push(owner);
        isOwner[owner] = true;

        emit OwnerAdded(owner);
    }

    /// @notice Remove an existing treasury owner.
    function removeOwner(address owner) external onlyOwner whenNotPaused {
        if (!isOwner[owner]) revert OwnerNotFound();
        if (owners.length == 1) revert LastOwner();

        uint256 ownerIndex;
        while (owners[ownerIndex] != owner) {
            ownerIndex++;
        }

        owners[ownerIndex] = owners[owners.length - 1];
        owners.pop();
        isOwner[owner] = false;

        emit OwnerRemoved(owner);
    }

    /// @notice Pause treasury operations.
    function pause() external onlyGuardian {
        if (paused) revert AlreadyPaused();

        paused = true;

        emit Paused(msg.sender);
    }

    /// @notice Resume treasury operations.
    function unpause() external onlyGuardian {
        if (!paused) revert NotPaused();

        paused = false;

        emit Unpaused(msg.sender);
    }

    /// @notice Submit a transaction request. Execution happens in a later flow.
    /// @param recipient The address intended to receive ETH.
    /// @param amount The amount of ETH requested for the transaction.
    function submitTransaction(address recipient, uint256 amount)
        external
        onlyTreasurer
        whenNotPaused
        returns (uint256 transactionIndex)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        transactionIndex = transactions.length;
        transactions.push(
            Transaction({
                recipient: recipient,
                amount: amount,
                executed: false,
                cancelled: false,
                confirmations: 0,
                executeAfter: 0,
                queued: false
            })
        );

        emit TransactionSubmitted(transactionIndex, recipient, amount);
    }

    /// @notice Approve a submitted transaction request.
    /// @param transactionIndex The transaction request to approve.
    function approve(uint256 transactionIndex) external onlyOwner whenNotPaused {
        _approveTransaction(transactionIndex);
    }

    /// @notice Approve a submitted transaction request.
    /// @param transactionIndex The transaction request to approve.
    function approveTransaction(uint256 transactionIndex) external onlyOwner whenNotPaused {
        _approveTransaction(transactionIndex);
    }

    /// @notice Queue an approved transaction request for execution after the delay.
    /// @param transactionIndex The transaction request to queue.
    function queue(uint256 transactionIndex) external onlyOwner whenNotPaused {
        _queueTransaction(transactionIndex);
    }

    /// @notice Queue an approved transaction request for execution after the delay.
    /// @param transactionIndex The transaction request to queue.
    function queueTransaction(uint256 transactionIndex) external onlyOwner whenNotPaused {
        _queueTransaction(transactionIndex);
    }

    /// @notice Cancel a submitted transaction request before it executes.
    /// @param transactionIndex The transaction request to cancel.
    function cancelTransaction(uint256 transactionIndex) external onlyOwner whenNotPaused {
        Transaction storage transaction = transactions[transactionIndex];

        if (transaction.executed) revert AlreadyExecuted();
        if (transaction.cancelled) revert AlreadyCancelled();

        transaction.cancelled = true;

        emit TransactionCancelled(transactionIndex);
    }

    /// @notice Execute an approved transaction request.
    /// @param transactionIndex The transaction request to execute.
    function execute(uint256 transactionIndex) external onlyExecutor whenNotPaused {
        Transaction storage transaction = transactions[transactionIndex];

        if (transaction.executed) revert AlreadyExecuted();
        if (transaction.cancelled) revert TransactionIsCancelled();
        if (transaction.confirmations < owners.length) revert InsufficientApprovals();
        if (!transaction.queued) revert TransactionNotQueued();
        /// forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < transaction.executeAfter) revert ExecutionDelayNotElapsed();

        /// forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= lastReset + 1 days) {
            spentToday = 0;
            lastReset = block.timestamp;
        }

        if (spentToday + transaction.amount > DAILY_WITHDRAWAL_LIMIT) {
            revert DailyWithdrawalLimitExceeded();
        }

        spentToday += transaction.amount;

        transaction.executed = true;

        (bool success,) = transaction.recipient.call{value: transaction.amount}("");
        if (!success) revert TransactionFailed();

        emit TransactionExecuted(transactionIndex, transaction.recipient, transaction.amount);
    }

    function _approveTransaction(uint256 transactionIndex) internal {
        if (approved[transactionIndex][msg.sender]) revert AlreadyApproved();

        approved[transactionIndex][msg.sender] = true;
        transactions[transactionIndex].confirmations++;

        emit TransactionApproved(transactionIndex, msg.sender, transactions[transactionIndex].confirmations);
    }

    function _queueTransaction(uint256 transactionIndex) internal {
        Transaction storage transaction = transactions[transactionIndex];

        if (transaction.executed) revert AlreadyExecuted();
        if (transaction.queued) revert AlreadyQueued();
        if (transaction.confirmations < owners.length) revert InsufficientApprovals();

        uint256 executeAfter = block.timestamp + EXECUTION_DELAY;
        transaction.executeAfter = executeAfter;
        transaction.queued = true;

        emit TransactionQueued(transactionIndex, executeAfter);
    }

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, msg.value, address(this).balance);
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        if (token.code.length == 0) revert TokenTransferFailed();

        (bool success, bytes memory returnData) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount));

        if (!success || (returnData.length != 0 && (returnData.length < 32 || !abi.decode(returnData, (bool))))) {
            revert TokenTransferFailed();
        }
    }

    function proposeRoleChange(address account, Role role, bool grant)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 roleChangeIndex)
    {
        if (account == address(0)) revert ZeroAddress();

        roleChangeIndex = roleChanges.length;
        roleChanges.push(
            RoleChange({
                account: account,
                role: role,
                grant: grant,
                executed: false,
                cancelled: false,
                confirmations: 0,
                executeAfter: 0,
                queued: false
            })
        );

        emit RoleChangeProposed(roleChangeIndex, account, role, grant);
    }

    function approveRoleChange(uint256 roleChangeIndex) external onlyOwner whenNotPaused {
        RoleChange storage roleChange = roleChanges[roleChangeIndex];

        if (roleChange.executed) revert AlreadyExecuted();
        if (roleChange.cancelled) revert AlreadyCancelled();
        if (roleChange.queued) revert AlreadyQueued();
        if (roleChangeApproved[roleChangeIndex][msg.sender]) revert AlreadyApproved();

        roleChangeApproved[roleChangeIndex][msg.sender] = true;
        roleChange.confirmations++;

        emit RoleChangeApproved(roleChangeIndex, msg.sender, roleChange.confirmations);
    }

    function queueRoleChange(uint256 roleChangeIndex) external onlyOwner whenNotPaused {
        RoleChange storage roleChange = roleChanges[roleChangeIndex];

        if (roleChange.executed) revert AlreadyExecuted();
        if (roleChange.cancelled) revert AlreadyCancelled();
        if (roleChange.queued) revert AlreadyQueued();
        if (roleChange.confirmations < owners.length) revert InsufficientApprovals();

        uint256 executeAfter = block.timestamp + ROLE_CHANGE_DELAY;
        roleChange.executeAfter = executeAfter;
        roleChange.queued = true;

        emit RoleChangeQueued(roleChangeIndex, executeAfter);
    }

    function executeRoleChange(uint256 roleChangeIndex) external onlyOwner whenNotPaused {
        RoleChange storage roleChange = roleChanges[roleChangeIndex];

        if (roleChange.executed) revert AlreadyExecuted();
        if (roleChange.cancelled) revert TransactionIsCancelled();
        if (roleChange.confirmations < owners.length) revert InsufficientApprovals();
        if (!roleChange.queued) revert TransactionNotQueued();
        /// forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < roleChange.executeAfter) revert ExecutionDelayNotElapsed();

        roleChange.executed = true;
        _applyRoleChange(roleChange.account, roleChange.role, roleChange.grant);

        emit RoleChangeExecuted(roleChangeIndex, roleChange.account, roleChange.role, roleChange.grant);
    }

    function cancelRoleChange(uint256 roleChangeIndex) external onlyOwner whenNotPaused {
        RoleChange storage roleChange = roleChanges[roleChangeIndex];

        if (roleChange.executed) revert AlreadyExecuted();
        if (roleChange.cancelled) revert AlreadyCancelled();

        roleChange.cancelled = true;

        emit RoleChangeCancelled(roleChangeIndex);
    }

    function _applyRoleChange(address account, Role role, bool grant) internal {
        if (role == Role.Guardian) {
            if (isGuardian[account] == grant) return;
            if (!grant && guardianCount == 1) revert LastRoleMember();
            isGuardian[account] = grant;
            if (grant) guardianCount++;
            else guardianCount--;
            if (grant) emit GuardianRoleGranted(account);
            else emit GuardianRoleRevoked(account);
        } else if (role == Role.Executor) {
            if (isExecutor[account] == grant) return;
            if (!grant && executorCount == 1) revert LastRoleMember();
            isExecutor[account] = grant;
            if (grant) executorCount++;
            else executorCount--;
            if (grant) emit ExecutorRoleGranted(account);
            else emit ExecutorRoleRevoked(account);
        } else {
            if (isTreasurer[account] == grant) return;
            if (!grant && treasurerCount == 1) revert LastRoleMember();
            isTreasurer[account] = grant;
            if (grant) treasurerCount++;
            else treasurerCount--;
            if (grant) emit TreasurerRoleGranted(account);
            else emit TreasurerRoleRevoked(account);
        }
    }

    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }

    function getRoleChangeCount() external view returns (uint256) {
        return roleChanges.length;
    }
}
