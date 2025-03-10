// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    FundMe fundMe; // Declarar la variable
    address USER = makeAddr("rose");
    uint256 constant SEND_VALUE = 0.1 ether; // = 0.1 ether = 100000000000000000 wei = $ 223.79 precio de ether en USD a dia 2024-03-06
    uint256 constant START_BALANCE = 100 ether; // 100 ether de prueba

    function setUp() external {
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        vm.deal(USER, START_BALANCE); // Le damos 100 ether de prueba a USER "rose"
    }

    function testMinimDollarIsFIVE() public view {
        assertEq(fundMe.MINIMUM_USD(), 5e18); //Si le ponemos 6e18, falla
    }

    function testOwnerIsMsgSender() public view {
        //assertEq(fundMe.i_owner(), address(this));
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeedVersionIsAccurate() public view {
        if (block.chainid == 11155111) {
            uint256 version = fundMe.getVersion();
            assertEq(version, 4);
        } else if (block.chainid == 1) {
            uint256 version = fundMe.getVersion();
            assertEq(version, 6);
        }
    }

    function testFundFailsWithEnoughtEther() public {
        vm.expectRevert(); // Esperamos que falle
        fundMe.fund(); // le mandamos 0 ether por ende va a fallar y va a dar un success por el expectRevert ya que se espera que falle
    }

    function testFundSuccessWithEnoughEther() public {
        vm.prank(USER); // la proxima tx va a ser enviada por USER "rose"

        fundMe.fund{value: SEND_VALUE}(); // le mandamos 0.1 ether por ende va a ser exitoso y va a dar un success por el expectSuccess

        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testAddressFunderToArrayFunders() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        address funder = fundMe.getFunder(0);
        assertEq(funder, USER);
    }

    // Usamos un modiefier para enviar ether a la direccion del contrato y no tener que hacerlo en cada test
    modifier funded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    function testOnlyOwnerCanWithdraw() public funded {
        vm.prank(USER); // la proxima tx va a ser enviada por USER "rose"
        vm.expectRevert(); // Esperamos que falle
        fundMe.withdraw(); // va a fallar ya que USER "rose" no es el owner
    }

    function testWithDraw() public funded {
        // Arrange --> Organizar la prueba

        uint256 balanceBefore = fundMe.getOwner().balance; // Captura el saldo del dueño (owner) del contrato fundMe antes de hacer el retiro.
        uint256 startingFundMeBalance = address(fundMe).balance; // Captura el saldo del contrato fundMe antes de hacer el retiro.

        // Act --> Realizar la accion a probar

        vm.prank(fundMe.getOwner()); // Esto hace que la siguiente transacción se realice como si fuera enviada por el dueño del contrato.
        fundMe.withdraw(); // Llama a la función withdraw, que se supone q debe transferir todos los fondos del contrato al dueño.

        // Assert --> Afirmar en la prueba

        uint256 endingBalance = fundMe.getOwner().balance; //  Saldo del dueño después del retiro.
        uint256 endingFundMeBalance = address(fundMe).balance; // Saldo del contrato después del retiro.
        assertEq(endingFundMeBalance, 0); // Verifica que el balance del contrato debe ser 0
        assertEq(startingFundMeBalance + balanceBefore, endingBalance); // Verifica que el saldo del dueño aumentó exactamente en la cantidad que tenía el contrato, asegurando que el retiro transfirió correctamente los fondos al owner
    }

    function testWithDrawMultipleFunders() public funded {
        // Arrange
        uint160 numberOfFunders = 10;
        uint160 startFunderIndex = 1;

        for (uint160 i = startFunderIndex; i <= numberOfFunders; i++) {
            hoax(address(i), SEND_VALUE); // hoax() es una funcion que simula ser una direccion y enviar ether (prank + deal)
            fundMe.fund{value: SEND_VALUE}();
        }
        uint256 balanceBefore = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        // Act
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();

        // Assert
        assertEq(address(fundMe).balance, 0); // Verifica que el balance del contrato debe ser 0
        assertEq(
            balanceBefore + startingFundMeBalance,
            fundMe.getOwner().balance
        ); // Verifica que el saldo del dueño aumentó exactamente en la cantidad que tenía el contrato, asegurando que el retiro transfirió correctamente los fondos al owner
    }

    function testWithDrawMultipleFundersCheaper() public funded {
        // Arrange
        uint160 numberOfFunders = 10;
        uint160 startFunderIndex = 1;

        for (uint160 i = startFunderIndex; i <= numberOfFunders; i++) {
            hoax(address(i), SEND_VALUE); // hoax() es una funcion que simula ser una direccion y enviar ether (prank + deal)
            fundMe.fund{value: SEND_VALUE}();
        }
        uint256 balanceBefore = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        // Act
        vm.startPrank(fundMe.getOwner());
        fundMe.cheaperWithdraw(); // cambiamos el nombre de la funcion withdraw a cheaperWithdraw
        vm.stopPrank();

        // Assert
        assertEq(address(fundMe).balance, 0);
        assertEq(
            balanceBefore + startingFundMeBalance,
            fundMe.getOwner().balance
        );
    }
}
