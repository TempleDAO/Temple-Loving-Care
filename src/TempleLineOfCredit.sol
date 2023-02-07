// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;


import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {Operators} from "./common/access/Operators.sol";

contract TempleLineOfCredit is Ownable, Operators {

    using SafeERC20 for IERC20;

    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 createdAt;
    }

    // Collateral Parameters

    /// @notice Supported collateral token address
    IERC20 public immutable collateralToken;

    /// @notice Collateral token price
    uint256 public collateralPrice;

    /// @notice Required collateral backing to not be in bad debt in percentage
    uint256 public minCollateralizationRatio;

    /// @notice Total debt taken out
    uint256 public debtBalance;

    /// @notice Fixed borrow interest rate in bpds
    uint256 public immutable interestRateBps;

    /// @notice Amount in seconds for interest to accumulate
    uint256 public immutable interestRatePeriod;

    /// @notice Address to send bad debt collateral
    address public debtCollector;

    /// Debt parameters

    /// @notice Debt token address
    IERC20 public immutable debtToken;

    /// @notice Debt token price
    uint256 public debtPrice;
    
    /// @notice Mapping of user positions
    mapping(address => Position) public positions;

    event DepositDebt(uint256 amount);
    event RemoveDebt(uint256 amount);
    event PostCollateral(address account, uint256 amount);
    event Borrow(address account, uint256 amount);
    event Repay(address account, uint256 amount);
    event Withdraw(address account, uint256 amount);
    event Liquidated(address account, uint256 debtAmount, uint256 collateralSeized);

    error InvalidAmount(uint256 amount);
    error InsufficentCollateral(uint256 maxCapacity, uint256 debtAmount);
    error ExceededBorrowedAmount(address account, uint256 amountBorrowed, uint256 amountRepay);
    error ExceededCollateralAmonut(address account, uint256 amountCollateral, uint256 collateralWithdraw);
    error WillUnderCollaterlize(address account, uint256 withdrawalAmount);
    error OverCollaterilized(address account);
    
    constructor(
        uint256 _interestRateBps,
        uint256 _minCollateralizationRatio,
        uint256 _interestRatePeriod,

        address _collateralToken,
        uint256 _collateralPrice,

        address _debtToken,
        uint256 _debtPrice,
        address _debtCollector

    ) {
        interestRateBps = _interestRateBps;
        minCollateralizationRatio = _minCollateralizationRatio;
        interestRatePeriod = _interestRatePeriod;
        
        collateralToken = IERC20(_collateralToken);
        collateralPrice = _collateralPrice;

        debtToken = IERC20(_debtToken);
        debtPrice = _debtPrice;
        
        debtCollector = _debtCollector;
    }


    function addOperator(address _address) external override onlyOwner {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyOwner {
        _removeOperator(_address);
    }

    function setDebtPrice(uint256 _debtPrice) external onlyOperators {
        debtPrice = _debtPrice;
    }

    function setCollateralPrice(uint256 _collateralPrice) external onlyOperators {
        collateralPrice = _collateralPrice;
    }

    function setDebtCollector(address _debtCollector) external onlyOperators {
        debtCollector = _debtCollector;
    }

    function setCollateralizationRatio(uint256 _minCollateralizationRatio) external onlyOperators {
        minCollateralizationRatio = _minCollateralizationRatio;
    }

    /**
     * @dev Get user principal amount
     * @return principal amount
     */
    function getDebtAmount(address account) public view returns (uint256) {
        return positions[account].debtAmount;
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @return total Debt
     */
    function getTotalDebtAmount(address account) public view returns (uint256) {
        uint256 totalDebt = positions[account].debtAmount;
        uint256 periodsPerYear = 365 days / interestRatePeriod;
        uint256 periodsElapsed = block.timestamp - positions[account].createdAt; // divided by interestRatePeriod
        totalDebt += (((totalDebt * interestRateBps) / 10000 / periodsPerYear) * periodsElapsed) / interestRatePeriod;
        return totalDebt;
    }

    /**
     * @dev Allows operator to depoist debt tokens
     * @param amount is the amount to deposit
     */
    function depositDebt(address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        debtBalance += amount;
        debtToken.safeTransferFrom(
            account,
            address(this),
            amount
        );
        emit DepositDebt(amount);
    }

        /**
     * @dev Allows operator to remove debt token
     * @param amount is the amount to remove
     */
    function removeDebt(uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        debtBalance -= amount;
        debtToken.safeTransfer(
            msg.sender,
            amount
        );
        emit RemoveDebt(amount);
    }

    /**
     * @dev Allows borrower to deposit collateral
     * @param amount is the amount to deposit
     */
    function postCollateral(uint256 amount) external {
        if (amount == 0) revert InvalidAmount(amount);
        positions[msg.sender].collateralAmount += amount;
        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit PostCollateral(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert InvalidAmount(amount);

        uint256 debtAmount =  positions[msg.sender].debtAmount;
        if (debtAmount != 0) {
            debtAmount = getTotalDebtAmount(msg.sender);
        }

        uint256 borrowCapacity = _maxBorrowCapacity(positions[msg.sender].collateralAmount) - debtAmount;
        debtAmount += amount;

        if (debtAmount > borrowCapacity) {
            revert InsufficentCollateral(borrowCapacity, debtAmount);
        }

        positions[msg.sender].debtAmount = debtAmount;
        
        // If more than 1 interest rate period has passed update the start-time
        if (block.timestamp - positions[msg.sender].createdAt >= interestRatePeriod || positions[msg.sender].createdAt == 0 ) {
            positions[msg.sender].createdAt = block.timestamp;
        }
         
        debtBalance -= amount;
        debtToken.safeTransfer(
            msg.sender,
            amount
        );
        emit Borrow(msg.sender, amount);
    }

    function maxBorrowCapacity(address account) public view returns(uint256) {
        return  _maxBorrowCapacity(positions[account].collateralAmount);
    }


    function _maxBorrowCapacity(uint256 collateralAmount) internal view returns (uint256) {
        return collateralAmount * collateralPrice * 100 / debtPrice / minCollateralizationRatio;
    }

   /**
     * @dev Allows borrower to with draw collateral if sufficient to not default on loan
     * @param withdrawalAmount is the amount to withdraw
     */
    function withdrawCollateral(uint256 withdrawalAmount) external {
        if (withdrawalAmount == 0) revert InvalidAmount(withdrawalAmount);
        uint256 collateralAmount = positions[msg.sender].collateralAmount;
        if (withdrawalAmount > collateralAmount) {
            revert ExceededCollateralAmonut(msg.sender, collateralAmount, withdrawalAmount);
        }

        uint256 borrowCapacity = _maxBorrowCapacity(collateralAmount - withdrawalAmount);
        
        if (positions[msg.sender].debtAmount > borrowCapacity ) {
            revert WillUnderCollaterlize(msg.sender, withdrawalAmount);
        }

        positions[msg.sender].collateralAmount -= withdrawalAmount;
        collateralToken.safeTransfer(
            msg.sender,
            withdrawalAmount
        );

        emit Withdraw(msg.sender, withdrawalAmount);
    }

   /**
     * @dev Allows borrower to repay borrowed amount
     * @param repayAmount is the amount to repay
     */
    function repay(uint256 repayAmount) external {
        if (repayAmount == 0) revert InvalidAmount(repayAmount);
        positions[msg.sender].debtAmount = getTotalDebtAmount(msg.sender);

        if (repayAmount >  positions[msg.sender].debtAmount) {
            revert ExceededBorrowedAmount(msg.sender, positions[msg.sender].debtAmount, repayAmount);
        }

        positions[msg.sender].debtAmount -= repayAmount;
        debtBalance += repayAmount;
        
        // If more than 1 interest rate period has passed update the start-time
        if (block.timestamp - positions[msg.sender].createdAt >= interestRatePeriod || positions[msg.sender].createdAt == 0  ) {
            positions[msg.sender].createdAt = block.timestamp;
        }
        debtToken.safeTransferFrom(
            msg.sender,
            address(this),
            repayAmount 
        );
        emit Repay(msg.sender, repayAmount);
    }
   
   /**
     * @dev Allows operator to liquidate debtors position
     * @param debtor the account to liquidate
     */
    function liquidate(address debtor) external onlyOperators {
        Position storage position = positions[debtor];    
        uint256 totalDebtOwed = getTotalDebtAmount(debtor);

        if (_getCurrentCollaterilizationRatio(position.collateralAmount, position.debtAmount, totalDebtOwed) >= minCollateralizationRatio) {
            revert OverCollaterilized(debtor);
        }

        uint256 collateralSeized = (totalDebtOwed * debtPrice) / collateralPrice;

        if (collateralSeized > position.collateralAmount) {
            collateralSeized = position.collateralAmount;
        }

        position.collateralAmount -= collateralSeized;
        position.debtAmount = 0;
        position.createdAt = 0;

        collateralToken.safeTransfer(
            debtCollector,
            collateralSeized 
        );

        emit Liquidated(debtor, totalDebtOwed, collateralSeized);
    }

    function getCurrentCollaterilizationRatio(address account) public view returns(uint256) {
        _getCurrentCollaterilizationRatio(positions[account].collateralAmount, positions[account].debtAmount, getTotalDebtAmount(account));
    }

    function _getCurrentCollaterilizationRatio(uint256 collateralAmount, uint256 debtAmount, uint256 totalDebtAmount) public view returns(uint256) {
        if (debtAmount == 0 ) {
            return 0;
        } else {
            return ((collateralAmount * collateralPrice * 100) / totalDebtAmount / debtPrice);
        }
    }

}
