// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Operators} from "./common/access/Operators.sol";

contract TLC is Operators{

    struct Token {
        address tokenAddress;
        uint256 price;
        uint256 reserveBalance;
        uint256 lastUpdatedAt;
    }

    struct Reserve {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 createdAt;
    }

    // Collateral Parameters

    /// Requited collaterial backing to not be in bad debt
    uint256 public collateralizationRatio;

    /// Total collateral posted
    uint256 public collateralBalance;

    //// Total debt taken out
    uint256 public debtBalance;

    /// Fixed interest rate
    uint256 public interestRate;

    /// Amount in seconds for interest to accumulate
    uint256 public interestRatePeriod;

    /// Fee for taking out a loan
    uint256 public originationFee;
    // uint256 public liquidationPenalty;
    
    /// Mapping of user positions
    mapping(address => Debt) public debts;

    Token public Reserve;

    Token public loan;


    error ZeroBalance();

    /**
     * @dev Get user principal amount
     * @return principal amount
     */
    function getDebtAmount() public view returns (uint256) {
        return debts[msg.sender].debtAmount;
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @return total Debt
     */
    function getTotalDebtAmount() public view returns (uint256) {
        uint totalDebt = debts[msg.sender].debtAmount;
        uint256 periodsPerYear = 365 days / interestRatePeriod;
        uint256 periodsElapsed = (block.timestamp / interestRatePeriod) - (debts[msg.sender].createdAt / interestRatePeriod);
        totalDebt += ((totalDebt * interestRate) / 10000 / periodsPerYear) * periodsElapsed;
        return totalDebt;
    }

    /**
     * @dev This function allows the Bank owner to deposit the reserve (debt tokens)
     * @param amount is the amount to deposit
     */
    function reserveDeposit(uint256 amount) external onlyOperator{
        require(amount > 0, "Amount is zero !!");
        if (amount = 0) {
            revert ZeroBalance();
        }
        debtBalance += amount;
        IERC20(collateral.tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit ReserveDeposit(amount);
    }


}
