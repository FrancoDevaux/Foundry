// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol"; // simular un fallo controlado "TransferFrom" de un token ERC20
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol"; // simular un fallo controlado "Mint" de un token ERC20
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol"; // simular un fallo controlado "Mint" de un token ERC20

contract DSCEngineTest is StdCheats, Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if redeemFrom != redeemedTo, then it was liquidated

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 amountToMint = 100 ether;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////////
    //   Constructor Test  //
    /////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIsTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////
    //     Prcice Test     //
    /////////////////////////

    function testGetUsdValue() public view {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether; // 100:2000 = 0.05  ---> $2000 = 1 ETH
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender; // Guarda el que llama a este test (msg.sender) como owner
        vm.prank(owner); // el siguiente msg.sender sea owner
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom(); // Creamos una instancia del MOCK MockFailedTransferFrom

        tokenAddresses = [address(mockDsc)]; // Necesarios para construir el contrato DSCEngine
        priceFeedAddresses = [ethUsdPriceFeed]; // Necesarios para construir el contrato DSCEngine

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL); // si el usuario no tiene tokens... ¡no hay nada para transferir!

        vm.prank(owner); // Quiero que la próxima transacción (y sólo esa) se ejecute como si msg.sender == owner.”
        mockDsc.transferOwnership(address(mockDsce)); // Para que DSCEngine tenga permiso de llamar mint() en el mock, ya que esa función es onlyOwner.

        // Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL); // USER aprueba que DSCEngine pueda mover sus tokens (AMOUNT_COLLATERAL).

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector); // Se espera q la siguiente línea va a hacer revert con este error
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL); // el (mockDsc) que tiene la funcion transferFrom roto a propósito
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); // El usuario (USER) aprueba al contrato dscEngine para gastar AMOUNT_COLLATERAL tokens de weth.

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector); // si el usuario intenta depositar 0 tokens deberia lanzar un error
        dscEngine.depositCollateral(weth, 0); // no revierte, el test fallará, indicando un problema en la validación del contrato.
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("Random", "RAND", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);

        // Asegurarse de que el token no está en s_priceFeeds antes de llamar la función
        console.logAddress(dscEngine.getPriceFeed(address(randomToken))); // Debería imprimir 0x0 -vv

        // Esperamos que la transacción revierta con el error específico y la dirección del token
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));

        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        // Tener ya colateral depositado
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositedAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 USERBalance = dsc.balanceOf(USER);
        assertEq(USERBalance, 0); // El usuario no ha acuñado nada
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 USERBalance = dsc.balanceOf(USER);
        assertEq(USERBalance, amountToMint);
    }

    ///////////////////////////////////////
    //          MintDsc Tests           //
    ///////////////////////////////////////

    function testRevertsIfMintFailed() public {
        // Arrange setUp

        // Porque simplemente no necesitabas que el owner fuera otra address distinta al contrato de test (address(this)), entonces podías omitir vm.prank.
        /**
         * address owner = msg.sender;
         * vm.prank(owner);
         */
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(); // Creamos una instancia de MockFailedMintDSC

        tokenAddresses = [weth]; // Ahora usamos un WETH "normal" como colateral, porque no quiero testear transferFrom en este test, quiero que funcione bien.
        priceFeedAddresses = [ethUsdPriceFeed];

        //address owner = msg.sender; // Guarda el que llama a este test (msg.sender) como owner
        //vm.prank(owner);

        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce)); // Para que DSCEngine tenga permiso de llamar mint() en el mock, ya que esa función es onlyOwner.

        // Arrange USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL); // USER aprueba que DSCEngine pueda mover sus tokens (AMOUNT_COLLATERAL).

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector); // Se espera q la siguiente línea va a hacer revert con este error
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint); // el (mockDsc) que tiene la funcion mint roto a propósito
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData(); // Obtener el precio actual de ETH
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(USER);
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor)); // si el usuario intenta acuñar una cantidad que rompe el health factor deberia lanzar un error
        dscEngine.mintDsc(amountToMint); // El usuario acuña DSC
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDsc(amountToMint); // El usuario acuña DSC
        uint256 USERBalance = dsc.balanceOf(USER); // El balance de DSC del usuario
        assertEq(USERBalance, amountToMint); // El balance de DSC del usuario es igual a la cantidad acuñada
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); // El usuario (USER) aprueba al contrato dscEngine para gastar AMOUNT_COLLATERAL tokens de weth.
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL); // El usuario deposita AMOUNT_COLLATERAL tokens de weth en el contrato dscEngine.

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector); // si el usuario intenta acuñar 0 tokens deberia lanzar un error
        dscEngine.mintDsc(0); // no revierte, el test fallará, indicando un problema en la validación del contrato.
        vm.stopPrank();
    }

    ///////////////////////////////////
    //          burnDsc Tests       //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); // El usuario (USER) aprueba al contrato dscEngine para gastar AMOUNT_COLLATERAL tokens de weth.
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint); // El usuario deposita AMOUNT_COLLATERAL tokens de weth en el contrato dscEngine.

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector); // si el usuario intenta quemar 0 tokens deberia lanzar un error
        dscEngine.burnDsc(0); // no revierte, el test fallará, indicando un problema en la validación del contrato.
        vm.stopPrank();
    }

    function testCanBurnMoreThanUSERHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(100 ether); // no revierte, el test fallará, indicando un problema en la validación del contrato.
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), amountToMint); // El usuario (USER) aprueba al contrato dscEngine para gastar AMOUNT_COLLATERAL tokens de weth.
        dscEngine.burnDsc(amountToMint); // El usuario quema DSC
        vm.stopPrank();

        uint256 USERBalance = dsc.balanceOf(USER); // El balance de DSC del usuario
        assertEq(USERBalance, 0); // El balance de DSC del usuario es igual a la cantidad quemada
        uint256 dscEngineBalance = dsc.balanceOf(address(dscEngine)); // El balance de DSC del contrato
        assertEq(dscEngineBalance, 0); // El balance de DSC del contrato es igual a la cantidad quemada
    }

    ///////////////////////////////////
    //    redeemCollateral Tests     //
    //////////////////////////////////

    function testReevertsIfTransferFails() public {
        // Arrange - Setup
        address owner = msg.sender; // Guarda el que llama a este test (msg.sender) como owner
        vm.prank(owner); // el siguiente msg.sender sea owner
        MockFailedTransfer mockDsc = new MockFailedTransfer(); // Creamos una instancia del MOCK MockFailedTransferFrom

        tokenAddresses = [address(mockDsc)]; // Necesarios para construir el contrato DSCEngine
        priceFeedAddresses = [ethUsdPriceFeed]; // Necesarios para construir el contrato DSCEngine

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL); // si el usuario no tiene tokens... ¡no hay nada para transferir!

        vm.prank(owner); // Quiero que la próxima transacción (y sólo esa) se ejecute como si msg.sender == owner.”
        mockDsc.transferOwnership(address(mockDsce)); // Para que DSCEngine tenga permiso de llamar mint() en el mock, ya que esa función es onlyOwner.

        // Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL); // USER aprueba que DSCEngine pueda mover sus tokens (AMOUNT_COLLATERAL).

        // Act / Assert
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector); // Se espera q la siguiente línea va a hacer revert con este error
        mockDsce.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL); // el (mockDsc) que tiene la funcion transferFrom roto a propósito
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanReedemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 USERBalanceBeforeRedeem = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(USERBalanceBeforeRedeem, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 USERBalanceAfterRedeem = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(USERBalanceAfterRedeem, 0); // Luego de retirarlo, su balance de colateral sea 0.
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedCorrectARGS() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDsc.approve(address(mockDsce), debtToCover);

        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);

        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(weth, USER, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(weth, amountToMint)
            + (
                dscEngine.getTokenAmountFromUsd(weth, amountToMint) * dscEngine.getLiquidationBonus()
                    / dscEngine.getLiquidationPrecision()
            );
        uint256 hardCodedExpected = 6_111_111_111_111_111_110; // cantidad de WETH en formato de 18 decimales,
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dscEngine.getTokenAmountFromUsd(weth, amountToMint)
            + (
                dscEngine.getTokenAmountFromUsd(weth, amountToMint) * dscEngine.getLiquidationBonus()
                    / dscEngine.getLiquidationPrecision()
            );

        uint256 usdAmountLiquidated = dscEngine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd =
            dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020; // = $70.000000000000020
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = dscEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dscEngine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
