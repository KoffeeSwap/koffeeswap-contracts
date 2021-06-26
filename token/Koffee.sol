// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./openzeppelin/ERC20.sol";

contract KoffeeToken is ERC20 {
    constructor() ERC20("KoffeeSwap Token", "KOFFEE") {
        _mint(msg.sender, 12648430 * 10 ** decimals());
    }
}