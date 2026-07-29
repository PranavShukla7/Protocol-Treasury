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
    Transaction[] public transactions;

    error NotOwner();
    error ZeroAmount();

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);

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

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();

        emit Deposited(msg.sender, msg.value, address(this).balance);
    }
}
