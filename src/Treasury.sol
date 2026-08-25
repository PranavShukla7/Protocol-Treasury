// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

/// @title Treasury
/// @notice Simple ETH treasury that can receive deposits and lets owners submit transactions.
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

    uint256 public constant EXECUTION_DELAY = 1 days;

    address[] public owners;
    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => bool)) public approved;
    Transaction[] public transactions;
    bool public paused;

    error NotOwner();
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

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event TransactionApproved(uint256 indexed transactionIndex, address indexed owner, uint256 confirmations);
    event TransactionQueued(uint256 indexed transactionIndex, uint256 executeAfter);
    event TransactionCancelled(uint256 indexed transactionIndex);
    event TransactionExecuted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    constructor() {
        owners.push(msg.sender);
        isOwner[msg.sender] = true;
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

    /// @notice Add a new treasury owner.
    /// @param owner The address to add as an owner.
    function addOwner(address owner) external onlyOwner whenNotPaused {
        if (isOwner[owner]) revert AlreadyOwner();

        owners.push(owner);
        isOwner[owner] = true;
    }

    /// @notice Pause treasury operations.
    function pause() external onlyOwner {
        if (paused) revert AlreadyPaused();

        paused = true;

        emit Paused(msg.sender);
    }

    /// @notice Resume treasury operations.
    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();

        paused = false;

        emit Unpaused(msg.sender);
    }

    /// @notice Submit a transaction request. Execution happens in a later flow.
    /// @param recipient The address intended to receive ETH.
    /// @param amount The amount of ETH requested for the transaction.
    function submitTransaction(address recipient, uint256 amount)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 transactionIndex)
    {
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
    function execute(uint256 transactionIndex) external onlyOwner whenNotPaused {
        Transaction storage transaction = transactions[transactionIndex];

        if (transaction.executed) revert AlreadyExecuted();
        if (transaction.cancelled) revert TransactionIsCancelled();
        if (transaction.confirmations < owners.length) revert InsufficientApprovals();
        if (!transaction.queued) revert TransactionNotQueued();
        if (block.timestamp < transaction.executeAfter) revert ExecutionDelayNotElapsed();

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
}
