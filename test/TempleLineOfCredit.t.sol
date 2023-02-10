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

    ERC20Mock public collateralToken;
    uint256 public collateralPrice;

    ERC20Mock public daiToken;
    uint256 public daiPrice;
    uint256 public daiMinCollateralizationRatio;
    uint256 public daiInterestRateBps;
    TempleLineOfCredit.TokenType public daiTokenType;


    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x2);
    address debtCollector = address(0x3);


    function setUp() public {

        collateralToken = new ERC20Mock("TempleToken", "Temple", admin, uint(500_000e18));
        collateralPrice = 970; // 0.97


        daiToken = new ERC20Mock("DAI Token", "DAI", admin, uint(500_000e18));
        daiPrice = 1000; // 1 USD
        daiMinCollateralizationRatio = 12000;
        daiTokenType = TempleLineOfCredit.TokenType.TRANSFER;
        daiInterestRateBps = 500; // 5%


        tlc = new TempleLineOfCredit(
            address(collateralToken),
            collateralPrice,
            debtCollector
        );

        tlc.addOperator(admin);
    }

    function testInitalization() public {
        assertEq(address(tlc.collateralToken()), address(collateralToken));
        assertEq(tlc.collateralPrice(), collateralPrice);
        assertEq(tlc.debtCollector(), debtCollector);
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

    function testSetCollateralPriceFailOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.setCollateralPrice(100);
    }

    function testSetCollateralPriceSuccess() public {
        uint256 collateralPrice = 970;
        vm.prank(admin);
        tlc.setCollateralPrice(collateralPrice);
        assertEq(tlc.collateralPrice(), collateralPrice);
    }

    function testSetDebtCollectorFailsOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.setDebtCollector(alice);
    }

    function testSetDebtCollectorSuccess() public { 
        vm.prank(admin);
        tlc.setDebtCollector(alice);
        assertEq(tlc.debtCollector(), alice);
    }

    function testAddDebtTokenFailsOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.addDebtToken(address(daiToken), daiTokenType, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
    }

    function testAddDebtTokenSuccess() public {
        vm.prank(admin);
        tlc.addDebtToken(address(daiToken), daiTokenType, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        (TempleLineOfCredit.TokenType tokenType, uint256 interestRateBps, uint256 tokenPrice, uint256 minCollateralizationRatio, bool allowed) = tlc.debtTokens(address(daiToken));
        assertEq(daiInterestRateBps, interestRateBps);
        assertEq(daiPrice, tokenPrice);
        assertEq(daiMinCollateralizationRatio, minCollateralizationRatio);
        assertEq(allowed, true);
    }

    function testRemoveDebtTokenFailsOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.removeDebtToken(address(daiToken));
    }

    function testRemoveDebtTokenFailsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.removeDebtToken(address(daiToken));
    }


    function testRemoveDebtTokenSuccess() public {
        vm.prank(admin);
        tlc.addDebtToken(address(daiToken), daiTokenType, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        vm.prank(admin);
        tlc.removeDebtToken(address(daiToken));
        (,,,, bool allowed) = tlc.debtTokens(address(daiToken));
        assertEq(allowed, false);
    }

    function testSetMinCollateralizationRatioFailsOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.setMinCollateralizationRatio(address(0x0), 0);
    }

    function testSetMinCollateralizationRatioUnsupported() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(0x0)));
        vm.prank(admin);
        tlc.setMinCollateralizationRatio(address(0x0), 0);
    }

    function testSetMinCollateralizationRatioSuccess() public {
        uint256 newCollaterilizationRatio = 140;
        vm.prank(admin);
        tlc.addDebtToken(address(daiToken), daiTokenType, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        vm.prank(admin);
        tlc.setMinCollateralizationRatio(address(daiToken), newCollaterilizationRatio);
        (,,, uint256 minCollateralizationRatio,) = tlc.debtTokens(address(daiToken));
        assertEq(minCollateralizationRatio, newCollaterilizationRatio);
    }

    function testDepositDebtExpectRevertOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.depositDebt(address(daiToken), alice, uint(100_000e18));
    }

    function testDepositDebtExpectFailUnSupprotedTokenAddress() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.depositDebt(address(daiToken), alice, uint(100_000e18));
    }

    function testDepositDebtExpectFailIncorrectTokenType() public {
        vm.prank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.MINT, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);

        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.depositDebt(address(daiToken), alice, uint(100_000e18));
    }

    function testdepositDebtSucess() public {
        vm.startPrank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        
        uint256 depositAmount = uint256(100_000e18);
        daiToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(address(daiToken), admin, depositAmount);
        assertEq(daiToken.balanceOf(address(tlc)), depositAmount);
    }

    function testRemoveDebtExpectRevertOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.removeDebt(address(daiToken), alice, uint(100_000e18));
    }

    function testRemoveDebtExpectFailUnSupprotedTokenAddress() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.removeDebt(address(daiToken), alice, uint(100_000e18));
    }


    function testRemoveDebtSucess() public {
        vm.startPrank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        
        uint256 depositAmount = uint256(100_000e18);
        daiToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(address(daiToken), admin, depositAmount);

        uint256 priorDebtBalance = daiToken.balanceOf(address(tlc));
        uint256 removeAmount = uint256(55_000e18);
        tlc.removeDebt(address(daiToken), admin, removeAmount);
        assertEq(daiToken.balanceOf(address(tlc)), priorDebtBalance - removeAmount);
    }


    function _initDeposit(uint256 depositAmount) internal {
        vm.startPrank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        daiToken.approve(address(tlc), depositAmount);
        tlc.depositDebt(address(daiToken), admin, depositAmount);
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

    function testBorrowCapacityCorrect() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 expectedMaxBorrowCapacity = uint(97_000e18) * uint(100) / uint(120);
        _postCollateral(alice, collateralAmount);
        assertEq(tlc.maxBorrowCapacity(address(daiToken), alice), expectedMaxBorrowCapacity);
    }

    function testBorrowInsufficientCollateral() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        uint256 maxBorrowCapacity = tlc.maxBorrowCapacity(address(daiToken), alice);
        uint256 borrowAmount = maxBorrowCapacity + uint(1);
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InsufficentCollateral.selector, address(daiToken), maxBorrowCapacity, borrowAmount));
        vm.prank(alice);

        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(daiToken);
        uint256[] memory borrowAmounts = new uint256[](1);
        borrowAmounts[0] = borrowAmount;

        tlc.borrow(debtTokens, borrowAmounts);
    }

    function testBorrowPasses() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        uint256 tlcDebtBalance = daiToken.balanceOf(address(tlc));
        uint256 maxBorrowCapacity = tlc.maxBorrowCapacity(address(daiToken), alice);
        
        vm.prank(alice);
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(daiToken);
        uint256[] memory borrowAmounts = new uint256[](1);
        borrowAmounts[0] = maxBorrowCapacity;
        tlc.borrow(debtTokens, borrowAmounts);

        (uint256 aliceCollateralAmount ) = tlc.positions(alice);
        TempleLineOfCredit.TokenPosition memory tp = tlc.getDebtAmount(address(daiToken), alice);

        assertEq(aliceCollateralAmount, collateralAmount);
        assertEq(tp.debtAmount, maxBorrowCapacity);
        assertEq(tp.createdAt, block.timestamp);
        assertEq(daiToken.balanceOf(alice), maxBorrowCapacity);
    }

    // function _borrow(address _account, uint256 collateralAmount, uint256 borrowAmount) internal {
    //     _postCollateral(_account, collateralAmount);
    //     vm.prank(_account);
    //     tlc.borrow(borrowAmount);
    // }

    // function testBorrowAccuresInterest(uint32 secondsElapsed) external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     _borrow(alice, uint(100_000e18), borrowAmount);

    //     uint256 borrowTimeStamp = block.timestamp;
       
    //     vm.warp(block.timestamp +  secondsElapsed);
    //     uint256 secondsElapsed = block.timestamp  - borrowTimeStamp;
    //     uint256 expectedTotalDebt = (borrowAmount) +  ((borrowAmount * interestRateBps * secondsElapsed) / 10000 / 365 days);

    //     vm.startPrank(alice);
    //     assertEq(expectedTotalDebt, tlc.getTotalDebtAmount(alice));
    //     vm.stopPrank();
    // }


    // function testRepayZero() external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 repayAmount = uint(0);
    //     _borrow(alice, uint(100_000e18), borrowAmount);
    //      vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, repayAmount));
    //     vm.startPrank(alice);
    //     tlc.repay(0);
    //     vm.stopPrank();
    // }

    // function testRepayExceededBorrow() external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 repayAmount = uint(61_000e18);
    //     _borrow(alice, uint(100_000e18), borrowAmount);
    //      vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededBorrowedAmount.selector, alice, borrowAmount, repayAmount));
    //     vm.startPrank(alice);
    //     tlc.repay(repayAmount);
    //     vm.stopPrank();
    // }

    // function testRepaySuccess(uint256 repayAmount) external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 repayAmount = uint(50_000e18);
    //     _borrow(alice, uint(100_000e18), borrowAmount);
    //      uint256 debtBalanceBefore = tlc.debtBalance();

    //     vm.startPrank(alice);
    //     debtToken.approve(address(tlc), repayAmount);
    //     tlc.repay(repayAmount);
    //     (, uint256 aliceDebtAmount, uint256 aliceCreatedAt) = tlc.positions(alice);
    //     vm.stopPrank();

    //     assertEq(borrowAmount - repayAmount,  aliceDebtAmount);
    //     assertEq(debtBalanceBefore + repayAmount, tlc.debtBalance());
    //     assertEq(block.timestamp, aliceCreatedAt);
    // }

    // function testWithdrawExceedCollateralAmount() external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 collateralAmount = uint(100_000e18);
    //     uint256 withdrawalAmount = uint(100_001e18);
    //     _borrow(alice, collateralAmount, borrowAmount);
    //      vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededCollateralAmonut.selector, alice, collateralAmount, withdrawalAmount));

    //      vm.startPrank(alice);
    //      tlc.withdrawCollateral(withdrawalAmount);
    //      vm.stopPrank();
    // }

    // function testWithdrawWillUnderCollaterlizeLoan() external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 collateralAmount = uint(100_000e18);
    //     uint256 withdrawalAmount = uint(30_001e18);
    //     _borrow(alice, collateralAmount, borrowAmount);
    //      vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.WillUnderCollaterlize.selector, alice, withdrawalAmount));

    //      vm.startPrank(alice);
    //      tlc.withdrawCollateral(withdrawalAmount);
    //      vm.stopPrank();
    // }

    // function testWithdrawalSuccess() external {
    //     uint256 borrowAmount = uint(60_000e18);
    //     uint256 collateralAmount = uint(100_000e18);
    //     uint256 withdrawalAmount = uint(10_000e18);
    //     _borrow(alice, collateralAmount, borrowAmount);

    //     uint256 collateralBalanceBefore = collateralToken.balanceOf(address(tlc));
    //     uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);

    //      vm.startPrank(alice);
    //      tlc.withdrawCollateral(withdrawalAmount);
    //      (uint256 aliceCollateralAmount,,) = tlc.positions(alice);
    //      vm.stopPrank();

    //      assertEq(collateralBalanceBefore - withdrawalAmount, collateralToken.balanceOf(address(tlc)));
    //      assertEq(aliceCollateralAmount, collateralAmount - withdrawalAmount);
    //      assertEq(collateralToken.balanceOf(alice), aliceCollateralBalanceBefore + withdrawalAmount);
    // }


    // function testLiquidateSufficientCollateral() external {
    //     uint256 borrowAmount = uint(70_000e18);
    //     uint256 collateralAmount = uint(100_000e18);
    //     _borrow(alice, collateralAmount, borrowAmount);
    //     vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.OverCollaterilized.selector, alice));

    //     vm.prank(admin);
    //     tlc.liquidate(alice);
    // }

    // function testLiquidateUnderWaterPositionSucessfully() external {
    //     uint256 borrowAmount = uint(70_000e18);
    //     uint256 collateralAmount = uint(100_000e18);
    //     _borrow(alice, collateralAmount, borrowAmount);
    //     vm.warp(block.timestamp + 1180 days);
    //     uint256 totalDebt = tlc.getTotalDebtAmount(alice);
    //     assertTrue(tlc.getCurrentCollaterilizationRatio(alice) < minCollateralizationRatio);
    //     vm.prank(admin);
    //     tlc.liquidate(alice);

    //     (uint256 aliceCollateralAmount, uint256 aliceDebtAmount, uint256 aliceCreatedAt) = tlc.positions(alice);
    //     assertEq(uint256(0), aliceDebtAmount);
    //     assertEq(collateralAmount - (totalDebt * debtPrice / collateralPrice),  aliceCollateralAmount);
    //     assertEq(uint256(0), aliceCreatedAt);
    //     assertEq((totalDebt * debtPrice / collateralPrice), collateralToken.balanceOf(debtCollector));
    // }
}
