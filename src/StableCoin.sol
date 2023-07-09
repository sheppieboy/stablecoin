// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StableCoin is ERC20Burnable, Ownable {
    error BalanceMustbeMoreThanZero();
    error BurnAmountExceedsBalance();
    error InvalidAddress();

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

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert InvalidAddress();
        }

        if (_amount <= 0) {
            revert BalanceMustbeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
