// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;



import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {Operators} from "./common/access/Operators.sol";
import {ITempleLineOfCredit} from "./interfaces/ITempleLineOfCredit.sol";
import {IInterestRateModel} from "./interfaces/IInterestRateModel.sol";
import {Compounding} from "./libraries/compounding.sol";

import "forge-std/console.sol";

interface IERC20MintBurn {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

interface IOudRedeemer {
    function treasuryPriceIndex() external view returns (uint256);
}

contract TempleLineOfCreditV2 is ITempleLineOfCredit, Ownable, Operators {

    using SafeERC20 for IERC20;
    using Compounding for uint256;

    /// Collateral Parameters
    /// @notice Collateral Token used by TLC
    IERC20 public immutable templeToken;
    /// @notice price of temple with 10_000 precision
    TokenPrice public templePrice;

    /// @notice total collateral posted by user mapping
    mapping(address => uint256) public collateralPosted;

    ReserveToken public dai;
    ReserveToken public oud;

    /// @notice contract to get TPI price
    IOudRedeemer public oudRedeemer;

    constructor(
        address _templeToken,
        TokenPrice _templePrice,

        address _daiToken,
        address _daiInterestRateModel,
        TokenPrice _daiPrice,
        uint256 _daiMinCollateralizationRatio,

        address _oudToken,
        address _oudInterestRateModel,
        TokenPrice _oudPrice,
        uint256 _oudMinCollateralizationRatio,

        address _oudRedeemer

    ) {

        templeToken = IERC20(_templeToken);
        templePrice = _templePrice;

        dai.tokenAddress =_daiToken;
        dai.interestRateModel = _daiInterestRateModel;
        dai.tokenPrice = _daiPrice;
        dai.minCollateralizationRatio = _daiMinCollateralizationRatio; 

        oud.tokenAddress = _oudToken;
        oud.interestRateModel = _oudInterestRateModel;
        oud.tokenPrice = _oudPrice;
        oud.minCollateralizationRatio = _oudMinCollateralizationRatio;

        oudRedeemer = IOudRedeemer(_oudRedeemer);
    }

    function addOperator(address _address) external override onlyOwner {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyOwner {
        _removeOperator(_address);
    }

    /**
     * @notice Set the borrow interest rate for debt token
     * @param debtToken address of the debt token
     * @param interestRateModel the interest rate model to use
     */
    function setInterestRateModel(address debtToken, address interestRateModel) external onlyOperators{

        if (debtToken == dai.tokenAddress) {
            _accrueInterest(dai);
            dai.interestRateModel = interestRateModel;
        } else if (debtToken == oud.tokenAddress) {
            _accrueInterest(oud);
            oud.interestRateModel = interestRateModel;
        } else {
            revert Unsupported(debtToken);
        }
    }


    function _accrueInterest(ReserveToken storage reserve) internal {

        uint256 totalBorrow = reserve.totalBorrow;
        uint256 totalReserve = reserve.totalReserve;
        uint256 totalShares = reserve.totalShares;

        // If no borrow just reset interest updated at.
        if (totalShares == 0) {

            reserve.interestRateLastUpdatedAt = block.timestamp;

        } else {

            uint256 timeElapsed = block.timestamp - reserve.interestRateLastUpdatedAt;
            uint256 newInterestRate =  IInterestRateModel(reserve.interestRateModel).getBorrowRate(totalBorrow, totalReserve);

            uint256 interestEarned = totalBorrow.continuouslyCompounded(timeElapsed, newInterestRate) - totalBorrow;

            totalBorrow += interestEarned;
            totalReserve += interestEarned; // Reserve should also increase to properly account for utilization rate

            reserve.totalBorrow = totalBorrow;
            reserve.totalReserve = totalReserve;
            reserve.interestRateLastUpdatedAt = block.timestamp;

            emit InterestRateUpdate(reserve.tokenAddress, newInterestRate);
        }
    }

    /**
     * @notice Allows operator to deposit debt tokens
     * @param account account to take debtToken from 
     * @param amount is the amount to deposit
     */
    function depositDAIReserve(address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        dai.totalReserve += amount;
        IERC20(dai.tokenAddress).safeTransferFrom(
            account,
            address(this),
            amount
        );
        emit DepositReserve(dai.tokenAddress, amount);
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @param account user address
     */
    function getTotalDebtAmount(address account) public view returns(uint256 daiAmount, uint256 oudAmount) {

        uint256 totalBorrow = dai.totalBorrow;
        uint256 totalReserve = dai.totalReserve;

        uint256 timeElapsed = block.timestamp - dai.interestRateLastUpdatedAt;
        uint256 newinterestRate = IInterestRateModel(dai.interestRateModel).getBorrowRate(totalBorrow, totalReserve);
        uint256 shares = dai.shares[account];
        daiAmount = _sharesToAmount(dai.totalShares, totalBorrow.continuouslyCompounded(timeElapsed, newinterestRate), shares);

        totalBorrow = oud.totalBorrow;
        totalReserve = oud.totalReserve;
        timeElapsed = block.timestamp - oud.interestRateLastUpdatedAt;
        newinterestRate = IInterestRateModel(oud.interestRateModel).getBorrowRate(totalBorrow, totalReserve);
        shares = oud.shares[account];
        oudAmount = _sharesToAmount(oud.totalShares, totalBorrow.continuouslyCompounded(timeElapsed, newinterestRate), shares);
    }


    /**
     * @notice Get Price of a token
     * @param price type of token
     */
    function getTokenPrice(TokenPrice tokenPrice) public view returns (uint256 price, uint256 precision) {

        if (tokenPrice== TokenPrice.STABLE) {
            price = 10000;
            precision = 10000;
        } else {
            // Get Token Price from redemeer
            price = IOudRedeemer(oudRedeemer).treasuryPriceIndex();
            precision = 10000;
        } 
    }

    /**
     * @dev Allows borrower to deposit temple collateral
     * @param collateralAmount is the amount to deposit
     */
    function postCollateral(uint256 collateralAmount) external {
        if (collateralAmount == 0) revert InvalidAmount(collateralAmount);
        collateralPosted[msg.sender] += collateralAmount;
        templeToken.safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount 
        );
        emit PostCollateral(msg.sender, collateralAmount);
    }

    /**
     * @notice Convert total shares to 
     * @param totalAmount total amount of reserve token deposited/minted
     * @param totalShares total shares issued to borrowers
     * @param amount amount to get share equivalent of
     */
    function _amountToShares(uint256 totalAmount, uint256 totalShares, uint256 amount) pure internal returns(uint256) {
        if (totalAmount == 0) {
            return amount;
        }
        return (amount * totalShares) / totalAmount;
    }

    function _sharesToAmount(uint256 totalShares, uint256 totalAmount, uint shares) pure internal returns(uint256) {
        if (totalShares == 0) {
            return shares;
        }
        return (shares * totalAmount) / totalShares;
    }


    /**
     * @dev Allows user to borrow debt tokens
     * @param daiBorrowAmount amount of dai to borrow
     * @param oudBorrowAmount amount of oud to borrow
     */
    function borrow(uint256 daiBorrowAmount, uint256 oudBorrowAmount) external {
      
        uint256 collateralAmount = collateralPosted[msg.sender];

        if (daiBorrowAmount != 0 ) {
            _borrow(dai, collateralAmount, daiBorrowAmount);

            IERC20(dai.tokenAddress).safeTransfer(
                msg.sender,
                daiBorrowAmount 
            );
        } 
        
        if (oudBorrowAmount != 0) {
            _borrow(oud, collateralAmount, oudBorrowAmount);
            IERC20MintBurn(oud.tokenAddress).mint(
               msg.sender,
               oudBorrowAmount 
            );
        } 
    }

    function _borrow(ReserveToken storage reserve, uint256 collateralAmount, uint256 borrowAmount) internal {

        _accrueInterest(reserve);

        uint256 shares = reserve.shares[msg.sender];
        uint256 totalBorrowAmount = _sharesToAmount(reserve.totalShares, reserve.totalBorrow, shares);

        // Check if user has sufficient collateral
        uint256 borrowCapacity = _maxBorrowCapacity(collateralAmount, reserve.tokenPrice, reserve.minCollateralizationRatio) - totalBorrowAmount;
        if (borrowAmount > borrowCapacity) {
            revert InsufficentCollateral(borrowCapacity, borrowAmount);
        }

        uint256 newshares = _amountToShares(reserve.totalBorrow, reserve.totalShares, borrowAmount);
        reserve.shares[msg.sender] += newshares;
        reserve.totalShares += newshares;
        reserve.totalBorrow += borrowAmount;

        emit Borrow(msg.sender, reserve.tokenAddress, borrowAmount);
    }
    
   /**
     * @notice Allows borrower to repay borrowed amount
     * @param repayDaiAmount amount of dai to repay
     * @param repayOudAmount amount of oud to repay
     */
    function repay(uint256 repayDaiAmount, uint256 repayOudAmount) public {

        if (repayDaiAmount != 0 ) {
            _repay(dai, repayDaiAmount);
            IERC20(dai.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                repayDaiAmount 
            );
        } 
        
        if (repayOudAmount != 0) {
             _repay(oud, repayOudAmount);
            IERC20MintBurn(oud.tokenAddress).burn(
                msg.sender,
                repayOudAmount
            );
        } 
    }

   /**
     * @notice Allows borrower to repay all outstanding balances
     * @dev leave no dust balance
     */
    function repayAll() external {
        (uint256 daiTotalAmount, uint256 oudTotalAmount) = getTotalDebtAmount(msg.sender);
        repay(daiTotalAmount, oudTotalAmount);
    }

    function _repay(ReserveToken storage reserve, uint256 repayAmount) internal {

        _accrueInterest(reserve);

        uint256 shares = reserve.shares[msg.sender];
        uint256 totalBorrowAmount = _sharesToAmount(reserve.totalShares, reserve.totalBorrow, shares);

        if (repayAmount > totalBorrowAmount) {
            revert ExceededBorrowedAmount(totalBorrowAmount, repayAmount);
        }

        uint256 sharesToRemove = _amountToShares(reserve.totalBorrow, reserve.totalShares, repayAmount);

        reserve.shares[msg.sender] -= sharesToRemove;
        reserve.totalShares -= sharesToRemove;
        reserve.totalBorrow -= repayAmount;

        emit Repay(msg.sender, repayAmount);
    }

    /**
     * @notice Get user max borrow capacity 
     * @param debtToken token to get max borrow capacity for 
     * @param account address of user 
     */
    function maxBorrowCapacity(address debtToken, address account) public view returns(uint256) {
        ReserveToken storage reserve; 
        if (debtToken == dai.tokenAddress) {
            reserve = dai;
        } else if (debtToken == oud.tokenAddress) {
            reserve = oud;
        } else {
            revert Unsupported(debtToken);
        }

        return  _maxBorrowCapacity(collateralPosted[account], reserve.tokenPrice, reserve.minCollateralizationRatio);
    }

    function _maxBorrowCapacity(uint256 collateralAmount, TokenPrice debtPrice,  uint256 minCollateralizationRatio) internal view returns (uint256) {
        (uint256 debtTokenPrice, uint256 debtPrecision) = getTokenPrice(debtPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = getTokenPrice(templePrice);
        return collateralAmount * collateralTokenPrice * debtPrecision * 10000 / debtTokenPrice  / collateralPrecision / minCollateralizationRatio;
    }

    function userShares(address account, address debtToken) external view returns(uint256) {
        ReserveToken storage reserve; 
        if (debtToken == dai.tokenAddress) {
            reserve = dai;
        } else if (debtToken == oud.tokenAddress) {
            reserve = oud;
        } else {
            revert Unsupported(debtToken);
        }
        return reserve.shares[account];
    }
}