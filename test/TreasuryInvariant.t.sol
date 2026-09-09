// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract Handler is Test {
    Treasury public treasury;
    address public depositor;

    constructor(Treasury _treasury, address _depositor) {
        treasury = _treasury;
        depositor = _depositor;
    }

    function deposit(uint96 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, 100 ether);

        vm.deal(depositor, amount);
        vm.prank(depositor);
        treasury.deposit{value: amount}();
    }

    function submitTransaction(address to, uint256 value) public {
        vm.prank(depositor);
        treasury.submitTransaction(to, value);
    }

    function approveTransaction(uint256 transactionIndex) public {
        vm.prank(depositor);
        treasury.approveTransaction(transactionIndex);
    }

    function queueTransaction(uint256 transactionIndex) public {
        vm.prank(depositor);
        treasury.queue(transactionIndex);
    }

    function cancelTransaction(uint256 transactionIndex) public {
        vm.prank(depositor);
        treasury.cancelTransaction(transactionIndex);
    }

    function executeTransaction(uint256 transactionIndex) public {
        vm.prank(depositor);
        treasury.execute(transactionIndex);
    }

    function pause() public {
        vm.prank(depositor);
        treasury.pause();
    }

    function unpause() public {
        vm.prank(depositor);
        treasury.unpause();
    }
}

contract TreasuryInvariantTest is Test {
    Treasury public treasury;
    Handler public handler;
    address public depositor;

    function setUp() public {
        depositor = address(0xDEAD);
        treasury = new Treasury();
        handler = new Handler(treasury, depositor);

        treasury.addOwner(depositor);
        //treasury.addOwner(address(this));
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
}
