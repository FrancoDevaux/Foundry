// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/*
 * @title: DecentralizedStableCoin
 * @author: Franco Devaux
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // Errors
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    // Funtions
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender); // balanceOf es una función que viene de ERC20.sol de OpenZeppelin.
        if (_amount <= 0) {
            // _amount es un parámetro de entrada en la función burn(), lo pasa el usuario cuando la llama.
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount); //  llama a la función original burn() de ERC20Burnable
            // Porque sobreescribimos la función burn() en nuestro contrato pero queremos que haga lo mismo que la versión original de OpenZeppelin.
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount); // Llama a la función _mint() de ERC20.sol de OpenZeppelin.
        return true; // Si todo va bien, retorna true.
    }
}
