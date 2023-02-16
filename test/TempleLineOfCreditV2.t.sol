// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import "../src/TempleLineOfCreditV2.sol";
import "../src/LinearInterestRateModel.sol";
import "../src/interfaces/ITempleLineOfCreditErrors.sol";
import "../src/interfaces/ITempleLineOfCreditEvents.sol";
import "../src/interfaces/ITempleLineOfCreditTypes.sol";
import "../src/mocks/OudRedeemer.sol";
import "../src/common/access/Operators.sol";

contract TempleLineOfCreditV2Test is 
    Test,
    ITempleLineOfCreditErrors,
    ITempleLineOfCreditEvents,
    ITempleLineOfCreditTypes
{

    TempleLineOfCreditV2 public tlc;
    ERC20Mock templeToken;
    TokenPrice templePrice;

    ERC20Mock daiToken;
    LinearInterestRateModel daiInterestRateModel;
    TokenPrice daiPrice;
    uint256 daiMinCollateralizationRatio;
    

    ERC20Mock oudToken;
    LinearInterestRateModel oudInterestRateModel;
    TokenPrice oudPrice;
    uint256 oudMinCollateralizationRatio;

    OudRedeemer public oudRedeemer;

    address admin = address(0x1);
    address alice = address (0x2);


    function setUp() public {

        templeToken = new ERC20Mock("TempleToken", "Temple", admin, uint(500_000e18));
        templePrice = TokenPrice.TPI; // 0.97


        daiToken = new ERC20Mock("DAI Token", "DAI", admin, uint(500_000e18));
        // uint256 _baseInterestRate, uint256 _maxInterestRate, uint _kinkUtilization, uint _kinkInterestRateBps) {
        daiInterestRateModel = new LinearInterestRateModel(
             5e18 / 100, // 5% interest rate
             20e18 / 100, // 20% percent interest rate
             9e18 / 10,  //  90% utilization
             10e18 / 100 // 10% percent interest rate
        );


        daiPrice = TokenPrice.STABLE; // 1 USD
        daiMinCollateralizationRatio = 12000;

        oudToken = new ERC20Mock("OUD Token", "OUD", admin, uint(500_000e18));
        oudInterestRateModel = new LinearInterestRateModel(
             5e18 / 100, // 5% interest rate
             5e18 / 100, // 20% percent interest rate
             10e18 / 10,  //  90% utilization
             5e18 / 100 // 10% percent interest rate
        ); // Set up a flat interest rate model for OUD
        oudPrice = TokenPrice.TPI;
        oudMinCollateralizationRatio = 11000; 


        oudRedeemer = new OudRedeemer();

        tlc = new TempleLineOfCreditV2(
            address(templeToken),
            templePrice,
            address(daiToken),
            address(daiInterestRateModel),
            daiPrice,
            daiMinCollateralizationRatio,
            address(oudToken),
            address(oudInterestRateModel),
            oudPrice,
            oudMinCollateralizationRatio,
            address(oudRedeemer)
        );

        tlc.addOperator(admin);
    }

    function testInitalization() public {
        assertEq(address(tlc.templeToken()), address(templeToken));
        assertEq(uint256(tlc.templePrice()), uint256(templePrice));

        (address _daiTokenAddress, TokenPrice _daiTokenPrice, uint256 _daiMCR, , , , , ) = tlc.dai();
        assertEq(_daiTokenAddress, address(daiToken));
        assertEq(uint256(_daiTokenPrice), uint256(daiPrice));
        assertEq(_daiMCR, daiMinCollateralizationRatio);


        (address _oudTokenAddress, TokenPrice _oudTokenPrice, uint256 _oudMCR, , , , , ) = tlc.oud();
        assertEq(_oudTokenAddress, address(oudToken));
        assertEq(uint256(_oudTokenPrice), uint256(oudPrice));
        assertEq(_oudMCR, oudMinCollateralizationRatio);

        assertEq(address(tlc.oudRedeemer()), address(oudRedeemer));
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

    function testSetInterestRateFailsNotOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.setInterestRateModel(address(daiToken), address(0x0));
    }

     function testSetInterestRateFailsUnsupported() public {
        vm.expectRevert(abi.encodeWithSelector(Unsupported.selector, address(0x0)));

        vm.prank(admin);
        tlc.setInterestRateModel(address(0x0), address(0x0));
    }

    function testSetInterestRateSuccess() public {

        vm.prank(admin);
        tlc.setInterestRateModel(address(daiToken), address(0x1234));

        (,,,,,,address newInterestRateModel,) = tlc.dai();
        assertEq(address(0x1234), newInterestRateModel);
    }

    function testDepositDaiReserveFailNotOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operators.OnlyOperators.selector, address(this)));
        tlc.depositDAIReserve(alice, 0);
    }

    function testDepositDaiReserveFailInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, 0));
        vm.prank(admin);
        tlc.depositDAIReserve(alice, 0);
    }

    function testDepositDaiReserveSuccess() public {
        tlc.addOperator(admin);
        vm.startPrank(admin);
        uint256 depositAmount = 10000;
        deal(address(daiToken), admin, depositAmount);
        daiToken.approve(address(tlc), depositAmount);


        vm.expectEmit(true, true, true, true, address(tlc));
        emit DepositReserve(address(daiToken), depositAmount);

        tlc.depositDAIReserve(admin, depositAmount);
        vm.stopPrank();


        (,,,uint256 totalReserve, , , , ) = tlc.dai();
        assertEq(totalReserve, depositAmount);
        assertEq(daiToken.balanceOf(admin), 0);
    }

    function testPostCollateralZeroBalanceRevert() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, uint(0)));
        vm.prank(alice);
        uint256 collateralAmount = uint(0);
        tlc.postCollateral(collateralAmount);
    }

    function testPostCollateralPasses() external {
        uint256 collateralAmount = uint(200_000e18);
        deal(address(templeToken), alice, collateralAmount);
        vm.startPrank(alice);
        templeToken.approve(address(tlc), collateralAmount);

        // assert emit 
        vm.expectEmit(true, true, true, true, address(tlc));
        emit PostCollateral(alice, collateralAmount);

        tlc.postCollateral(collateralAmount);
        assertEq(templeToken.balanceOf(address(tlc)), collateralAmount);
        assertEq(tlc.collateralPosted(alice), collateralAmount);


        // Post collateral again
        uint256 newCollateralAmount = uint(100_000e18);
        deal(address(templeToken), alice, newCollateralAmount);
        templeToken.approve(address(tlc), newCollateralAmount);

        // assert emit 
        vm.expectEmit(true, true, true, true, address(tlc));
        emit PostCollateral(alice, newCollateralAmount);

        tlc.postCollateral(newCollateralAmount);
        assertEq(templeToken.balanceOf(address(tlc)), collateralAmount + newCollateralAmount);
        assertEq(tlc.collateralPosted(alice), collateralAmount + newCollateralAmount);

        vm.stopPrank();
    }

    function _initDeposit(uint256 daiDepositAmount) internal {
        vm.startPrank(admin);
        daiToken.approve(address(tlc), daiDepositAmount);
        tlc.depositDAIReserve(admin, daiDepositAmount);
        vm.stopPrank();
    }

    function _postCollateral(address user, uint256 reserveAmount, uint256 collateralAmount) internal {
        _initDeposit(reserveAmount);
        deal(address(templeToken), user, collateralAmount);
        vm.startPrank(user);
        templeToken.approve(address(tlc), collateralAmount);
        tlc.postCollateral(collateralAmount);
        vm.stopPrank();
    }


    function testBorrowCapacityCorrect() external {
        uint256 collateralAmount = uint(100_000e18);
        uint256 expectedMaxBorrowCapacity = uint(97_000e18) * uint(100) / uint(120);
        _postCollateral(alice, uint(100_000e18), collateralAmount);
        assertEq(tlc.maxBorrowCapacity(address(daiToken), alice), expectedMaxBorrowCapacity);
    }

    function testBorrowInsufficientCollateral() external {
        uint256 collateralAmount = uint(100_000e18);
        _postCollateral(alice, uint(100_000e18), collateralAmount);
        uint256 maxBorrowCapacity = tlc.maxBorrowCapacity(address(daiToken), alice);
        uint256 borrowAmount = maxBorrowCapacity + uint(1);
        vm.expectRevert(abi.encodeWithSelector(InsufficentCollateral.selector, maxBorrowCapacity, borrowAmount));

        vm.startPrank(alice);
        tlc.borrow(borrowAmount, 0);
        vm.stopPrank();
    }

    function testBorrowDaiAndOudSucess() external {
        _postCollateral(alice, uint(100_000e18), uint(100_000e18));

        uint256 borrowDAIAmount;
        uint256 borrowOUDAmount;
        uint256 aliceDaiBalancePrior;
        uint256 aliceOudBalancePrior;

        borrowDAIAmount = tlc.maxBorrowCapacity(address(daiToken), alice);
        borrowOUDAmount = tlc.maxBorrowCapacity(address(oudToken), alice); 

        aliceDaiBalancePrior = daiToken.balanceOf(alice);
        aliceOudBalancePrior = oudToken.balanceOf(alice);

        uint256 totalDaiBorrowPrior;
        uint256 totalDaiSharesPrior;
        uint256 userSharesDaiPrior;
        uint256 totalOUDBorrowPrior;
        uint256 totalOUDSharesPrior;
        uint256 userSharesOUDPrior;

        (,,,,totalDaiBorrowPrior, totalDaiSharesPrior, , ) = tlc.dai();
        userSharesDaiPrior = tlc.userShares(alice, address(daiToken));

        (,,,, totalOUDBorrowPrior, totalOUDSharesPrior, , ) = tlc.oud();
        userSharesOUDPrior = tlc.userShares(alice, address(oudToken));

        vm.startPrank(alice);
        // assert emit 
        vm.expectEmit(true, true, true, true, address(tlc));
        emit Borrow(alice, address(daiToken), borrowDAIAmount / 2);

        vm.expectEmit(true, true, true, true, address(tlc));
        emit Borrow(alice, address(oudToken), borrowOUDAmount / 2);
        
        tlc.borrow(borrowDAIAmount/2 , borrowOUDAmount/2);
        vm.stopPrank();

        assertEq(daiToken.balanceOf(alice), aliceDaiBalancePrior + (borrowDAIAmount / 2));
        assertEq(oudToken.balanceOf(alice), aliceOudBalancePrior + (borrowOUDAmount / 2));

        uint256 totalBorrowExpected;
        uint256 totalSharesExpected; 
        uint256 newSharesExpected;
        
        // Assert DAI variables
        (,,,,  totalBorrowExpected, totalSharesExpected, , ) = tlc.dai();
        newSharesExpected = borrowDAIAmount / 2; // First time borrowing
        assertEq(totalBorrowExpected, totalDaiBorrowPrior + borrowDAIAmount / 2);
        assertEq(totalSharesExpected, totalDaiSharesPrior + newSharesExpected);
        assertEq(newSharesExpected, userSharesDaiPrior + newSharesExpected);
        

        // Assert OUD variables
        (,,,,  totalBorrowExpected, totalSharesExpected, , ) = tlc.oud();
        newSharesExpected = borrowOUDAmount / 2; // First time borrowing
        assertEq(totalBorrowExpected, totalOUDBorrowPrior + borrowOUDAmount / 2);
        assertEq(totalSharesExpected, totalOUDSharesPrior + newSharesExpected);
        assertEq(newSharesExpected, userSharesOUDPrior + newSharesExpected);
    

        (,,,,totalDaiBorrowPrior, totalDaiSharesPrior, , ) = tlc.dai();
        userSharesDaiPrior = tlc.userShares(alice, address(daiToken));
            
        (,,,, totalOUDBorrowPrior, totalOUDSharesPrior, , ) = tlc.oud();
        userSharesOUDPrior = tlc.userShares(alice, address(oudToken));

            
        vm.startPrank(alice);
                
        // Assert emits
        vm.expectEmit(true, true, true, true, address(tlc));
        emit InterestRateUpdate(address(daiToken), daiInterestRateModel.getBorrowRate(totalDaiBorrowPrior, uint(100_000e18)));

        vm.expectEmit(true, true, true, true, address(tlc));
        emit InterestRateUpdate(address(oudToken), oudInterestRateModel.getBorrowRate(totalOUDBorrowPrior, uint(100_000e18)));

        tlc.borrow(borrowDAIAmount / 2, borrowOUDAmount / 2);
        vm.stopPrank();

        assertEq(daiToken.balanceOf(alice), aliceDaiBalancePrior + 2 * (borrowDAIAmount / 2));
        assertEq(oudToken.balanceOf(alice), aliceOudBalancePrior + 2 * (borrowOUDAmount / 2));

        // Assert DAI variables
        (,,,,  totalBorrowExpected, totalSharesExpected, , ) = tlc.dai();
     
        newSharesExpected = (borrowDAIAmount / 2) * totalDaiSharesPrior / totalDaiBorrowPrior; 
        assertEq(totalBorrowExpected, totalDaiBorrowPrior + (borrowDAIAmount / 2));
        assertEq(totalSharesExpected, totalDaiSharesPrior + newSharesExpected);
        assertEq(tlc.userShares(alice, address(daiToken)), userSharesDaiPrior + newSharesExpected);

        // Assert OUD variables
        (,,,,  totalBorrowExpected, totalSharesExpected, , ) = tlc.oud();
        newSharesExpected = (borrowOUDAmount / 2) * totalOUDSharesPrior / totalOUDBorrowPrior; 
        assertEq(totalBorrowExpected, totalOUDBorrowPrior + (borrowOUDAmount / 2));
        assertEq(totalSharesExpected, totalOUDSharesPrior + newSharesExpected);
        assertEq(tlc.userShares(alice, address(oudToken)), userSharesOUDPrior + newSharesExpected);
    }

    function _borrow(address _account, uint256 reserveAmount, uint256 collateralAmount, uint256 daiBorrowAmount, uint256 oudBorrowAmount) internal {
        if (collateralAmount != 0) {
            _postCollateral(_account, reserveAmount, collateralAmount);
        }
        vm.startPrank(_account);
        tlc.borrow(daiBorrowAmount, oudBorrowAmount);
        vm.stopPrank();
    }

    function testBorrowAlreadyBorrowedFailInsufficientCollateral() external {
        uint256 borrowDAIAmountFirst = uint(30_000e18);
        uint256 borrowOUDAmountFirst = uint(20_000e18);
        
        _borrow(alice, 100_000e18, uint(100_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);

        uint256 borrowDAIAmountSecond = tlc.maxBorrowCapacity(address(daiToken), alice) - borrowDAIAmountFirst + 1;
        uint256 borrowOUDAmountSecond = uint(10_000e18);

        vm.expectRevert(abi.encodeWithSelector(InsufficentCollateral.selector, borrowDAIAmountSecond - 1,  borrowDAIAmountSecond)); 
        _borrow(alice, 100_000e18, 0, borrowDAIAmountSecond, borrowOUDAmountSecond);
    }

    function testBorrowAccruesInterestRate() external {

        uint256 reserveAmount = 100_000e18;

        uint256 borrowDAIAmountFirst = uint(90_000e18); // At kink approximately 10% interest rate
        uint256 borrowOUDAmountFirst = uint(20_000e18); // Flat interest rate of 5%
        
        _borrow(alice, reserveAmount, uint(200_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);

        (uint256 totalDAIDebt, uint256 totalOudDebt) = tlc.getTotalDebtAmount(alice);
        assertEq(totalDAIDebt, borrowDAIAmountFirst);
        assertEq(totalOudDebt, borrowOUDAmountFirst);
        
        vm.warp(365 days); // 1 year continously compunding
        (totalDAIDebt, totalOudDebt) = tlc.getTotalDebtAmount(alice);

                                      /// 10% percenet continously compounding ~ 10.52 apr
        assertApproxEqRel(totalDAIDebt, borrowDAIAmountFirst + ((borrowDAIAmountFirst * 1052) / 100 / 100), 0.01e18);
                                      /// 5% percenet continously compounding ~ 5.13 apr
        assertApproxEqRel(totalOudDebt, borrowOUDAmountFirst + ((borrowOUDAmountFirst * 513) / 100 / 100), 0.01e18);
    }


    function testRepayExceedBorrowedAmountFails() external {

        uint256 reserveAmount = 100_000e18;
        uint256 borrowDAIAmountFirst = uint(50_000e18); 
        uint256 borrowOUDAmountFirst = uint(20_000e18); 
       
        _borrow(alice, reserveAmount, uint(200_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);

        vm.expectRevert(abi.encodeWithSelector(ExceededBorrowedAmount.selector, borrowDAIAmountFirst, borrowDAIAmountFirst + 1)); 
        vm.startPrank(alice);
        tlc.repay(borrowDAIAmountFirst + 1, 0);
        vm.stopPrank();
    }


    function testRepaySuccess() external {

        uint256 reserveAmount = 100_000e18;
        uint256 borrowDAIAmountFirst = uint(50_000e18); // At kink approximately 10% interest rate
        uint256 borrowOUDAmountFirst = uint(20_000e18); // Flat interest rate of 5%
       
        _borrow(alice, reserveAmount, uint(200_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);

        vm.warp(365 days); // 1 year continously compunding

        vm.startPrank(alice);
        (uint256 totalDAIDebtPrior, uint256 totalOudDebtPrior) = tlc.getTotalDebtAmount(alice);

        uint256 repayDaiAmount = borrowDAIAmountFirst; // pay of initial borrowed amount 
        uint256 repayOudAmount = borrowOUDAmountFirst;  // pay of initial borrowed amount 
        daiToken.approve(address(tlc), repayDaiAmount);

        // assert emit 
        vm.expectEmit(true, true, true, true, address(tlc));
        emit InterestRateUpdate(address(daiToken), daiInterestRateModel.getBorrowRate(borrowDAIAmountFirst, reserveAmount));
        
        vm.expectEmit(true, true, true, true, address(tlc));
        emit Repay(alice, repayDaiAmount);

        vm.expectEmit(true, true, true, true, address(tlc));
        emit InterestRateUpdate(address(oudToken), oudInterestRateModel.getBorrowRate(borrowOUDAmountFirst, reserveAmount));

        vm.expectEmit(true, true, true, true, address(tlc));
        emit Repay(alice, repayOudAmount);

        tlc.repay(repayDaiAmount, repayOudAmount);

        (uint256 totalDAIDebt, uint256 totalOudDebt) = tlc.getTotalDebtAmount(alice);

        assertEq(totalDAIDebtPrior - borrowDAIAmountFirst, totalDAIDebt); // Remaining amount is interest accumulated
        assertEq(totalOudDebtPrior - borrowOUDAmountFirst, totalOudDebt);
        vm.stopPrank();
    }

    function testRepayAllSuccess() external {

        uint256 reserveAmount = 100_000e18;
        uint256 borrowDAIAmountFirst = uint(50_000e18); // At kink approximately 10% interest rate
        uint256 borrowOUDAmountFirst = uint(20_000e18); // Flat interest rate of 5%
       
        _borrow(alice, reserveAmount, uint(200_000e18), borrowDAIAmountFirst, borrowOUDAmountFirst);
        vm.warp(365 days); // 1 year continously compunding

        vm.startPrank(alice);

        (uint256 repayDaiAmount, uint256 repayOudAmount) = tlc.getTotalDebtAmount(alice); // Repay all debt

        deal(address(daiToken), alice, repayDaiAmount); // Give to pay of interest payment
        deal(address(oudToken), alice, repayOudAmount);
        daiToken.approve(address(tlc), repayDaiAmount);

        // assert emit 
        vm.expectEmit(true, true, true, true, address(tlc));
        emit Repay(alice, repayDaiAmount);

        vm.expectEmit(true, true, true, true, address(tlc));
        emit Repay(alice, repayOudAmount);

        tlc.repay(repayDaiAmount, repayOudAmount);

        (uint256 totalDAIDebt, uint256 totalOudDebt) = tlc.getTotalDebtAmount(alice);

        assertEq(totalDAIDebt, 0);
        assertEq(totalOudDebt, 0);
        vm.stopPrank();
    }

}
