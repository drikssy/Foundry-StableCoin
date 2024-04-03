// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function run() public returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();
        (
            address wethAddress,
            address ethUsdFeedAddress,
            address wbtcAddress,
            address btcUsdFeedAddress,
            uint256 deployerKey
        ) = config.s_activeConfig();

        tokenAddresses = [wethAddress, wbtcAddress];
        feedAddresses = [ethUsdFeedAddress, btcUsdFeedAddress];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc, engine);
    }
}
