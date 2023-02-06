// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import "../src/TempleLineOfCredit.sol";
import "../src/common/access/Operators.sol";

contract TempleLineOfCreditTest is Test {

    TempleLineOfCredit public tlc;

    uint256 public interestRateBps;
    uint256 public minCollateralizationRatio;
    uint256 public interestRatePeriod;

    ERC20Mock public collateralToken;
    uint256 public collateralPrice;

    ERC20Mock public debtToken;
    uint256 public debtPrice;

    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x2);
    address debtCollector = address(0x3);


    function setUp() public {

        interestRateBps = 500; // 5%
        minCollateralizationRatio = 120;
        interestRatePeriod = 60 seconds;
        collateralToken = new ERC20Mock("TempleToken", "Temple", admin, uint(500_000e18));
        collateralPrice = 970; // 0.97
        debtToken = new ERC20Mock("DAI Token", "DAI", admin, uint(500_000e18));
        debtPrice = 1000; // 1 USD

        tlc = new TempleLineOfCredit(
            interestRateBps,
            minCollateralizationRatio,
            interestRatePeriod,
            address(collateralToken),
            collateralPrice,
            address(debtToken),
            debtPrice,
            debtCollector
        );

        tlc.addOperator(admin);
    }

    function testInitalization() public {
        assertEq(tlc.interestRateBps(), interestRateBps);
        assertEq(tlc.minCollateralizationRatio(), minCollateralizationRatio);
        assertEq(address(tlc.collateralToken()), address(collateralToken));
        assertEq(tlc.collateralPrice(), collateralPrice);
        assertEq(address(tlc.debtToken()), address(debtToken));
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
        tlc.depositDebt(alice, uint(100_000e18));
    }

    function testdepositDebt() public {
        vm.startPrank(admin);
        uint256 depositAmount = uint256(100_000e18);
        debtToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(admin, depositAmount);

        assertEq(debtToken.balanceOf(address(tlc)), depositAmount);
        assertEq(tlc.debtBalance(), depositAmount);
    }

    function _initDeposit(uint256 depositAmount) internal {
        vm.startPrank(admin);
        debtToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(admin, depositAmount);
        vm.stopPrank();
    }

    function testPostCollateralZeroBalanceRevert() external {
        _initDeposit(uint256(100_000e18));
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, uint(0)));
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
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InsufficentCollateral.selector, maxBorrowCapacity, borrowAmount));
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

    function _borrow(address _account, uint256 collateralAmount, uint256 borrowAmount) internal {
        _postCollateral(_account, collateralAmount);
        vm.prank(_account);
        tlc.borrow(borrowAmount);
    }

    function testBorrowAccuresInterest(uint32 periodElapsed) external {
        uint256 borrowAmount = uint(60_000e18);
        _borrow(alice, uint(100_000e18), borrowAmount);

        uint256 borrowTimeStamp = block.timestamp;
       
        vm.warp(block.timestamp +  (periodElapsed * interestRatePeriod));
        uint256 periodsPerYear = 365 days / interestRatePeriod;
        uint256 periodsElapsed = (block.timestamp / interestRatePeriod) - (borrowTimeStamp / interestRatePeriod);
        uint256 expectedTotalDebt = (borrowAmount) +  ((borrowAmount * interestRateBps) / 10000 / periodsPerYear) * periodsElapsed;

        vm.startPrank(alice);
        assertEq(expectedTotalDebt, tlc.getTotalDebtAmount(alice));
        vm.stopPrank();
    }


    function testRepayZero() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 repayAmount = uint(0);
        _borrow(alice, uint(100_000e18), borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, repayAmount));
        vm.startPrank(alice);
        tlc.repay(0);
        vm.stopPrank();
    }

    function testRepayExceededBorrow() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 repayAmount = uint(61_000e18);
        _borrow(alice, uint(100_000e18), borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededBorrowedAmount.selector, alice, borrowAmount, repayAmount));
        vm.startPrank(alice);
        tlc.repay(repayAmount);
        vm.stopPrank();
    }

    function testRepaySuccess() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 repayAmount = uint(50_000e18);
        _borrow(alice, uint(100_000e18), borrowAmount);
         uint256 debtBalanceBefore = tlc.debtBalance();

        vm.startPrank(alice);
        debtToken.approve(address(tlc), repayAmount);
        tlc.repay(repayAmount);
        (, uint256 aliceDebtAmount, uint256 aliceCreatedAt) = tlc.positions(alice);
        vm.stopPrank();

        assertEq(borrowAmount - repayAmount,  aliceDebtAmount);
        assertEq(debtBalanceBefore + repayAmount, tlc.debtBalance());
        assertEq(block.timestamp, aliceCreatedAt);
    }

    function testWithdrawExceedCollateralAmount() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(100_001e18);
        _borrow(alice, collateralAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededCollateralAmonut.selector, alice, collateralAmount, withdrawalAmount));

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         vm.stopPrank();
    }

    function testWithdrawWillUnderCollaterlizeLoan() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(30_001e18);
        _borrow(alice, collateralAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.WillUnderCollaterlize.selector, alice, withdrawalAmount));

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         vm.stopPrank();
    }

    function testWithdrawalSuccess() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(10_000e18);
        _borrow(alice, collateralAmount, borrowAmount);

        uint256 collateralBalanceBefore = collateralToken.balanceOf(address(tlc));
        uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         (uint256 aliceCollateralAmount,,) = tlc.positions(alice);
         vm.stopPrank();

         assertEq(collateralBalanceBefore - withdrawalAmount, collateralToken.balanceOf(address(tlc)));
         assertEq(aliceCollateralAmount, collateralAmount - withdrawalAmount);
         assertEq(collateralToken.balanceOf(alice), aliceCollateralBalanceBefore + withdrawalAmount);
    }


    function testLiquidateSufficientCollateral() external {
        uint256 borrowAmount = uint(70_000e18);
        uint256 collateralAmount = uint(100_000e18);
        _borrow(alice, collateralAmount, borrowAmount);
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.OverCollaterilized.selector, alice));

        vm.prank(admin);
        tlc.liquidate(alice);
    }

    function testLiquidateUnderWaterPositionSucessfully() external {
        uint256 borrowAmount = uint(70_000e18);
        uint256 collateralAmount = uint(100_000e18);
        _borrow(alice, collateralAmount, borrowAmount);
        vm.warp(block.timestamp + 1180 days);
        uint256 totalDebt = tlc.getTotalDebtAmount(alice);
        assertTrue(tlc.getCurrentCollaterilizationRatio(alice) < minCollateralizationRatio);
        vm.prank(admin);
        tlc.liquidate(alice);

        (uint256 aliceCollateralAmount, uint256 aliceDebtAmount, uint256 aliceCreatedAt) = tlc.positions(alice);
        assertEq(uint256(0), aliceDebtAmount);
        assertEq(collateralAmount - (totalDebt * debtPrice / collateralPrice),  aliceCollateralAmount);
        assertEq(uint256(0), aliceCreatedAt);
        assertEq((totalDebt * debtPrice / collateralPrice), collateralToken.balanceOf(debtCollector));
    }
}
