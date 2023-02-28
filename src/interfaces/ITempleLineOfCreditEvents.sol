// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface ITempleLineOfCreditEvents {
    
    event DepositReserve(address debtToken, uint256 amount);

    event PostCollateral(address account, uint256 collateralAmount);

    event Borrow(address account, address debtToken, uint256 amount);

    event Repay(address account, uint256 repayAmount);

    event InterestRateUpdate(address debtToken, uint256 newInterestRate);
}