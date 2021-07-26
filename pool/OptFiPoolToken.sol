// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./OptFiPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OptFiPoolToken is ERC20, Ownable{

    bool private _tradeable;

    constructor (string memory name_, string memory symbol_, bool tradeable_) ERC20 (name_, symbol_) {
        _tradeable = tradeable_;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(_tradeable,"This token is not tradeable and cannot be transferred.");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(_tradeable,"This token is not tradeable and cannot be transferred.");
        return super.transferFrom(sender, recipient, amount);
    }

    fallback() external {}
}