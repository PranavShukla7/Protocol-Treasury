// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury private treasury;

    address private depositor = address(0xA11CE);
    address private nonOwner = address(0xB0B);
    address private recipient = address(0xCAFE);

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);

    receive() external payable {}

    function setUp() public {
        treasury = new Treasury();

        vm.deal(depositor, 10 ether);
        vm.deal(nonOwner, 10 ether);
    }

    function testDepositWorks() public {
        uint256 amount = 1 ether;

        vm.prank(depositor);
        treasury.deposit{value: amount}();

        assertEq(address(treasury).balance, amount);
        assertEq(treasury.contractBalance(), amount);
    }

    function testDeployerIsOwner() public view {
        assertEq(treasury.owners(0), address(this));
        assertTrue(treasury.isOwner(address(this)));
    }

    function testSubmitTransactionStoresTransaction() public {
        uint256 amount = 0.75 ether;

        uint256 transactionIndex = treasury.submitTransaction(recipient, amount);

        assertEq(transactionIndex, 0);
        (address storedRecipient, uint256 storedAmount, bool executed, uint256 confirmations) =
            treasury.transactions(transactionIndex);
        assertEq(storedRecipient, recipient);
        assertEq(storedAmount, amount);
        assertFalse(executed);
        assertEq(confirmations, 0);
    }

    function testSubmitTransactionIndexIncrements() public {
        uint256 firstIndex = treasury.submitTransaction(recipient, 1 ether);
        uint256 secondIndex = treasury.submitTransaction(address(0xD00D), 2 ether);

        assertEq(firstIndex, 0);
        assertEq(secondIndex, 1);
    }

    function testSubmitTransactionDoesNotExecute() public {
        vm.prank(depositor);
        treasury.deposit{value: 3 ether}();

        uint256 recipientBalanceBefore = recipient.balance;
        treasury.submitTransaction(recipient, 1 ether);

        assertEq(recipient.balance, recipientBalanceBefore);
        assertEq(treasury.contractBalance(), 3 ether);
        (,, bool executed,) = treasury.transactions(0);
        assertFalse(executed);
    }

    function testNonOwnerSubmitTransactionFails() public {
        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.submitTransaction(recipient, 0.5 ether);
    }

    function testDepositEmitsEvent() public {
        uint256 amount = 1.25 ether;

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Deposited(depositor, amount, amount);

        vm.prank(depositor);
        treasury.deposit{value: amount}();
    }

    function testSubmitTransactionEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit TransactionSubmitted(0, recipient, 0.5 ether);

        treasury.submitTransaction(recipient, 0.5 ether);
    }
}
