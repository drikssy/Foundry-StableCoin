// SPDX-Licence-Identifier: MIT
// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Cedric Ngakam
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_MustBeMoreThanZero();
    error DecentralizedStableCoin_BurnAmountExceedsBalance();
    error DecentralizedStableCoin_NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) revert DecentralizedStableCoin_MustBeMoreThanZero();
        if (amount > balance) {
            revert DecentralizedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        if (to == address(0)) revert DecentralizedStableCoin_NotZeroAddress();
        if (amount <= 0) revert DecentralizedStableCoin_MustBeMoreThanZero();
        _mint(to, amount);
        return true;
    }
}
