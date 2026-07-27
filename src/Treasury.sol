// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

/// @title Treasury
/// @notice Simple ETH treasury that can receive deposits and allows owners to withdraw.
contract Treasury {
    address[] public owners;
    mapping(address => bool) public isOwner;

    error NotOwner();
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 balanceAfter);

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

    /// @notice Withdraw ETH from the treasury to the calling owner.
    /// @param amount The amount of ETH to withdraw.
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert InsufficientBalance();

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, amount, address(this).balance);
    }

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();

        emit Deposited(msg.sender, msg.value, address(this).balance);
    }
}
