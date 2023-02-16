// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface IInterestRateModel {

  function utilizationRate(uint256 totalBorrow, uint256 totalReserve) external pure returns (uint);
  function getBorrowRate(uint256 totalBorrow, uint256 totalReserve) external view returns (uint256);

}