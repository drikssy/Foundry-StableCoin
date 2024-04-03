// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct Config {
        // address dscAddress;
        address wethAddress;
        address ethUsdFeedAddress;
        address wbtcAddress;
        address btcUsdFeedAddress;
        uint256 deployerKey;
    }

    Config public s_activeConfig;

    constructor() {
        if (block.chainid == 11155111) s_activeConfig = getSepoliaETHConfig();
        else s_activeConfig = getOrCreateAnvilETHConfig();
    }

    function getSepoliaETHConfig() public view returns (Config memory) {
        address wbtcAddress = 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC; //WBTC
        address wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; //WETH

        address btcUsdFeedAddress = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // BTC/USD
        address ethUsdFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD

        return Config({
            wethAddress: wethAddress,
            ethUsdFeedAddress: ethUsdFeedAddress,
            wbtcAddress: wbtcAddress,
            btcUsdFeedAddress: btcUsdFeedAddress,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilETHConfig() public returns (Config memory) {
        if (s_activeConfig.ethUsdFeedAddress != address(0)) {
            return s_activeConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdFeed = new MockV3Aggregator(8, 2000e8);
        MockV3Aggregator btcUsdFeed = new MockV3Aggregator(8, 46000e8);

        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        return Config({
            wethAddress: address(weth),
            ethUsdFeedAddress: address(ethUsdFeed),
            wbtcAddress: address(wbtc),
            btcUsdFeedAddress: address(btcUsdFeed),
            deployerKey: uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        });
    }
}
