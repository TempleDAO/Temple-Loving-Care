// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;


import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {Operators} from "./common/access/Operators.sol";

interface IERC20MintBurn {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;

}

interface IOudRedeemer {
    function treasuryPriceIndex() external view returns (uint256);
}

contract TempleLineOfCredit is Ownable, Operators {

    using SafeERC20 for IERC20;

    /// @notice A user's posted collateral, debt positions across all debt tokens.
    struct Position {
        /// @notice total collateral posted for this position
        uint256 collateralAmount;
        mapping(address => DebtPosition) debtPosition;
    }

    /// @notice debt position on a specific token
    struct DebtPosition {
        uint256 debtAmount;
        uint256 lastUpdatedAt;
    }

    enum TokenType {
        MINT,
        TRANSFER
    }

    enum TokenPrice {
        /// @notice equal to 1 USD
        STABLE,
        /// @notice treasury price index
        TPI
    }

    /// @notice relevant data related to a debt token
    struct DebtToken {
        /// @notice either a mint token or a transfer
        TokenType tokenType;
        /// @notice Fixed borrow interest rate in bps
        uint256 interestRateBps;
        /// @notice debt token price
        TokenPrice tokenPrice;
        /// @notice Required collateral backing to not be in bad debt. Should have same precision as the collateral price
        uint256 minCollateralizationRatio;
        /// @notice flag to show if debt token is supported
        bool isAllowed;
    }

    /// @notice mapping of debt token to its underlying information
    mapping(address => DebtToken) public debtTokens;

    /// @notice list of all supported debtTokens
    address[] public debtTokenList;

    // Collateral Parameters

    /// @notice Supported collateral token address
    IERC20 public immutable collateralToken;

    /// @notice Collateral token price with 10_000
    TokenPrice public collateralPrice;

    /// @notice contract to get TPI price
    address public oudRedeemer;
    
    /// @notice Address to send bad debt collateral
    address public debtCollector;

    /// @notice Mapping of user positions
    mapping(address => Position) public positions;

    event SetCollateralPrice(TokenPrice price);
    event SetDebtCollector(address debtCollector); 
    event SetMinCollateralizationRatio(address debtToken, uint256 minCollateralizationRatio);
    event AddDebtToken(address token);
    event RemoveDebtToken(address token);
    event DepositReserve(address debtToken, uint256 amount);
    event RemoveReserve(address debtToken, uint256 amount);
    event PostCollateral(address account, uint256 amount);
    event Borrow(address account, address debtToken, uint256 amount);
    event Repay(address account, uint256 amount);
    event Withdraw(address account, uint256 amount);
    event Liquidated(address account, uint256 debtAmount, uint256 collateralSeized);

    error InvalidAmount(uint256 amount);
    error InvalidArrayLength();
    error Unsupported(address token);
    error InvalidTokenPrice(TokenPrice tokenPrice);
    error InsufficentCollateral(address debtToken, uint256 maxCapacity, uint256 borrowAmount);
    error ExceededBorrowedAmount(address account, uint256 amountBorrowed, uint256 amountRepay);
    error ExceededCollateralAmonut(address account, uint256 amountCollateral, uint256 collateralWithdraw);
    error WillUnderCollaterlize(address account, uint256 withdrawalAmount);
    error OverCollaterilized(address account);
    
    constructor(
        address _collateralToken,
        TokenPrice _collateralPrice,
        address _debtCollector,

        address _oudRedeemer

    ) {
        
        collateralToken = IERC20(_collateralToken);
        collateralPrice = _collateralPrice;
        debtCollector = _debtCollector;
        oudRedeemer = _oudRedeemer;
    }


    function addOperator(address _address) external override onlyOwner {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyOwner {
        _removeOperator(_address);
    }

    function setCollateralPrice(TokenPrice _collateralPrice) external onlyOperators {
        collateralPrice = _collateralPrice;
        emit SetCollateralPrice(_collateralPrice);
    }

    function setDebtCollector(address _debtCollector) external onlyOperators {
        debtCollector = _debtCollector;
        emit SetDebtCollector(debtCollector);
    }

    function addDebtToken(address token, TokenType tokenType, uint256 interestRateBps, TokenPrice tokenPrice, uint256 minCollateralizationRatio) external onlyOperators {
        DebtToken memory newDebtToken = DebtToken(tokenType, interestRateBps, tokenPrice, minCollateralizationRatio, true);
        debtTokens[token] = newDebtToken;
        debtTokenList.push(token);
        emit AddDebtToken(token);
    }


    function removeDebtToken(address debtToken) external onlyOperators {
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        delete debtTokens[debtToken];
        uint256 debtTokensLength = debtTokenList.length;
        for (uint256 i; i < debtTokensLength; ++i) {
            if (debtTokenList[i] == debtToken) {
                // Switch the last item into this place then pop off the end.
                debtTokenList[i] = debtTokenList[debtTokenList.length - 1];
                debtTokenList.pop();
                break;
            }
        }
        emit RemoveDebtToken(debtToken);
    }

    function setMinCollateralizationRatio(address debtToken, uint256 _minCollateralizationRatio) external onlyOperators {
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        debtTokens[debtToken].minCollateralizationRatio = _minCollateralizationRatio;
        emit SetMinCollateralizationRatio(debtToken, _minCollateralizationRatio);
    }


    /**
     * @dev Get current user debt position. (Doesn't account for recently accured interest)
     * @return debt amount 
     */
    function getDebtPosition(address debtToken, address account) external view returns (DebtPosition memory) {
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        return positions[account].debtPosition[debtToken];
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @return total Debt
     */
    function getTotalDebtAmount(address debtToken, address account) public view returns (uint256) {
        DebtToken storage debtTokenInfo = debtTokens[debtToken];
        if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken);

        DebtPosition storage userPosition = positions[account].debtPosition[debtToken];

        uint256 totalDebt = userPosition.debtAmount;
        uint256 secondsElapsed = block.timestamp - userPosition.lastUpdatedAt; 
        totalDebt += (totalDebt * debtTokenInfo.interestRateBps * secondsElapsed)  / 10000 / 365 days;
        return totalDebt;
    }

    /**
     * @dev Get List of all supported debt tokens
     * @return array of debt toknes
     */
    function getDebtTokenList() external view returns (address[] memory) {
        return debtTokenList;
    }

    function getTokenPrice(TokenPrice _price) public view returns (uint256 price, uint256 precision) {

        if (_price == TokenPrice.STABLE) {
            return (10000, 10000);
        } else {
            // Get Token Price from redemeer
            uint256 tpiPrice = IOudRedeemer(oudRedeemer).treasuryPriceIndex();
            return (tpiPrice, 10000);
        } 
    }

    /**
     * @dev Allows operator to deposit debt tokens
     * @param debtToken debt token to deposit
     * @param account account to take debtToken from 
     * @param amount is the amount to deposit
     */
    function depositReserve(address debtToken, address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (!debtTokens[debtToken].isAllowed || debtTokens[debtToken].tokenType != TokenType.TRANSFER ) revert Unsupported(debtToken);
        IERC20(debtToken).safeTransferFrom(
            account,
            address(this),
            amount
        );
        emit DepositReserve(debtToken, amount);
    }

        /**
     * @dev Allows operator to remove debt token
     * @param debtToken debt token to deposit
     * @param account account to take debt token from 
     * @param amount is the amount to remove
     */
    function removeReserve(address debtToken, address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (!debtTokens[debtToken].isAllowed || debtTokens[debtToken].tokenType != TokenType.TRANSFER ) revert Unsupported(debtToken);
        IERC20(debtToken).safeTransfer(
            account,
            amount
        );
        emit RemoveReserve(debtToken, amount);
    }

    /**
     * @dev Allows borrower to deposit collateral
     * @param collateralAmount is the amount to deposit
     */
    function postCollateral(uint256 collateralAmount) external {
        if (collateralAmount == 0) revert InvalidAmount(collateralAmount);
        positions[msg.sender].collateralAmount += collateralAmount;
        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount 
        );
        emit PostCollateral(msg.sender, collateralAmount);
    }

    /**
     * @dev Allows user to borrow debt tokens
     * @param tokens list of debt tokens to borrow
     * @param borrowAmounts list of amounts to borrow
     */
    function borrow(address[] memory tokens, uint256[] memory borrowAmounts) external {

        if (tokens.length != borrowAmounts.length) {
            revert InvalidArrayLength();
        }

        address debtToken;
        uint256 borrowAmount;
        uint256 debtAmount;
        uint256 borrowCapacity;
        DebtToken storage debtTokenInfo;
        DebtPosition storage userPosition;

        for (uint256 i; i < tokens.length; ++i) {
            
            debtToken = tokens[i];
            borrowAmount = borrowAmounts[i];

            if (borrowAmount == 0) revert InvalidAmount(borrowAmount);

            debtTokenInfo = debtTokens[debtToken];
            if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken); 

            userPosition = positions[msg.sender].debtPosition[debtToken];
            debtAmount = userPosition.debtAmount == 0 ? 0 : getTotalDebtAmount(debtToken, msg.sender);

            
            borrowCapacity = _maxBorrowCapacity(positions[msg.sender].collateralAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio) - debtAmount;
            if (borrowAmount > borrowCapacity) {
                revert InsufficentCollateral(debtToken, borrowCapacity, borrowAmount);
            }

            debtAmount += borrowAmount;
            userPosition.debtAmount = debtAmount;
            userPosition.lastUpdatedAt = block.timestamp;
            
            if (debtTokenInfo.tokenType == TokenType.TRANSFER){
                IERC20(debtToken).safeTransfer(
                    msg.sender,
                    borrowAmount 
                );
            } else {
                IERC20MintBurn(debtToken).mint(
                    msg.sender,
                    borrowAmount 
                );
            }

            emit Borrow(msg.sender, debtToken, borrowAmount);
        }
    }

    function maxBorrowCapacity(address debtToken, address account) public view returns(uint256) {
        DebtToken storage debtTokenInfo = debtTokens[debtToken];
        return  _maxBorrowCapacity(positions[account].collateralAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio);
    }


    function _maxBorrowCapacity(uint256 collateralAmount, TokenPrice debtPrice,  uint256 minCollateralizationRatio) internal view returns (uint256) {
        (uint256 debtTokenPrice, uint256 debtPrecision) = getTokenPrice(debtPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = getTokenPrice(collateralPrice);
        return collateralAmount * collateralTokenPrice * debtPrecision * 10000 / debtTokenPrice  / collateralPrecision / minCollateralizationRatio;
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

        address debtToken;
        DebtToken storage debtTokenInfo;
        uint256 borrowCapacity;
        uint256 debtTokensLength = debtTokenList.length;
        for (uint256 i; i < debtTokensLength; ++i) {

            debtToken = debtTokenList[i];
            debtTokenInfo = debtTokens[debtToken];

            borrowCapacity = _maxBorrowCapacity(collateralAmount - withdrawalAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio);
            
            if (positions[msg.sender].debtPosition[debtToken].debtAmount > borrowCapacity ) {
                revert WillUnderCollaterlize(msg.sender, withdrawalAmount);
            }
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
     * @param tokens is the list of debt tokens to repay
     * @param repayAmounts is amount to repay
     */
    function repay(address[] memory tokens, uint256[] memory repayAmounts) external {

        address debtToken;
        uint256 repayAmount;
        uint256 debtAmount;
        DebtToken storage debtTokenInfo;
        DebtPosition storage userPosition;

        for (uint256 i; i < tokens.length; ++i) {
            
            debtToken = tokens[i];
            repayAmount = repayAmounts[i];
            
            if (repayAmount == 0) revert InvalidAmount(repayAmount);

            debtTokenInfo = debtTokens[debtToken];
            if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken); 

            userPosition = positions[msg.sender].debtPosition[debtToken];
            debtAmount = userPosition.debtAmount == 0 ? 0 : getTotalDebtAmount(debtToken, msg.sender);

            if (repayAmount >  debtAmount) {
              revert ExceededBorrowedAmount(msg.sender, debtAmount, repayAmount);
            }

            userPosition.debtAmount = debtAmount - repayAmount;
            userPosition.lastUpdatedAt = block.timestamp;
            
            if (debtTokenInfo.tokenType == TokenType.TRANSFER){
                IERC20(debtToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    repayAmount 
                );
            } else {
                IERC20MintBurn(debtToken).burn(
                    msg.sender,
                    repayAmount 
                );
            }
            emit Repay(msg.sender, repayAmount);
        }
    }
   
   /**
     * @dev Allows operator to liquidate debtors position
     * @param debtor the account to liquidate
     * @param debtToken specific debt token that is in debt
     */
    function liquidate(address debtor, address debtToken) external onlyOperators {

        DebtToken storage debtTokenInfo = debtTokens[debtToken];
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        
        DebtPosition storage userPosition = positions[debtor].debtPosition[debtToken];
        uint256 totalDebtOwed = userPosition.debtAmount == 0 ? 0 : getTotalDebtAmount(debtToken, debtor);
        uint256 collateralAmount = positions[debtor].collateralAmount;

        (uint256 debtTokenPrice, uint256 debtPrecision) = getTokenPrice(debtTokenInfo.tokenPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = getTokenPrice(collateralPrice);

        if (_getCurrentCollaterilizationRatio(collateralAmount, userPosition.debtAmount, totalDebtOwed, debtTokenPrice, debtPrecision,  collateralTokenPrice, collateralPrecision) >= debtTokenInfo.minCollateralizationRatio) {
            revert OverCollaterilized(debtor);
        }

        uint256 collateralSeized = (totalDebtOwed * debtTokenPrice * collateralPrecision) / collateralTokenPrice / debtPrecision;
        if (collateralSeized > collateralAmount) {
            collateralSeized = collateralAmount;
        }

        positions[debtor].collateralAmount = collateralAmount - collateralSeized;

        // Wipe out all of users other token debts
        address _debtToken;
        uint256 debtTokensLength = debtTokenList.length;
        for (uint256 i; i < debtTokensLength; ++i) {
            _debtToken = debtTokenList[i];
            userPosition = positions[debtor].debtPosition[_debtToken];
            userPosition.debtAmount = 0;
            userPosition.lastUpdatedAt = block.timestamp;
        }

        collateralToken.safeTransfer(
            debtCollector,
            collateralSeized 
        );

        emit Liquidated(debtor, totalDebtOwed, collateralSeized);
    }

    function getCurrentCollaterilizationRatio(address debtToken, address account) external view returns(uint256) {
        (uint256 debtTokenPrice, uint256 debtPrecision) = getTokenPrice(debtTokens[debtToken].tokenPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = getTokenPrice(collateralPrice);
        return _getCurrentCollaterilizationRatio(positions[account].collateralAmount,  positions[account].debtPosition[debtToken].debtAmount, getTotalDebtAmount(debtToken, account), debtTokenPrice, debtPrecision, collateralTokenPrice, collateralPrecision);
    }

    function _getCurrentCollaterilizationRatio(uint256 collateralAmount, uint256 debtAmount, uint256 totalDebtAmount, uint256 debtTokenPrice, uint256 debtPrecision, uint256 collateralTokenPrice, uint256 collateralPrecision) internal view returns(uint256) {
        if (debtAmount == 0 ) {
            return 0;
        } else {

            return ((collateralAmount * collateralTokenPrice * debtPrecision * 10000) / totalDebtAmount / debtTokenPrice / collateralPrecision);
        }
    }

}
