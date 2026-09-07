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
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    receive() external payable {}

    function setUp() public {
        treasury = new Treasury();
        treasury.addOwner(ownerTwo);

        vm.deal(depositor, 10 ether);
        vm.deal(nonOwner, 10 ether);
    }

    function testFuzzDeposit(uint96 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, 100 ether);

        vm.deal(depositor, amount);
        vm.prank(depositor);
        treasury.deposit{value: amount}();

        assertEq(treasury.contractBalance(), amount);
    }

    function testDeployerIsOwner() public view {
        assertEq(treasury.owners(0), address(this));
        assertTrue(treasury.isOwner(address(this)));
    }

    function testStartsUnpaused() public view {
        assertFalse(treasury.paused());
    }

    function testPauseSetsPaused() public {
        treasury.pause();

        assertTrue(treasury.paused());
    }

    function testPauseEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit Paused(address(this));

        treasury.pause();
    }

    function testUnpauseSetsPausedFalse() public {
        treasury.pause();

        treasury.unpause();

        assertFalse(treasury.paused());
    }

    function testUnpauseEmitsEvent() public {
        treasury.pause();

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Unpaused(address(this));

        treasury.unpause();
    }

    function testNonOwnerPauseFails() public {
        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotGuardian.selector);
        treasury.pause();

        assertFalse(treasury.paused());
    }

    function testNonOwnerUnpauseFails() public {
        treasury.pause();

        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotGuardian.selector);
        treasury.unpause();

        assertTrue(treasury.paused());
    }

    function testCannotPauseTwice() public {
        treasury.pause();

        vm.expectRevert(Treasury.AlreadyPaused.selector);
        treasury.pause();
    }

    function testCannotUnpauseWhenNotPaused() public {
        vm.expectRevert(Treasury.NotPaused.selector);
        treasury.unpause();
    }

    function testUnpauseRestoresDeposits() public {
        treasury.pause();
        treasury.unpause();

        vm.prank(depositor);
        treasury.deposit{value: 1 ether}();

        assertEq(treasury.contractBalance(), 1 ether);
    }

    function testFuzzSubmitTransaction(address fuzzRecipient, uint96 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, type(uint96).max);

        uint256 index = treasury.submitTransaction(fuzzRecipient, amount);

        (
            address storedRecipient,
            uint256 storedAmount,
            bool executed,
            bool cancelled,
            uint256 confirmations,
            uint256 executeAfter,
            bool queued
        ) = treasury.transactions(index);

        assertEq(storedRecipient, fuzzRecipient);
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
        vm.expectRevert(Treasury.NotTreasurer.selector);
        treasury.submitTransaction(recipient, 0.5 ether);
    }

    function testGrantedTreasurerCanSubmitTransaction() public {
        treasury.grantTreasurerRole(nonOwner);

        vm.prank(nonOwner);
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);

        assertEq(transactionIndex, 0);
    }

    function testDepositEmitsEvent() public {
        uint256 amount = 1.25 ether;

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Deposited(depositor, amount, amount);

        vm.prank(depositor);
        treasury.deposit{value: amount}();
    }

    function testPausedDepositFails() public {
        treasury.pause();

        vm.prank(depositor);
        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.deposit{value: 1 ether}();

        assertEq(treasury.contractBalance(), 0);
    }

    function testPausedAddOwnerFails() public {
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.addOwner(address(0xD00D));

        assertFalse(treasury.isOwner(address(0xD00D)));
    }

    function testSubmitTransactionEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit TransactionSubmitted(0, recipient, 0.5 ether);

        treasury.submitTransaction(recipient, 0.5 ether);
    }

    function testPausedSubmitTransactionFails() public {
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
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

    function testPausedApproveFails() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 0.5 ether);
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.approve(transactionIndex);

        assertFalse(treasury.approved(transactionIndex, address(this)));
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

    function testPausedQueueFails() public {
        uint256 transactionIndex = _submitAndApprove(1 ether);
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.queue(transactionIndex);

        (,,,,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertEq(executeAfter, 0);
        assertFalse(queued);
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

    function testPausedCancelTransactionFails() public {
        uint256 transactionIndex = treasury.submitTransaction(recipient, 1 ether);
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.cancelTransaction(transactionIndex);

        (,,, bool cancelled,,,) = treasury.transactions(transactionIndex);
        assertFalse(cancelled);
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

    function testNonExecutorExecuteFails() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);
        treasury.revokeExecutorRole(address(this));

        vm.expectRevert(Treasury.NotExecutor.selector);
        treasury.execute(transactionIndex);
    }

    function testGrantedExecutorCanExecute() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.grantExecutorRole(nonOwner);
        treasury.revokeExecutorRole(address(this));

        vm.prank(nonOwner);
        treasury.execute(transactionIndex);

        (,, bool executed,,,,) = treasury.transactions(transactionIndex);
        assertTrue(executed);
    }

    function testExecuteTwiceFails() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.execute(transactionIndex);

        vm.expectRevert(Treasury.AlreadyExecuted.selector);
        treasury.execute(transactionIndex);
    }

    function testExecuteCancelledTransactionFails() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);

        treasury.cancelTransaction(transactionIndex);

        vm.expectRevert(Treasury.TransactionIsCancelled.selector);
        treasury.execute(transactionIndex);

        (,, bool executed, bool cancelled,, uint256 executeAfter, bool queued) = treasury.transactions(transactionIndex);
        assertFalse(executed);
        assertTrue(cancelled);
        assertTrue(queued);
        assertLe(executeAfter, block.timestamp);
    }

    function testPausedExecuteFails() public {
        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(2 ether, 1 ether);
        treasury.pause();

        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.execute(transactionIndex);

        (,, bool executed,,,,) = treasury.transactions(transactionIndex);
        assertFalse(executed);
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

    function testFuzzExecuteAccounting(uint96 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, treasury.DAILY_WITHDRAWAL_LIMIT());

        uint256 transactionIndex = _depositSubmitApproveQueueAndWait(amount + 1 ether, amount);

        uint256 treasuryBefore = treasury.contractBalance();
        uint256 recipientBefore = recipient.balance;

        treasury.execute(transactionIndex);

        assertEq(treasury.contractBalance(), treasuryBefore - amount);
        assertEq(recipient.balance, recipientBefore + amount);
        assertEq(treasury.spentToday(), amount);
    }

    function testFuzzDailyWithdrawalLimit(uint96 rawFirst, uint96 rawSecond) public {
        uint256 first = bound(rawFirst, 1, treasury.DAILY_WITHDRAWAL_LIMIT());
        uint256 second =
            bound(rawSecond, treasury.DAILY_WITHDRAWAL_LIMIT() - first + 1, treasury.DAILY_WITHDRAWAL_LIMIT());

        vm.deal(depositor, first + second);
        vm.prank(depositor);
        treasury.deposit{value: first + second}();

        uint256 firstTx = _submitAndApprove(first);
        uint256 secondTx = _submitAndApprove(second);

        treasury.queue(firstTx);
        treasury.queue(secondTx);

        (,,,,, uint256 executeAfter,) = treasury.transactions(firstTx);
        vm.warp(executeAfter);

        treasury.execute(firstTx);

        vm.expectRevert(Treasury.DailyWithdrawalLimitExceeded.selector);
        treasury.execute(secondTx);
    }

    function testExecuteAllowsWithdrawalAfterDailyReset() public {
        vm.deal(depositor, 250 ether);
        vm.prank(depositor);
        treasury.deposit{value: 200 ether}();

        uint256 txOne = _submitAndApprove(100 ether);
        uint256 txTwo = _submitAndApprove(1 ether);

        treasury.queue(txOne);
        treasury.queue(txTwo);

        (,,,,, uint256 executeAfter,) = treasury.transactions(txOne);
        vm.warp(executeAfter);

        treasury.execute(txOne);

        vm.expectRevert(Treasury.DailyWithdrawalLimitExceeded.selector);
        treasury.execute(txTwo);

        vm.warp(block.timestamp + 1 days);
        treasury.execute(txTwo);

        assertEq(treasury.spentToday(), 1 ether);
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
