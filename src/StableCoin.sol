// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/extensions";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StableCoin
 * @author Luke Sheppard
 * Collateral: Exogenous (BTC and ETH)
 * Relative Stability: Pegged to USD
 *
 * This contract meant to be giverned by DSCEngine. This contract is the ERC20 implementation of the
 * stable coin
 */

error BalanceMustbeMoreThanZero();
error BurnAmountExceedsBalance();

contract StableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("Decentralized StableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert BalanceMustbeMoreThanZero();
        }
        if (balance < _amount) {
            revert BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }
}
