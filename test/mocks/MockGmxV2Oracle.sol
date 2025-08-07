// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { IGmxV2Types } from "@hmx/interfaces/gmx-v2/IGmxV2Types.sol";
import { IGmxV2Oracle } from "@hmx/interfaces/gmx-v2/IGmxV2Oracle.sol";

contract MockGmxV2Oracle is IGmxV2Oracle {
  mapping(address => IGmxV2Types.PriceProps) public prices;

  function minTimestamp() external pure returns (uint256) {
    return type(uint256).max;
  }

  function maxTimestamp() external pure returns (uint256) {
    return 1;
  }

  function setPrices(IGmxV2Oracle.SetPricesParams memory params) external {
    prices[0x47904963fc8b2340414262125aF798B9655E58Cd] = IGmxV2Types.PriceProps({
      min: 344234240000000000000000000,
      max: 344264600000000000000000000
    });
    prices[0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f] = IGmxV2Types.PriceProps({
      min: 344234240000000000000000000,
      max: 344264600000000000000000000
    });
    prices[0xaf88d065e77c8cC2239327C5EDb3A432268e5831] = IGmxV2Types.PriceProps({
      min: 999900890000000000000000,
      max: 1000148200000000000000000
    });
    prices[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = IGmxV2Types.PriceProps({
      min: 1784642714660000,
      max: 1784736100000000
    });
  }

  function getPrimaryPrice(address token) external view returns (IGmxV2Types.PriceProps memory) {
    return prices[token];
  }

  function validateRealtimeFeeds(
    address /* dataStore */,
    address[] memory realtimeFeedTokens,
    bytes[] memory realtimeFeedData
  ) external view returns (RealtimeFeedReport[] memory) {
    RealtimeFeedReport[] memory reports = new IGmxV2Oracle.RealtimeFeedReport[](realtimeFeedTokens.length);
    for (uint256 i = 0; i < realtimeFeedTokens.length; i++) {
      uint256 price = abi.decode(realtimeFeedData[i], (uint256));
      reports[i] = RealtimeFeedReport({
        feedId: 0,
        observationsTimestamp: uint32(block.timestamp),
        median: int192(int256(price)),
        bid: int192(int256(price)),
        ask: int192(int256(price)),
        blocknumberUpperBound: uint64(block.number),
        upperBlockhash: blockhash(block.number),
        blocknumberLowerBound: uint64(block.number),
        currentBlockTimestamp: uint64(block.timestamp)
      });
    }
    return reports;
  }

  function clearAllPrices() external {}

  function validateSequencerUp() external view {}
}
