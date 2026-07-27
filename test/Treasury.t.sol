// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury private treasury;

    address private depositor = address(0xA11CE);
    address private nonOwner = address(0xB0B);

    event Deposited(address indexed sender, uint256 amount, uint256 balanceAfter);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 balanceAfter);

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

    function testWithdrawWorks() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 0.75 ether;

        vm.prank(depositor);
        treasury.deposit{value: depositAmount}();

        uint256 ownerBalanceBefore = address(this).balance;
        treasury.withdraw(withdrawAmount);

        assertEq(address(this).balance, ownerBalanceBefore + withdrawAmount);
        assertEq(address(treasury).balance, depositAmount - withdrawAmount);
    }

    function testNonOwnerWithdrawFails() public {
        vm.prank(depositor);
        treasury.deposit{value: 1 ether}();

        vm.prank(nonOwner);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.withdraw(0.5 ether);
    }

    function testBalanceUpdates() public {
        vm.prank(depositor);
        treasury.deposit{value: 3 ether}();

        assertEq(treasury.contractBalance(), 3 ether);

        treasury.withdraw(1 ether);

        assertEq(treasury.contractBalance(), 2 ether);
    }

    function testDepositEmitsEvent() public {
        uint256 amount = 1.25 ether;

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Deposited(depositor, amount, amount);

        vm.prank(depositor);
        treasury.deposit{value: amount}();
    }

    function testWithdrawEmitsEvent() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 0.5 ether;

        vm.prank(depositor);
        treasury.deposit{value: depositAmount}();

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Withdrawn(address(this), withdrawAmount, depositAmount - withdrawAmount);

        treasury.withdraw(withdrawAmount);
    }
}
