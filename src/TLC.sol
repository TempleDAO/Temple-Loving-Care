// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {Operators} from "./common/access/Operators.sol";

contract TLC is Ownable, Operators {

    using SafeERC20 for IERC20;

    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 createdAt;
    }

    // Collateral Parameters

    /// Supported collateral token address
    address public collateralAddress;

    /// Collateral token price 
    uint256 public collateralPrice;

    /// Requited collateral backing to not be in bad debt
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


    /// Debt parameters

    /// Debt token address
    address public debtAddress;

    /// Debt token price
    uint256 public debtPrice;

    
    /// Mapping of user positions
    mapping(address => Position) public positions;

    event DepositDebt(uint256 amount);
    event PostCollateral(uint256 amount);
    event Borrow(address account, uint256 amount);

    error ZeroBalance(address account);
    error InsufficentCollateral(uint256 maxCapacity, uint256 debtAmount);

    constructor(
        uint256 _interestRate,
        uint256 _collateralizationRatio,
        uint256 _interestRatePeriod,

        address _collateralAddress,
        uint256 _collateralPrice,

        address _debtAddress,
        uint256 _debtPrice

    ) {
        interestRate = _interestRate;
        collateralizationRatio = _collateralizationRatio;
        interestRatePeriod = _interestRatePeriod;
        
        collateralAddress = _collateralAddress;
        collateralPrice = _collateralPrice;

        debtAddress = _debtAddress;
        debtPrice = _debtPrice;
    }


    function addOperator(address _address) external override onlyOwner {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyOwner {
        _removeOperator(_address);
    }

    /**
     * @dev Get user principal amount
     * @return principal amount
     */
    function getDebtAmount() public view returns (uint256) {
        return positions[msg.sender].debtAmount;
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @return total Debt
     */
    function getTotalDebtAmount() public view returns (uint256) {
        uint totalDebt = positions[msg.sender].debtAmount;
        uint256 periodsPerYear = 365 days / interestRatePeriod;
        uint256 periodsElapsed = (block.timestamp / interestRatePeriod) - (positions[msg.sender].createdAt / interestRatePeriod);
        totalDebt += ((totalDebt * interestRate) / 10000 / periodsPerYear) * periodsElapsed;
        return totalDebt;
    }

    /**
     * @dev Allows operator to depoist debt tokens
     * @param amount is the amount to deposit
     */
    function depositDebt(uint256 amount) external onlyOperators{
        require(amount > 0, "Amount is zero !!");
        if (amount == 0) {
            revert ZeroBalance(msg.sender);
        }
        debtBalance += amount;
        IERC20(debtAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit DepositDebt(amount);
    }

    /**
     * @dev Allows borrower to deposit collateral
     * @param amount is the amount to deposit
     */
    function postCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroBalance(msg.sender);
        positions[msg.sender].collateralAmount += amount;
        collateralBalance += amount;
        IERC20(collateralAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function borrow(uint256 amount) external {
        if (positions[msg.sender].debtAmount != 0) {
            positions[msg.sender].debtAmount = getTotalDebtAmount();
        }

        uint256 maxBorrowCapacity = maxBorrowCapacity(msg.sender);
        maxBorrowCapacity -= positions[msg.sender].debtAmount;

        // TODO: Add fees for borrowing
        positions[msg.sender].debtAmount += amount;

        if (positions[msg.sender].debtAmount > maxBorrowCapacity) {
            revert InsufficentCollateral(maxBorrowCapacity, positions[msg.sender].debtAmount);
        }
        
        // If more than 1 interest rate period has passed update the start-time
        if (block.timestamp - positions[msg.sender].createdAt > interestRatePeriod || positions[msg.sender].createdAt == 0 ) {
            positions[msg.sender].createdAt = block.timestamp;
        }
         
        debtBalance -= amount;
        IERC20(debtAddress).safeTransfer(
            msg.sender,
            amount
        );
        emit Borrow(msg.sender, amount);
    }

    function maxBorrowCapacity(address account) public returns(uint256) {
        return ((positions[account].collateralAmount * collateralPrice * 100) / debtPrice / collateralizationRatio);
    }

}
