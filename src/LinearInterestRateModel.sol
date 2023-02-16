// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import {IInterestRateModel} from "./interfaces/IInterestRateModel.sol";

contract LinearInterestRateModel is IInterestRateModel {
    
    uint256 private constant PRECISION = 1e18;
    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseInterestRate;

    /**
     * @notice Interest rate at 100 percent utilization
     */
    uint public maxInterestRate;

    /**
     * @notice The utilization point at which slope changes
     */
    uint256 public kinkUtilization;

    /**
     * @notice Interest rate at kink
     */
    uint256 public kinkInterestRateBps;

    event NewInterestParams(uint256 baseInterestRate, uint256 maxInterestRate, uint256 kinkUtilization, uint256 kinkInterestRateBps);

    /**
     * @notice Construct an interest rate model
     * @param _baseInterestRate base interest rate which is the y-intercept when utilization rate is 0
     * @param _maxInterestRate Interest rate at 100 percent utilization
     * @param _kinkUtilization The utilization point at which slope changes
     * @param _kinkInterestRateBps kinkInterestRateBps;
     */
    constructor(uint256 _baseInterestRate, uint256 _maxInterestRate, uint _kinkUtilization, uint _kinkInterestRateBps) {
        //TODO: assert the validity of this information
        baseInterestRate = _baseInterestRate;
        maxInterestRate  = _maxInterestRate;
        kinkUtilization = _kinkUtilization;
        kinkInterestRateBps = _kinkInterestRateBps;
        emit NewInterestParams(baseInterestRate, maxInterestRate, kinkUtilization, kinkInterestRateBps);
    }

    /**
     * @notice Calculates the utilization rate of the market
     * @param totalBorrow total borrowed
     * @param totalReserve total reserve available for borrowing
     * @return The utilization rate
     */
    function utilizationRate(uint256 totalBorrow, uint256 totalReserve) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (totalBorrow == 0 || totalReserve == 0) {
            return 0;
        }

        return (totalBorrow * PRECISION) /  totalReserve;
    }


    /**
     * @notice Calculates the current borrow rate per block
     * @param totalBorrow total borrowed
     * @param totalReserve total reserve available for borrowing
     * @return The borrow rate (scaled by PRECISION)
     */
    function getBorrowRate(uint256 totalBorrow, uint256 totalReserve) public view returns (uint256) {
        uint256 util = utilizationRate(totalBorrow, totalReserve);

        if (util <= kinkUtilization) {
            uint256 slope = ((kinkInterestRateBps - baseInterestRate) * PRECISION ) / kinkUtilization;
            return baseInterestRate + ((util * slope) / PRECISION);
        } else {
            uint256 slope = (((maxInterestRate - kinkInterestRateBps ) * PRECISION) / ( PRECISION  - kinkUtilization));
            return kinkInterestRateBps + (((util - kinkUtilization) * slope) / PRECISION);
        }
    }
}