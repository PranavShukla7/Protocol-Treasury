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