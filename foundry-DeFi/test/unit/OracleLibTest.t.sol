// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public mockV3Aggregator;

    uint8 public constant DECIMALS = 8;
    int256 public constant STRAT_PRICE = 2000 ether; // 2000 USD

    function setUp() public {
        mockV3Aggregator = new MockV3Aggregator(DECIMALS, STRAT_PRICE);
    }

    function testGetTimeOut() public view {
        uint256 expectedTime = 3 hours; // 3 * 60 * 60 seconds = 10800 seconds
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(address(mockV3Aggregator))), expectedTime);
    }

    // Foundry Bug - I have to make staleCheckLatestRoundData public
    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 8 seconds); //  el límite permitido es 3 horas
        vm.roll(block.number + 1); // Avanza el número de bloque para reflejar el paso del tiempo

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector); // la siguinte lienea se espera que falle
        AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();
        // Llamamos a la función y como se adelantó el tiempo, se espera que falle por ser un precio viejo.
    }

    function testPriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        mockV3Aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt); // Actualizamos el oráculo falso con esos datos = 0

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();
        // Se llama a la función que debería detectar que esos datos no estan bien y lanzar error.
    }
}
