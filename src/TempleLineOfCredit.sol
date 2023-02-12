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

    /// @notice debt position on all tokens
    struct Position {
        /// @notice total collateral posted for this position
        uint256 collateralAmount;
        mapping(address => TokenPosition) tokenPosition;
    }

    /// @notice debt position on a specific token
    struct TokenPosition {
        uint256 debtAmount;
        uint256 createdAt;
    }

    enum TokenType {
        MINT,
        TRANSFER
    }

    enum TokenPrice {
        STABLE,
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
    event AddDebtToken(address token);
    event RemoveDebtToken(address token);
    event DepositDebt(address debtToken, uint256 amount);
    event RemoveDebt(address debtToken, uint256 amount);
    event PostCollateral(address account, uint256 amount);
    event Borrow(address account, address debtToken, uint256 amount);
    event Repay(address account, uint256 amount);
    event Withdraw(address account, uint256 amount);
    // event Liquidated(address account, uint256 debtAmount, uint256 collateralSeized);

    error InvalidAmount(uint256 amount);
    error Unsupported(address token);
    error InsufficentCollateral(address debtToken, uint256 maxCapacity, uint256 debtAmount);
    // error InsufficentDebtToken(uint256 debtTokenBalance, uint256 borrowAmount);
    error ExceededBorrowedAmount(address account, uint256 amountBorrowed, uint256 amountRepay);
    error ExceededCollateralAmonut(address account, uint256 amountCollateral, uint256 collateralWithdraw);
    error WillUnderCollaterlize(address account, uint256 withdrawalAmount);
    // error OverCollaterilized(address account);
    
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
        /// TODO: Remove from the debtTokenList
        emit AddDebtToken(debtToken);
    }

    function setMinCollateralizationRatio(address debtToken, uint256 _minCollateralizationRatio) external onlyOperators {
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        debtTokens[debtToken].minCollateralizationRatio = _minCollateralizationRatio;
        emit RemoveDebtToken(debtToken);
    }


    /**
     * @dev Get user principal amount
     * @return principal amount
     */
    function getDebtAmount(address debtToken, address account) public view returns (TokenPosition memory) {
        if (!debtTokens[debtToken].isAllowed) revert Unsupported(debtToken);
        return positions[account].tokenPosition[debtToken];
    }

    /**
     * @dev Get user total debt incurred (principal + interest)
     * @return total Debt
     */
    function getTotalDebtAmount(address debtToken, address account) public view returns (uint256) {
        DebtToken memory debtTokenInfo = debtTokens[debtToken];
        if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken);

        TokenPosition storage userPosition = positions[account].tokenPosition[debtToken];

        uint256 totalDebt = userPosition.debtAmount;
        uint256 secondsElapsed = block.timestamp - userPosition.createdAt; 
        totalDebt += (totalDebt * debtTokenInfo.interestRateBps * secondsElapsed)  / 10000 / 365 days;
        return totalDebt;
    }

    function getDebtTokenPrice(TokenPrice _price) public view returns (uint256 price, uint256 precision) {

        if (_price == TokenPrice.STABLE) {
            return (10000, 10000);
        } else if (_price == TokenPrice.TPI) {
            // Get Token Price from redemeer
            uint256 tpiPrice = IOudRedeemer(oudRedeemer).treasuryPriceIndex();
            return (tpiPrice, 10000);
        }
    }

    /**
     * @dev Allows operator to depoist debt tokens
     * @param amount is the amount to deposit
     */
    function depositDebt(address debtToken, address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (!debtTokens[debtToken].isAllowed || debtTokens[debtToken].tokenType != TokenType.TRANSFER ) revert Unsupported(debtToken);
        IERC20(debtToken).safeTransferFrom(
            account,
            address(this),
            amount
        );
        emit DepositDebt(debtToken, amount);
    }

        /**
     * @dev Allows operator to remove debt token
     * @param amount is the amount to remove
     */
    function removeDebt(address debtToken, address account, uint256 amount) external onlyOperators{
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (!debtTokens[debtToken].isAllowed || debtTokens[debtToken].tokenType != TokenType.TRANSFER ) revert Unsupported(debtToken);
        IERC20(debtToken).safeTransfer(
            msg.sender,
            amount
        );
        emit RemoveDebt(debtToken, amount);
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

    function borrow(address[] memory tokens, uint256[] memory borrowAmounts) external {

        for (uint256 i =0; i < tokens.length; i++) {
            
            address debtToken = tokens[i];
            uint256 borrowAmount = borrowAmounts[i];

            if (borrowAmount == 0) revert InvalidAmount(borrowAmount);

            DebtToken memory debtTokenInfo = debtTokens[debtToken];
            if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken); 

            uint256 debtAmount =  positions[msg.sender].tokenPosition[debtToken].debtAmount;
            if (debtAmount != 0) {
                debtAmount = getTotalDebtAmount(debtToken, msg.sender);
            }

            uint256 borrowCapacity = _maxBorrowCapacity(positions[msg.sender].collateralAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio) - debtAmount;
            debtAmount += borrowAmount;

            if (debtAmount > borrowCapacity) {
                revert InsufficentCollateral(debtToken, borrowCapacity, debtAmount);
            }

            TokenPosition storage userPosition = positions[msg.sender].tokenPosition[debtToken];

            userPosition.debtAmount = debtAmount;
            userPosition.createdAt = block.timestamp;
            
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
        DebtToken memory debtTokenInfo = debtTokens[debtToken];
        return  _maxBorrowCapacity(positions[account].collateralAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio);
    }


    function _maxBorrowCapacity(uint256 collateralAmount, TokenPrice debtPrice,  uint256 minCollateralizationRatio) internal view returns (uint256) {
        (uint256 debtTokenPrice, uint256 debtPercision) = getDebtTokenPrice(debtPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = getDebtTokenPrice(collateralPrice);
        return collateralAmount * collateralTokenPrice * debtPercision * 10000 / debtTokenPrice  / collateralPrecision / minCollateralizationRatio;
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

        for (uint256 i =0; i < debtTokenList.length; i++) {

            address debtToken = debtTokenList[i];
            DebtToken memory debtTokenInfo = debtTokens[debtToken];

            uint256 borrowCapacity = _maxBorrowCapacity(collateralAmount - withdrawalAmount, debtTokenInfo.tokenPrice, debtTokenInfo.minCollateralizationRatio);
            
            if (positions[msg.sender].tokenPosition[debtToken].debtAmount > borrowCapacity ) {
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

        for (uint256 i =0; i < tokens.length; i++) {
            
            address debtToken = tokens[i];
            uint256 repayAmount = repayAmounts[i];
            
            if (repayAmount == 0) revert InvalidAmount(repayAmount);

            DebtToken memory debtTokenInfo = debtTokens[debtToken];
            if (!debtTokenInfo.isAllowed) revert Unsupported(debtToken); 

            uint256 debtAmount =  positions[msg.sender].tokenPosition[debtToken].debtAmount;
            if (debtAmount != 0) {
                debtAmount = getTotalDebtAmount(debtToken, msg.sender);
            }

            if (repayAmount >  debtAmount) {
              revert ExceededBorrowedAmount(msg.sender, debtAmount, repayAmount);
            }

            TokenPosition storage userPosition = positions[msg.sender].tokenPosition[debtToken];

            userPosition.debtAmount = debtAmount - repayAmount;
            userPosition.createdAt = block.timestamp;
            
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
   
//    /**
//      * @dev Allows operator to liquidate debtors position
//      * @param debtor the account to liquidate
//      */
//     function liquidate(address debtor) external onlyOperators {
//         Position storage position = positions[debtor];    
//         uint256 totalDebtOwed = getTotalDebtAmount(debtor);

//         if (_getCurrentCollaterilizationRatio(position.collateralAmount, position.debtAmount, totalDebtOwed) >= minCollateralizationRatio) {
//             revert OverCollaterilized(debtor);
//         }

//         uint256 collateralSeized = (totalDebtOwed * debtPrice) / collateralPrice;

//         if (collateralSeized > position.collateralAmount) {
//             collateralSeized = position.collateralAmount;
//         }

//         position.collateralAmount -= collateralSeized;
//         position.debtAmount = 0;
//         position.createdAt = 0;

//         collateralToken.safeTransfer(
//             debtCollector,
//             collateralSeized 
//         );

//         emit Liquidated(debtor, totalDebtOwed, collateralSeized);
//     }

    function getCurrentCollaterilizationRatio(address debtToken, address account) public view returns(uint256) {
        DebtToken memory debtTokenInfo = debtTokens[debtToken];
        _getCurrentCollaterilizationRatio(positions[account].collateralAmount,  positions[msg.sender].tokenPosition[debtToken].debtAmount, debtTokenInfo.tokenPrice, getTotalDebtAmount(debtToken, account));
    }

    function _getCurrentCollaterilizationRatio(uint256 collateralAmount, uint256 debtAmount, TokenPrice debtPrice, uint256 totalDebtAmount) public view returns(uint256) {
        if (debtAmount == 0 ) {
            return 0;
        } else {
            (uint256 debtTokenPrice, uint256 debtPercision) = getDebtTokenPrice(debtPrice);
            (uint256 collateralTokenPrice, uint256 collateralPrecision) = getDebtTokenPrice(collateralPrice);
            return ((collateralAmount * collateralTokenPrice * debtPercision * 10000) / totalDebtAmount / debtTokenPrice / collateralPrecision);
        }
    }

}
