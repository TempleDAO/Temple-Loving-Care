pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { UD60x18, ud } from "prb-math/UD60x18.sol";
import { mulDiv, UNIT } from "prb-math/Common.sol";

library Compounding {
    uint256 public constant ONE_YEAR = 365 days;

    /// @notice FV = P*e^(r*t)
    /// @param principal Initial principal amount, 1e18 precision
    /// @param elapsed Number of seconds elapsed
    /// @param interestRate The interest rate per annum, 1e18 precision. eg 5% = 0.05e18
    function continuouslyCompounded(uint256 principal, uint256 elapsed, uint256 interestRate) internal pure returns (uint256) {
        uint256 exponent = mulDiv(elapsed, interestRate, ONE_YEAR);
        return mulDiv(
            principal, 
            ud(exponent).exp().unwrap(),
            UNIT
        );
    }
}