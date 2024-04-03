// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Why is this a library and not abstract?
// Why not an interface?
abstract contract PriceConverter {
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    // We could make this public, but then we'd have to deploy it

    function _getPrice(address priceFeed) internal view returns (uint256) {
        // Sepolia ETH / USD Address
        // https://docs.chain.link/data-feeds/price-feeds/addresses
        (, int256 answer,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        // ETH/USD rate in 18 digit
        return uint256(answer) * ADDITIONAL_FEED_PRECISION;
    }
}
