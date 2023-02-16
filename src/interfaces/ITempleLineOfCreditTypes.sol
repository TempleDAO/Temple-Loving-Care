// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface ITempleLineOfCreditTypes {
    
    enum TokenPrice {
        /// @notice equal to 1 USD
        STABLE,
        /// @notice treasury price index
        TPI
    }

    struct ReserveToken {
        /// @notice deployed contract address
        address tokenAddress;

        /// @notice hardcoded token price
        TokenPrice tokenPrice;

        /// @notice minimum collateralization ratio to prevent liquidation
        uint256 minCollateralizationRatio;

        /// @notice total amount of reserves that been supplied
        uint256 totalReserve;

        /// @notice total amount that has been already borrowed
        uint256 totalBorrow;

        //// @notice total number of shares that have been issued
        uint256 totalShares;

        /// @notice interest rate model contract
        address interestRateModel;

        /// @notice last time the interest was updated At
        uint256 interestRateLastUpdatedAt;

        /// @notice mapping of user debt share on totalShares    
        mapping(address => uint256) shares;
    }
    
}