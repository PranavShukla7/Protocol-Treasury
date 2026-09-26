// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract Handler is Test {
    Treasury public treasury;
    address public ownerOne;
    address public ownerTwo;
    uint256 public expectedEthBalance;
    mapping(uint256 => uint256) public successfulExecutions;
    mapping(uint256 => address) public queuedRecipients;
    mapping(uint256 => uint256) public queuedAmounts;
    mapping(uint256 => uint256) public queuedExecuteAfter;
    mapping(uint256 => bool) public hasQueuedSnapshot;

    constructor(Treasury _treasury, address _ownerOne, address _ownerTwo) {
        treasury = _treasury;
        ownerOne = _ownerOne;
        ownerTwo = _ownerTwo;
        expectedEthBalance = address(_treasury).balance;
    }

    function _actor(bool useOwnerTwo) private view returns (address) {
        return useOwnerTwo ? ownerTwo : ownerOne;
    }

    function deposit(uint96 rawAmount, bool useOwnerTwo) public {
        uint256 amount = bound(rawAmount, 1, 100 ether);
        address actor = _actor(useOwnerTwo);

        vm.deal(actor, amount);
        vm.prank(actor);
        try treasury.deposit{value: amount}() {
            expectedEthBalance += amount;
        } catch {}
    }

    function submitTransaction(address recipient, uint96 rawAmount, bool useOwnerTwo) public {
        uint256 amount = bound(rawAmount, 1, 100 ether);

        vm.prank(_actor(useOwnerTwo));
        treasury.submitTransaction(recipient, amount);
    }

    function approveTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.approveTransaction(transactionIndex);
    }

    function queueTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        try treasury.queue(transactionIndex) {
            (address recipient, uint256 amount,,,, uint256 executeAfter,) = treasury.transactions(transactionIndex);
            queuedRecipients[transactionIndex] = recipient;
            queuedAmounts[transactionIndex] = amount;
            queuedExecuteAfter[transactionIndex] = executeAfter;
            hasQueuedSnapshot[transactionIndex] = true;
        } catch {}
    }

    function cancelTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.cancelTransaction(transactionIndex);
    }

    function executeTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        try treasury.execute(transactionIndex) {
            (, uint256 amount,,,,,) = treasury.transactions(transactionIndex);
            successfulExecutions[transactionIndex]++;
            expectedEthBalance -= amount;
        } catch {}
    }

    function pause(bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.pause();
    }

    function unpause(bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.unpause();
    }

    function advanceTime(uint32 rawDelay) public {
        uint256 delay = bound(rawDelay, 0, 2 days);
        vm.warp(block.timestamp + delay);
    }
}

contract TreasuryInvariantTest is Test {
    Treasury public treasury;
    Handler public handler;
    address public ownerTwo = address(0xDEAD);

    function setUp() public {
        treasury = new Treasury();
        treasury.addOwner(ownerTwo);

        _executeRoleChange(ownerTwo, Treasury.Role.Guardian, true);
        _executeRoleChange(ownerTwo, Treasury.Role.Executor, true);
        _executeRoleChange(ownerTwo, Treasury.Role.Treasurer, true);

        handler = new Handler(treasury, address(this), ownerTwo);
        targetContract(address(handler));
    }

    function invariantTransactionsHaveValidState() public view {
        for (uint256 i = 0; i < treasury.getTransactionCount(); i++) {
            (,, bool executed, bool cancelled, uint256 confirmations, uint256 executeAfter, bool queued) =
                treasury.transactions(i);

            assertLe(confirmations, treasury.getOwnerCount());

            if (executed) {
                assertTrue(queued);
                assertFalse(cancelled);
                assertLe(executeAfter, block.timestamp);
            }

            if (cancelled) {
                assertFalse(executed);
            }

            if (queued) {
                assertGt(executeAfter, 0);
            }
        }
    }

    function invariantSpentTodayNeverExceedsLimit() public view {
        assertLe(treasury.spentToday(), treasury.DAILY_WITHDRAWAL_LIMIT());
    }

    function invariantConfirmationCountMatchesApprovals() public view {
        for (uint256 i = 0; i < treasury.getTransactionCount(); i++) {
            (,,,, uint256 confirmations,,) = treasury.transactions(i);

            uint256 approvalCount;
            for (uint256 j = 0; j < treasury.getOwnerCount(); j++) {
                address owner = treasury.owners(j);
                if (treasury.approved(i, owner)) {
                    approvalCount++;
                }
            }

            assertEq(confirmations, approvalCount);
        }
    }

    function invariantExecutedTransactionsCannotExecuteAgain() public view {
        for (uint256 i = 0; i < treasury.getTransactionCount(); i++) {
            (,, bool executed,,,,) = treasury.transactions(i);

            assertLe(handler.successfulExecutions(i), 1);
            if (executed) {
                assertEq(handler.successfulExecutions(i), 1);
            }
        }
    }

    function invariantCancelledTransactionsNeverExecute() public view {
        for (uint256 i = 0; i < treasury.getTransactionCount(); i++) {
            (,, bool executed, bool cancelled,,,) = treasury.transactions(i);

            if (cancelled) {
                assertFalse(executed);
                assertEq(handler.successfulExecutions(i), 0);
            }
        }
    }

    function invariantEthBalanceMatchesSuccessfulTransfers() public view {
        assertEq(address(treasury).balance, handler.expectedEthBalance());
    }

    function invariantQueuedTransactionsAreImmutable() public view {
        for (uint256 i = 0; i < treasury.getTransactionCount(); i++) {
            if (handler.hasQueuedSnapshot(i)) {
                (address recipient, uint256 amount,,,, uint256 executeAfter, bool queued) = treasury.transactions(i);

                assertTrue(queued);
                assertEq(recipient, handler.queuedRecipients(i));
                assertEq(amount, handler.queuedAmounts(i));
                assertEq(executeAfter, handler.queuedExecuteAfter(i));
            }
        }
    }

    function invariantAdministrationRemainsUsable() public view {
        assertGt(treasury.getOwnerCount(), 0);
        assertGt(treasury.guardianCount(), 0);
        assertGt(treasury.executorCount(), 0);
        assertGt(treasury.treasurerCount(), 0);

        for (uint256 i = 0; i < treasury.getOwnerCount(); i++) {
            assertTrue(treasury.isOwner(treasury.owners(i)));
        }
    }

    function _executeRoleChange(address account, Treasury.Role role, bool grant) private {
        uint256 roleChangeIndex = treasury.proposeRoleChange(account, role, grant);
        treasury.approveRoleChange(roleChangeIndex);

        vm.prank(ownerTwo);
        treasury.approveRoleChange(roleChangeIndex);

        treasury.queueRoleChange(roleChangeIndex);
        vm.warp(block.timestamp + treasury.ROLE_CHANGE_DELAY());
        treasury.executeRoleChange(roleChangeIndex);
    }
}
