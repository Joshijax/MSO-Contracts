// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SyntheticToken is ERC20, ERC20Burnable, Ownable {
    constructor(address initialOwner, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        Ownable()
    {
        
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}