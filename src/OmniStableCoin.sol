

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {ERC20Burnable , ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

    /**
        *   @title Decentralized stable coin 
        *  @author Omeenee
                Collateral : Exogenous (Eth and Btc)
                Minting : Algorithmic 
                Relative Stability : Pegged to USD

                This contract will be governed by the DSCEngine . 
                This contract is just the ERC20 implementation of our stable system
    *
    */
contract OmniStableCoin is ERC20Burnable , Ownable{
    error OmniStableCoin__MustBeMoreThanZero();
    error OmniStableCoin__BurnAmountExceedsZero();
    error OmniStableCoin__NotZeroAddress();
    constructor() ERC20 ("OmniStableCoin" , "OSC") Ownable(msg.sender) {}
    function burn(uint256 _amount) public override onlyOwner  {
        uint256 balance = balanceOf(msg.sender);
        if (_amount < 0 ){
            revert OmniStableCoin__MustBeMoreThanZero();
        }
        if(_amount > balance) {
            revert OmniStableCoin__BurnAmountExceedsZero();
            
        }
        super.burn(_amount);
        
    }

    function mint(address _to , uint256 _amount) external onlyOwner returns (bool){
        if (_to == address(0)){
            revert OmniStableCoin__NotZeroAddress();
        }
        if (_amount <= 0){
            revert OmniStableCoin__MustBeMoreThanZero();
        }
        _mint(_to , _amount);
        return true;
    }
}