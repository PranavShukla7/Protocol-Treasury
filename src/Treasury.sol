// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

/// @title Treasury
/// @notice Simple ETH treasury that can receive deposits and lets owners submit transactions.
contract Treasury {
    struct Transaction {
        address recipient;
        uint256 amount;
        bool executed;
        uint256 confirmations;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => bool)) public approved;
    Transaction[] public transactions;

    error NotOwner();
    error ZeroAmount();
    error AlreadyOwner();
    error AlreadyApproved();
    error AlreadyExecuted();
    error InsufficientApprovals();
    error TransactionFailed();

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event TransactionApproved(uint256 indexed transactionIndex, address indexed owner, uint256 confirmations);
    event TransactionExecuted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    constructor() {
        owners.push(msg.sender);
        isOwner[msg.sender] = true;
    }

    receive() external payable {
        _deposit();
    }

    /// @notice Deposit ETH into the treasury.
    function deposit() external payable {
        _deposit();
    }

    /// @notice Returns the current ETH balance held by the treasury.
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Add a new treasury owner.
    /// @param owner The address to add as an owner.
    function addOwner(address owner) external onlyOwner {
        if (isOwner[owner]) revert AlreadyOwner();

        owners.push(owner);
        isOwner[owner] = true;
    }

    /// @notice Submit a transaction request. Execution happens in a later flow.
    /// @param recipient The address intended to receive ETH.
    /// @param amount The amount of ETH requested for the transaction.
    function submitTransaction(address recipient, uint256 amount)
        external
        onlyOwner
        returns (uint256 transactionIndex)
    {
        if (amount == 0) revert ZeroAmount();

        transactionIndex = transactions.length;
        transactions.push(Transaction({recipient: recipient, amount: amount, executed: false, confirmations: 0}));

        emit TransactionSubmitted(transactionIndex, recipient, amount);
    }

    /// @notice Approve a submitted transaction request.
    /// @param transactionIndex The transaction request to approve.
    function approve(uint256 transactionIndex) external onlyOwner {
        _approveTransaction(transactionIndex);
    }

    /// @notice Approve a submitted transaction request.
    /// @param transactionIndex The transaction request to approve.
    function approveTransaction(uint256 transactionIndex) external onlyOwner {
        _approveTransaction(transactionIndex);
    }

    /// @notice Execute an approved transaction request.
    /// @param transactionIndex The transaction request to execute.
    function execute(uint256 transactionIndex) external onlyOwner {
        Transaction storage transaction = transactions[transactionIndex];

        if (transaction.executed) revert AlreadyExecuted();
        if (transaction.confirmations < owners.length) revert InsufficientApprovals();

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

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, msg.value, address(this).balance);
    }
}
