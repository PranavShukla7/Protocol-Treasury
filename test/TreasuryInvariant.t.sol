// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract Handler is Test {
    Treasury public treasury;
    address public ownerOne;
    address public ownerTwo;

    constructor(Treasury _treasury, address _ownerOne, address _ownerTwo) {
        treasury = _treasury;
        ownerOne = _ownerOne;
        ownerTwo = _ownerTwo;
    }

    function _actor(bool useOwnerTwo) private view returns (address) {
        return useOwnerTwo ? ownerTwo : ownerOne;
    }

    function deposit(uint96 rawAmount, bool useOwnerTwo) public {
        uint256 amount = bound(rawAmount, 1, 100 ether);
        address actor = _actor(useOwnerTwo);

        vm.deal(actor, amount);
        vm.prank(actor);
        treasury.deposit{value: amount}();
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
        treasury.queue(transactionIndex);
    }

    function cancelTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.cancelTransaction(transactionIndex);
    }

    function executeTransaction(uint256 transactionIndex, bool useOwnerTwo) public {
        vm.prank(_actor(useOwnerTwo));
        treasury.execute(transactionIndex);
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