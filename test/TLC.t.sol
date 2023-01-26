// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import "../src/TLC.sol";
import "../src/common/access/Operators.sol";

contract TLCTest is Test {

    TLC public tlc;

    uint256 public interestRate;
    uint256 public collateralizationRatio;
    uint256 public interestRatePeriod;

    ERC20Mock public collateralToken;
    uint256 public collateralPrice;

    ERC20Mock public debtToken;
    uint256 public debtPrice;

    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x2);


    function setUp() public {

        interestRate = 5; // 5%
        collateralizationRatio = 120;
        interestRatePeriod = 1 hours;
        collateralToken = new ERC20Mock("TempleToken", "Temple", admin, uint(500_000e18));
        collateralPrice = 970; // 0.97
        debtToken = new ERC20Mock("DAI Token", "DAI", admin, uint(500_000e18));
        debtPrice = 1000; // 1 USD

        tlc = new TLC(
            interestRate,
            collateralizationRatio,
            interestRatePeriod,
            address(collateralToken),
            collateralPrice,
            address(debtToken),
            debtPrice
        );

        tlc.addOperator(admin);
    }

    function testInitalization() public {
        assertEq(tlc.interestRate(), interestRate);
        assertEq(tlc.collateralizationRatio(), collateralizationRatio);
        assertEq(tlc.collateralAddress(), address(collateralToken));
        assertEq(tlc.collateralPrice(), collateralPrice);
        assertEq(tlc.debtAddress(), address(debtToken));
        assertEq(tlc.debtPrice(), debtPrice);
    }

    function testAddOperator() public {
        assertEq(tlc.owner(), address(this));
        assertFalse(tlc.operators(alice));
        tlc.addOperator(alice);
        assertTrue(tlc.operators(alice));
    }

    function testRemoveOperator() public {
        assertEq(tlc.owner(), address(this));
        tlc.addOperator(alice);
        assertTrue(tlc.operators(alice));
        tlc.removeOperator(alice);
        assertFalse(tlc.operators(alice));
    }

    function testDepositDebtExpectRevertOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.depositDebt(uint(100_000e18));
    }

    function testdepositDebt() public {
        vm.startPrank(admin);
        uint256 depositAmount = uint256(100_000e18);
        debtToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(depositAmount);

        assertEq(debtToken.balanceOf(address(tlc)), depositAmount);
        assertEq(tlc.debtBalance(), depositAmount);
    }

    function _initDeposit(uint256 depositAmount) internal {
        vm.startPrank(admin);
        debtToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(depositAmount);
        vm.stopPrank();
    }

    function testPostCollateralZeroBalanceRevert() external {
        _initDeposit(uint256(100_000e18));
        vm.expectRevert(abi.encodeWithSelector(TLC.ZeroBalance.selector, alice));
        vm.prank(alice);
        uint256 collateralAmount = uint(0);
        tlc.postCollateral(collateralAmount);
    }

    function testPostCollateralPasses() external {
        _initDeposit(uint256(100_000e18));
        uint256 collateralAmount = uint(200_000e18);
        deal(address(collateralToken), alice, collateralAmount);
        vm.startPrank(alice);
        collateralToken.approve(address(tlc), collateralAmount);
        tlc.postCollateral(collateralAmount);
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(address(tlc)), collateralAmount);
        assertEq(tlc.collateralBalance(), collateralAmount);
    }

    function _postCollateral(address user, uint256 collateralAmount) internal {
        _initDeposit(100_000e18);
        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        collateralToken.approve(address(tlc), collateralAmount);
        tlc.postCollateral(collateralAmount);
        vm.stopPrank();
    }

    function testBorrowCapacity() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 expectedMaxBorrowCapacity = uint(97_000e18) * uint(100) / uint(120);
        _postCollateral(alice, collateralAmount);
        assertEq(tlc.maxBorrowCapacity(alice), expectedMaxBorrowCapacity);
    }

    function testBorrowInsufficientCollateral() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        uint256 maxBorrowCapacity = tlc.maxBorrowCapacity(alice);
        uint256 borrowAmount = maxBorrowCapacity + uint(1);
        vm.expectRevert(abi.encodeWithSelector(TLC.InsufficentCollateral.selector, maxBorrowCapacity, borrowAmount));
        vm.prank(alice);
        tlc.borrow(borrowAmount);
    }

    function testBorrowPasses() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        uint256 tlcDebtBalance = debtToken.balanceOf(address(tlc));
        uint256 maxBorrowCapacity = tlc.maxBorrowCapacity(alice);
        vm.prank(alice);
        tlc.borrow(maxBorrowCapacity);

        (uint256 aliceCollateralAmount, uint256 aliceDebtAmount, uint256 aliceCreatedAt) = tlc.positions(alice);

        assertEq(aliceCollateralAmount, collateralAmount);
        assertEq(aliceDebtAmount, maxBorrowCapacity);
        assertEq(aliceCreatedAt, block.timestamp);
        assertEq(tlc.debtBalance(), tlcDebtBalance - maxBorrowCapacity);
        assertEq(debtToken.balanceOf(alice), maxBorrowCapacity);
    }

}
