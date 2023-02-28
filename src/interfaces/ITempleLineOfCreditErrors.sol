// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface ITempleLineOfCreditErrors {

    error InvalidAmount(uint256 amount);
    error InsufficentCollateral(uint256 maxCapacity, uint256 borrowAmount);
    error Unsupported(address token);
    error ExceededBorrowedAmount(uint256 totalDebtAmount, uint256 repayAmount);
}