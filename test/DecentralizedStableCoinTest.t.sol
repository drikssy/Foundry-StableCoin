// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../script/DeployDecentralizedStableCoin.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address public USER = makeAddr("USER");

    function setUp() public {
        DeployDecentralizedStableCoin deployer = new DeployDecentralizedStableCoin();
        dsc = deployer.run();
    }
}
