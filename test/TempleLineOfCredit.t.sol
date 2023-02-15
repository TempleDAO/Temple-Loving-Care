// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import "../src/TempleLineOfCredit.sol";
import "../src/mocks/OudRedeemer.sol";
import "../src/common/access/Operators.sol";

contract TempleLineOfCreditTest is Test {

    TempleLineOfCredit public tlc;

    uint256 public interestRateBps;
    uint256 public minCollateralizationRatio;

    ERC20Mock public collateralToken;
    TempleLineOfCredit.TokenPrice public collateralPrice;

    ERC20Mock public daiToken;
    TempleLineOfCredit.TokenPrice public daiPrice;
    uint256 public daiMinCollateralizationRatio;
    uint256 public daiInterestRateBps;
    TempleLineOfCredit.TokenType public daiTokenType;


    ERC20Mock public oudToken;
    TempleLineOfCredit.TokenPrice public oudPrice;
    uint256 public oudMinCollateralizationRatio;
    uint256 public oudInterestRateBps;
    TempleLineOfCredit.TokenType public oudTokenType;



    OudRedeemer public oudRedeemer;


    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x2);
    address debtCollector = address(0x3);


    function setUp() public {

        collateralToken = new ERC20Mock("TempleToken", "Temple", admin, uint(500_000e18));
        // collateralPrice = 9700; // 0.97
        collateralPrice = TempleLineOfCredit.TokenPrice.TPI; // 0.97


        daiToken = new ERC20Mock("DAI Token", "DAI", admin, uint(500_000e18));
        daiPrice = TempleLineOfCredit.TokenPrice.STABLE; // 1 USD
        daiMinCollateralizationRatio = 12000;
        daiTokenType = TempleLineOfCredit.TokenType.TRANSFER;
        daiInterestRateBps = 500; // 5%

        oudRedeemer = new OudRedeemer();

        tlc = new TempleLineOfCredit(
            address(collateralToken),
            collateralPrice,
            debtCollector,
            address(oudRedeemer)
        );


        oudToken = new ERC20Mock("OUD Token", "OUD", address(tlc), uint(500_000e18));
        oudPrice = TempleLineOfCredit.TokenPrice.TPI;
        oudMinCollateralizationRatio = 11000; 
        oudTokenType = TempleLineOfCredit.TokenType.MINT;
        oudInterestRateBps = 500; // 5%

        tlc.addOperator(admin);
    }

    function testInitalization() public {
        assertEq(address(tlc.collateralToken()), address(collateralToken));
        assertEq(uint(tlc.collateralPrice()), uint(collateralPrice));
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
        tlc.setCollateralPrice(TempleLineOfCredit.TokenPrice.STABLE);
    }

    function testSetCollateralPriceSuccess() public {
        TempleLineOfCredit.TokenPrice collateralPrice = TempleLineOfCredit.TokenPrice.STABLE;
        vm.prank(admin);
        tlc.setCollateralPrice(collateralPrice);
        assertEq(uint(tlc.collateralPrice()), uint(collateralPrice));
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
        (TempleLineOfCredit.TokenType tokenType, uint256 interestRateBps, TempleLineOfCredit.TokenPrice tokenPrice, uint256 minCollateralizationRatio, bool allowed) = tlc.debtTokens(address(daiToken));
        assertEq(daiInterestRateBps, interestRateBps);
        assertEq(uint(daiPrice), uint(tokenPrice));
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

    function testDepositExpectRevertOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.depositReserve(address(daiToken), alice, uint(100_000e18));
    }

    function testDepositReserveInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, 0));
        vm.prank(admin);
        tlc.depositReserve(address(daiToken), alice, 0);
    }

    function testDepositReserveExpectFailUnSupprotedTokenAddress() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.depositReserve(address(daiToken), alice, uint(100_000e18));
    }

    function testDepositDebtExpectFailIncorrectTokenType() public {
        vm.prank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.MINT, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);

        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.depositReserve(address(daiToken), alice, uint(100_000e18));
    }

    function testDepositDebtSucess() public {
        vm.startPrank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        
        uint256 depositAmount = uint256(100_000e18);
        daiToken.approve(address(tlc), depositAmount);
        tlc.depositReserve(address(daiToken), admin, depositAmount);
        assertEq(daiToken.balanceOf(address(tlc)), depositAmount);
    }

    function testRemoveDebtInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, 0));
        vm.prank(admin);
        tlc.removeReserve(address(daiToken), alice, 0);
    }

    function testRemoveReserveExpectRevertOnlyOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.removeReserve(address(daiToken), alice, uint(100_000e18));
    }

    function testRemoveReserveExpectFailUnSupprotedTokenAddress() public {
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.Unsupported.selector, address(daiToken)));
        vm.prank(admin);
        tlc.removeReserve(address(daiToken), alice, uint(100_000e18));
    }


    function testRemoveReserveSucess() public {
        vm.startPrank(admin);
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        
        uint256 depositAmount = uint256(100_000e18);
        daiToken.approve(address(tlc), depositAmount);
        tlc.depositReserve(address(daiToken), admin, depositAmount);

        uint256 priorDebtBalance = daiToken.balanceOf(address(tlc));
        uint256 removeAmount = uint256(55_000e18);
        tlc.removeReserve(address(daiToken), admin, removeAmount);
        assertEq(daiToken.balanceOf(address(tlc)), priorDebtBalance - removeAmount);
    }


    function _initDeposit(uint256 daiDepositAmount) internal {
        vm.startPrank(admin);

        // deposit DAI
        tlc.addDebtToken(address(daiToken), TempleLineOfCredit.TokenType.TRANSFER, daiInterestRateBps, daiPrice, daiMinCollateralizationRatio);
        daiToken.approve(address(tlc), daiDepositAmount);
        tlc.depositReserve(address(daiToken), admin, daiDepositAmount);

        // support OUD
        tlc.addDebtToken(address(oudToken), TempleLineOfCredit.TokenType.MINT, oudInterestRateBps, oudPrice, oudMinCollateralizationRatio);
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


    function testBorrowFailInvalidArrayLength() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        
        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidArrayLength.selector));
        vm.prank(alice);
        address[] memory debtTokens = new address[](2);
        debtTokens[0] = address(daiToken);
        debtTokens[1] = address(oudToken);
        uint256[] memory borrowAmounts = new uint256[](1);
        borrowAmounts[0] = 100_100;
        tlc.borrow(debtTokens, borrowAmounts);
    }

    function testBorrowTwoAssetsSucess() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, collateralAmount);
        uint256 tlcDebtBalance = daiToken.balanceOf(address(tlc));
        uint256 maxBorrowCapacityDAI = tlc.maxBorrowCapacity(address(daiToken), alice);
        uint256 maxBorrowCapacityOUD = tlc.maxBorrowCapacity(address(oudToken), alice);
        
        vm.prank(alice);
        address[] memory debtTokens = new address[](2);
        debtTokens[0] = address(daiToken);
        debtTokens[1] = address(oudToken);
        uint256[] memory borrowAmounts = new uint256[](2);
        borrowAmounts[0] = maxBorrowCapacityDAI;
        borrowAmounts[1] = maxBorrowCapacityOUD;
        
        tlc.borrow(debtTokens, borrowAmounts);

        (uint256 aliceCollateralAmount ) = tlc.positions(alice);
        
        TempleLineOfCredit.TokenPosition memory tpDAI = tlc.getDebtAmount(address(daiToken), alice);
        assertEq(aliceCollateralAmount, collateralAmount);
        assertEq(tpDAI.debtAmount, maxBorrowCapacityDAI);
        assertEq(tpDAI.lastUpdatedAt, block.timestamp);
        assertEq(daiToken.balanceOf(alice), maxBorrowCapacityDAI);

        TempleLineOfCredit.TokenPosition memory tpOUD = tlc.getDebtAmount(address(oudToken), alice);
        assertEq(tpOUD.debtAmount, maxBorrowCapacityOUD);
        assertEq(tpOUD.lastUpdatedAt, block.timestamp);
        assertEq(oudToken.balanceOf(alice), maxBorrowCapacityOUD);
    }


    function testBorrowAccuresInterest(uint32 secondsElapsed) external {
        uint256 borrowAmount = uint(60_000e18);
        _borrow(alice, uint(100_000e18), borrowAmount, borrowAmount);

        uint256 borrowTimeStamp = block.timestamp;
       
        vm.warp(block.timestamp +  secondsElapsed);
        uint256 secondsElapsed = block.timestamp  - borrowTimeStamp;
        uint256 expectedTotalDebtDAI = (borrowAmount) +  ((borrowAmount * daiInterestRateBps * secondsElapsed) / 10000 / 365 days);
        uint256 expectedTotalDebtOUD = (borrowAmount) +  ((borrowAmount * oudInterestRateBps * secondsElapsed) / 10000 / 365 days);


        vm.startPrank(alice);
        assertEq(expectedTotalDebtDAI, tlc.getTotalDebtAmount(address(daiToken), alice));
        assertEq(expectedTotalDebtOUD, tlc.getTotalDebtAmount(address(oudToken), alice));
        vm.stopPrank();
    }

    function _borrow(address _account, uint256 collateralAmount, uint256 daiBorrowAmount, uint256 oudBorrowAmount) internal {
        _postCollateral(_account, collateralAmount);
        vm.prank(_account);
        address[] memory debtTokens = new address[](2);
        debtTokens[0] = address(daiToken);
        debtTokens[1] = address(oudToken);
        uint256[] memory borrowAmounts = new uint256[](2);
        borrowAmounts[0] = daiBorrowAmount;
        borrowAmounts[1] = oudBorrowAmount;
        
        tlc.borrow(debtTokens, borrowAmounts);
    }


    function testBorrowAlreadyBorrowedSucess() external {
        uint256 borrowDAIAmountFirst = uint(30_000e18);
        uint256 borrowOUDAmountFirst = uint(20_000e18);
        
        _borrow(alice, uint(100_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);
        
        uint secondsElapsed = 200 days;
        vm.warp(block.timestamp +  secondsElapsed);

        uint256 borrowDAIAmountSecond = uint(30_000e18);
        uint256 borrowOUDAmountSecond = uint(20_000e18);

        _borrow(alice, uint(100_000e18), borrowDAIAmountSecond, borrowOUDAmountSecond);


        TempleLineOfCredit.TokenPosition memory tpDAI = tlc.getDebtAmount(address(daiToken), alice);
                                   /// First Principle                                  accured principle                                       second borrow amount       
        assertEq(tpDAI.debtAmount, borrowDAIAmountFirst + ((borrowDAIAmountFirst * daiInterestRateBps * secondsElapsed)  / 10000 / 365 days) + borrowDAIAmountSecond );
        assertEq(tpDAI.lastUpdatedAt, block.timestamp);
        assertEq(daiToken.balanceOf(alice), borrowDAIAmountFirst + borrowDAIAmountSecond);



        TempleLineOfCredit.TokenPosition memory tpOUD = tlc.getDebtAmount(address(oudToken), alice);
                                   /// First Principle                                  accured principle                                       second borrow amount       
        assertEq(tpOUD.debtAmount, borrowOUDAmountFirst + ((borrowOUDAmountFirst * oudInterestRateBps * secondsElapsed)  / 10000 / 365 days) + borrowOUDAmountSecond );
        assertEq(tpOUD.lastUpdatedAt, block.timestamp);
        assertEq(oudToken.balanceOf(alice), borrowOUDAmountFirst + borrowOUDAmountSecond);
    }

    function testRepayZero() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 repayAmount = uint(0);
        _borrow(alice, uint(100_000e18), borrowAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.InvalidAmount.selector, repayAmount));
        vm.startPrank(alice);
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(daiToken);
        uint256[] memory repayAmounts = new uint256[](1);
        repayAmounts[0] = repayAmount;
        tlc.repay(debtTokens, repayAmounts);
        vm.stopPrank();
    }

    function testRepayExceededBorrow() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 repayAmount = uint(61_000e18);
        _borrow(alice, uint(100_000e18), borrowAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededBorrowedAmount.selector, alice, borrowAmount, repayAmount));
        vm.startPrank(alice);
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(daiToken);
        uint256[] memory repayAmounts = new uint256[](1);
        repayAmounts[0] = repayAmount;
        tlc.repay(debtTokens, repayAmounts);
        vm.stopPrank();
    }

    function testRepaySuccessMultipleTokens() external {
        uint256 borrowDAIAmount = uint(60_000e18);
        uint256 borrowOUDAmount = uint(60_000e18);
        uint256 repayDAIAmount = uint(50_000e18);
        uint256 repayOUDAmount = uint(50_000e18);
        
        _borrow(alice, uint(100_000e18), borrowDAIAmount, borrowOUDAmount);

        vm.startPrank(alice);
        daiToken.approve(address(tlc), repayDAIAmount);
        address[] memory debtTokens = new address[](2);
        debtTokens[0] = address(daiToken);
        debtTokens[1] = address(oudToken);
        uint256[] memory repayAmounts = new uint256[](2);
        repayAmounts[0] = repayDAIAmount;
        repayAmounts[1] = repayOUDAmount;
        tlc.repay(debtTokens, repayAmounts);
        vm.stopPrank();

        TempleLineOfCredit.TokenPosition memory tpDAI = tlc.getDebtAmount(address(daiToken), alice);
        assertEq(borrowDAIAmount - repayDAIAmount,  tpDAI.debtAmount);
        assertEq(block.timestamp, tpDAI.lastUpdatedAt);

        TempleLineOfCredit.TokenPosition memory tpOUD = tlc.getDebtAmount(address(oudToken), alice);
        assertEq(borrowOUDAmount - repayOUDAmount, tpOUD.debtAmount);
        assertEq(block.timestamp, tpOUD.lastUpdatedAt);
        
    }

    function testWithdrawExceedCollateralAmount() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(100_001e18);
        _borrow(alice, collateralAmount, borrowAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.ExceededCollateralAmonut.selector, alice, collateralAmount, withdrawalAmount));

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         vm.stopPrank();
    }

    function testWithdrawWillUnderCollaterlizeLoan() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(30_001e18);
        _borrow(alice, collateralAmount, borrowAmount, borrowAmount);
         vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.WillUnderCollaterlize.selector, alice, withdrawalAmount));

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         vm.stopPrank();
    }

    function testWithdrawalSuccess() external {
        uint256 borrowAmount = uint(60_000e18);
        uint256 collateralAmount = uint(100_000e18);
        uint256 withdrawalAmount = uint(10_000e18);
        _borrow(alice, collateralAmount, borrowAmount, borrowAmount);

        uint256 collateralBalanceBefore = collateralToken.balanceOf(address(tlc));
        uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);

         vm.startPrank(alice);
         tlc.withdrawCollateral(withdrawalAmount);
         (uint256 aliceCollateralAmount) = tlc.positions(alice);
         vm.stopPrank();

         assertEq(collateralBalanceBefore - withdrawalAmount, collateralToken.balanceOf(address(tlc)));
         assertEq(aliceCollateralAmount, collateralAmount - withdrawalAmount);
         assertEq(collateralToken.balanceOf(alice), aliceCollateralBalanceBefore + withdrawalAmount);
    }

    function testLiquidateSufficientCollateral() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 borrowAmount = uint(30_000e18);
        _borrow(alice, collateralAmount, borrowAmount, borrowAmount);

        vm.expectRevert(abi.encodeWithSelector(TempleLineOfCredit.OverCollaterilized.selector, alice));

        vm.prank(admin);
        tlc.liquidate(alice, address(daiToken));
    }

    function testLiquidateUnderWaterPositionSucessfully() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 borrowDAIAmount = uint(70_000e18);
        uint256 borrowOUDAmount = uint(30_000e18);
        _borrow(alice, collateralAmount, borrowDAIAmount, borrowOUDAmount);
        vm.warp(block.timestamp + 1800 days);
        
        uint256 totalDebt = tlc.getTotalDebtAmount(address(daiToken), alice);
        assertTrue(tlc.getCurrentCollaterilizationRatio(address(daiToken), alice) < daiMinCollateralizationRatio); // Position in bad debt
        assertFalse(tlc.getCurrentCollaterilizationRatio(address(oudToken), alice) < oudMinCollateralizationRatio); // Position in good debt
        vm.prank(admin);
        tlc.liquidate(alice, address(daiToken));

        (uint256 aliceCollateralAmount) = tlc.positions(alice);
        (uint256 debtTokenPrice, uint256 debtPrecision) = tlc.getTokenPrice(daiPrice);
        (uint256 collateralTokenPrice, uint256 collateralPrecision) = tlc.getTokenPrice(collateralPrice);
        assertEq(collateralAmount - (totalDebt * debtTokenPrice * collateralPrecision  / collateralTokenPrice / debtPrecision),  aliceCollateralAmount);

        TempleLineOfCredit.TokenPosition memory tpDAI = tlc.getDebtAmount(address(daiToken), alice);
        assertEq(0,  tpDAI.debtAmount);
        assertEq(block.timestamp, tpDAI.lastUpdatedAt);

        TempleLineOfCredit.TokenPosition memory tpOUD = tlc.getDebtAmount(address(oudToken), alice);
        assertEq(0, tpOUD.debtAmount);
        assertEq(block.timestamp, tpOUD.lastUpdatedAt);
    }

    function testLiquidateUnderWaterPositionCollateralExceedAmountThatCanBeSiezedSucessfully() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 borrowDAIAmount = uint(70_000e18);
        uint256 borrowOUDAmount = uint(30_000e18);
        _borrow(alice, collateralAmount, borrowDAIAmount, borrowOUDAmount);
        vm.warp(block.timestamp + 18000 days);
        
        uint256 totalDebt = tlc.getTotalDebtAmount(address(daiToken), alice);
        assertTrue(tlc.getCurrentCollaterilizationRatio(address(daiToken), alice) < daiMinCollateralizationRatio); // Position in bad debt
        assertTrue(tlc.getCurrentCollaterilizationRatio(address(oudToken), alice) < oudMinCollateralizationRatio); // Position in good debt
        vm.prank(admin);
        tlc.liquidate(alice, address(daiToken));

        (uint256 aliceCollateralAmount) = tlc.positions(alice);
        assertEq(0,  aliceCollateralAmount);

        TempleLineOfCredit.TokenPosition memory tpDAI = tlc.getDebtAmount(address(daiToken), alice);
        assertEq(0,  tpDAI.debtAmount);
        assertEq(block.timestamp, tpDAI.lastUpdatedAt);

        TempleLineOfCredit.TokenPosition memory tpOUD = tlc.getDebtAmount(address(oudToken), alice);
        assertEq(0, tpOUD.debtAmount);
        assertEq(block.timestamp, tpOUD.lastUpdatedAt);
    }
}
