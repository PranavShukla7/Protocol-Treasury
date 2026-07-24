// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

/// @title Treasury
/// @notice Simple ETH treasury that can receive deposits and allows the owner to withdraw.
contract Treasury {
    address public immutable owner;

    error NotOwner();
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 balanceAfter);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
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

    /// @notice Withdraw ETH from the treasury to the owner.
    /// @param amount The amount of ETH to withdraw.
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert InsufficientBalance();

        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(owner, amount, address(this).balance);
    }

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();

        emit Deposited(msg.sender, msg.value, address(this).balance);
    }
}
