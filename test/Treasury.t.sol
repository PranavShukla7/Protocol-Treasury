// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury private treasury;

    address private depositor = address(0xA11CE);
    address private ownerTwo = address(0xBEEF);
    address private nonOwner = address(0xB0B);
    address private recipient = address(0xCAFE);

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed recipient, uint256 amount);
    event TransactionQueued(uint256 indexed transactionIndex, uint256 executeAfter);
    event TransactionCancelled(uint256 indexed transactionIndex);

    receive() external payable {}

    function setUp() public {
        treasury = new Treasury();
        treasury.addOwner(ownerTwo);

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
        (
            address storedRecipient,
            uint256 storedAmount,
            bool executed,
            bool cancelled,
            uint256 confirmations,
            uint256 executeAfter,
            bool queued
        ) = treasury.transactions(transactionIndex);
        assertEq(storedRecipient, recipient);
        assertEq(storedAmount, amount);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(confirmations, 0);
        assertEq(executeAfter, 0);
        assertFalse(queued);
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
        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(0);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(executeAfter, 0);
        assertFalse(queued);
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

    function testCannotApproveTwice() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);

        treasury.approve(transactionIndex);

        vm.expectRevert(Treasury.AlreadyApproved.selector);
        treasury.approve(transactionIndex);

        assertTrue(treasury.approved(transactionIndex, address(this)));
        (,, bool executed, bool cancelled, uint256 confirmations,, bool queued) =
            treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(confirmations, 1);
        assertFalse(queued);
    }

    function testDifferentOwnersApprove() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);

        treasury.approve(transactionIndex);

        vm.prank(ownerTwo);
        treasury.approve(transactionIndex);

        assertTrue(treasury.approved(transactionIndex, address(this)));
        assertTrue(treasury.approved(transactionIndex, ownerTwo));
    }

    function testConfirmationCountCorrect() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);

        treasury.approve(transactionIndex);
        (,,,, uint256 confirmationsAfterFirstApproval,,) = treasury.transactions(transactionIndex);
        assertEq(confirmationsAfterFirstApproval, 1);

        vm.prank(ownerTwo);
        treasury.approve(transactionIndex);
        (,,,, uint256 confirmationsAfterSecondApproval,,) = treasury.transactions(transactionIndex);
        assertEq(confirmationsAfterSecondApproval, 2);
    }

    function testNonOwnerApproveTransactionFails() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);

        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.approve(transactionIndex);

        assertFalse(treasury.approved(transactionIndex, nonOwner));
        (,,,, uint256 confirmations,,) = treasury.transactions(transactionIndex);
        assertEq(confirmations, 0);
    }

    function testQueueSetsQueuedAndExecuteAfter() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);
        uint256 expectedExecuteAfter = block.timestamp + treasury.EXECUTION_DELAY();

        treasury.queue(transactionIndex);

        (,,,,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertTrue(queued);
        assertEq(executeAfter, expectedExecuteAfter);
    }

    function testQueueTransactionAliasSetsQueuedAndExecuteAfter() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);
        uint256 expectedExecuteAfter = block.timestamp + treasury.EXECUTION_DELAY();

        treasury.queueTransaction(transactionIndex);

        (,,,,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertTrue(queued);
        assertEq(executeAfter, expectedExecuteAfter);
    }

    function testQueueEmitsEvent() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);
        uint256 expectedExecuteAfter = block.timestamp + treasury.EXECUTION_DELAY();

        vm.expectEmit(true, false, false, true, address(treasury));
        emit TransactionQueued(transactionIndex, expectedExecuteAfter);

        treasury.queue(transactionIndex);
    }

    function testCannotQueueWithoutEnoughApprovals() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);
        treasury.approve(transactionIndex);

        vm.expectRevert(Treasury.InsufficientApprovals.selector);
        treasury.queue(transactionIndex);

        (,,,,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertEq(executeAfter, 0);
        assertFalse(queued);
    }

    function testCannotQueueTwice() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);

        treasury.queue(transactionIndex);

        vm.expectRevert(Treasury.AlreadyQueued.selector);
        treasury.queue(transactionIndex);
    }

    function testNonOwnerQueueFails() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);

        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.queue(transactionIndex);

        (,,,,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertEq(executeAfter, 0);
        assertFalse(queued);
    }

    function testCancelTransactionSetsCancelled() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);

        treasury.cancelTransaction(transactionIndex);

        (,, bool executed, bool cancelled,,,) = treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertTrue(cancelled);
    }

    function testCancelTransactionEmitsEvent() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit TransactionCancelled(transactionIndex);

        treasury.cancelTransaction(transactionIndex);
    }

    function testNonOwnerCancelTransactionFails() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);

        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.cancelTransaction(transactionIndex);

        (,,, bool cancelled,,,) = treasury.transactions(transactionIndex);
        assertFalse(cancelled);
    }

    function testCannotCancelTransactionTwice() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);

        treasury.cancelTransaction(transactionIndex);

        vm.expectRevert(Treasury.AlreadyCancelled.selector);
        treasury.cancelTransaction(transactionIndex);
    }

    function testExecuteSuccess() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.execute(transactionIndex);

        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertTrue(executed);
        assertFalse(cancelled);
        assertTrue(queued);
        assertLe(executeAfter, block.timestamp);
    }

    function testExecuteTwiceFails() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.execute(transactionIndex);

        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.execute(transactionIndex);
    }

    function testCannotCancelExecutedTransaction() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.execute(transactionIndex);

        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.cancelTransaction(transactionIndex);
    }

    function testInsufficientApprovalsExecuteFails() public {
        vm.prank(depositor);
        treasury.deposit{value: 2 ether}();

        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);
        treasury.approve(transactionIndex);

        vm.expectRevert(Treasury.InsufficientApprovals.selector);
        treasury.execute(transactionIndex);

        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(executeAfter, 0);
        assertFalse(queued);
    }

    function testExecuteBeforeQueueFails() public {
        vm.prank(depositor);
        treasury.deposit{value: 2 ether}();

        uint256 transactionIndex = _submitAndApprove(1 ether);

        vm.expectRevert(Treasury.TransactionNotQueued.selector);
        treasury.execute(transactionIndex);

        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(executeAfter, 0);
        assertFalse(queued);
    }

    function testExecuteBeforeExecuteAfterFails() public {
        vm.prank(depositor);
        treasury.deposit{value: 2 ether}();

        uint256 transactionIndex = _submitAndApprove(1 ether);
        treasury.queue(transactionIndex);

        vm.expectRevert(Treasury.ExecutionDelayNotElapsed.selector);
        treasury.execute(transactionIndex);

        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertFalse(cancelled);
        assertEq(executeAfter, block.timestamp + treasury.EXECUTION_DELAY());
        assertTrue(queued);
    }

    function testExecuteDecreasesTreasuryBalance() public {
        uint256 amount = 1 ether;
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(3 ether, amount);
        uint256 treasuryBalanceBefore = treasury.contractBalance();

        treasury.execute(transactionIndex);

        assertEq(treasury.contractBalance(), treasuryBalanceBefore - amount);
    }

    function testExecuteIncreasesRecipientBalance() public {
        uint256 amount = 1 ether;
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(3 ether, amount);
        uint256 recipientBalanceBefore = recipient.balance;

        treasury.execute(transactionIndex);

        assertEq(recipient.balance, recipientBalanceBefore + amount);
    }

    function _submitAndApprove(uint256 transactionAmount) private returns (uint256 transactionIndex) {
        transactionIndex = treasury.submitTransaction(recipient, transactionAmount);
        treasury.approve(transactionIndex);

        vm.prank(ownerTwo);
        treasury.approve(transactionIndex);
    }

    function _depositSubmitApproveQueueAndWait(uint256 depositAmount, uint256 transactionAmount)
        private
        returns (uint256 transactionIndex)
    {
        vm.prank(depositor);
        treasury.deposit{value: depositAmount}();

        transactionIndex = _submitAndApprove(transactionAmount);
        treasury.queue(transactionIndex);

        (,,,,, uint256 executeAfter,) = treasury.transactions(transactionIndex);
        vm.warp(executeAfter);
    }
}
