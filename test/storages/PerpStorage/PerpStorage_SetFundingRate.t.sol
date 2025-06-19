// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseTest } from "@hmx-test/base/BaseTest.sol";
import { PerpStorage_Base } from "./PerpStorage_Base.t.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { console2 } from "forge-std/console2.sol";

contract PerpStorage_SetFundingRate is PerpStorage_Base {
  event LogSetFundingRate(uint256 indexed marketIndex, int256 fundingRate);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenSetFundingRate_SingleMarket() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = 1000; // 0.1% (assuming funding rate is in basis points)

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, 1000);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, 1000);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_MultipleMarkets() external {
    uint256[] memory marketIndexes = new uint256[](3);
    int256[] memory fundingRates = new int256[](3);

    marketIndexes[0] = 1;
    marketIndexes[1] = 2;
    marketIndexes[2] = 3;

    fundingRates[0] = 1000; // 0.1%
    fundingRates[1] = -500; // -0.05%
    fundingRates[2] = 2000; // 0.2%

    // Expect events for each market
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, 1000);
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(2, -500);
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(3, 2000);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    // Verify all markets were updated
    IPerpStorage.Market memory market1 = pStorage.getMarketByIndex(1);
    IPerpStorage.Market memory market2 = pStorage.getMarketByIndex(2);
    IPerpStorage.Market memory market3 = pStorage.getMarketByIndex(3);

    assertEq(market1.currentFundingRate, 1000);
    assertEq(market1.lastFundingTime, block.timestamp);

    assertEq(market2.currentFundingRate, -500);
    assertEq(market2.lastFundingTime, block.timestamp);

    assertEq(market3.currentFundingRate, 2000);
    assertEq(market3.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_UpdateExistingMarket() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = 1000;

    // Set initial funding rate
    pStorage.setFundingRate(marketIndexes, fundingRates);

    // Update to new funding rate
    fundingRates[0] = 2500;

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, 2500);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, 2500);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_ZeroFundingRate() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = 0;

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, 0);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, 0);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_NegativeFundingRate() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = -1500; // -0.15%

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, -1500);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, -1500);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_EmptyArrays() external {
    uint256[] memory marketIndexes = new uint256[](0);
    int256[] memory fundingRates = new int256[](0);

    // Should not revert with empty arrays
    pStorage.setFundingRate(marketIndexes, fundingRates);
  }

  function testRevert_WhenSetFundingRate_NotOwner() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = 1000;

    // Try to call as non-owner
    vm.prank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    pStorage.setFundingRate(marketIndexes, fundingRates);
  }

  function testRevert_WhenSetFundingRate_ArrayLengthMismatch() external {
    uint256[] memory marketIndexes = new uint256[](2);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    marketIndexes[1] = 2;
    fundingRates[0] = 1000;

    vm.expectRevert(IPerpStorage.IPerpStorage_BadArrayLength.selector);
    pStorage.setFundingRate(marketIndexes, fundingRates);
  }

  function testRevert_WhenSetFundingRate_ArrayLengthMismatch_Reverse() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](2);

    marketIndexes[0] = 1;
    fundingRates[0] = 1000;
    fundingRates[1] = 2000;

    vm.expectRevert(IPerpStorage.IPerpStorage_BadArrayLength.selector);
    pStorage.setFundingRate(marketIndexes, fundingRates);
  }

  function testCorrectness_WhenSetFundingRate_LargeFundingRate() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = type(int256).max; // Maximum positive value

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, type(int256).max);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, type(int256).max);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_MinimumFundingRate() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 1;
    fundingRates[0] = type(int256).min; // Minimum negative value

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, type(int256).min);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(1);
    assertEq(market.currentFundingRate, type(int256).min);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_NonExistentMarket() external {
    uint256[] memory marketIndexes = new uint256[](1);
    int256[] memory fundingRates = new int256[](1);

    marketIndexes[0] = 999; // Non-existent market
    fundingRates[0] = 1000;

    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(999, 1000);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    IPerpStorage.Market memory market = pStorage.getMarketByIndex(999);
    assertEq(market.currentFundingRate, 1000);
    assertEq(market.lastFundingTime, block.timestamp);
  }

  function testCorrectness_WhenSetFundingRate_MixedPositiveNegative() external {
    uint256[] memory marketIndexes = new uint256[](4);
    int256[] memory fundingRates = new int256[](4);

    marketIndexes[0] = 1;
    marketIndexes[1] = 2;
    marketIndexes[2] = 3;
    marketIndexes[3] = 4;

    fundingRates[0] = 1000; // Positive
    fundingRates[1] = -2000; // Negative
    fundingRates[2] = 0; // Zero
    fundingRates[3] = 500; // Positive

    // Expect events for each market
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(1, 1000);
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(2, -2000);
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(3, 0);
    vm.expectEmit(true, false, false, true);
    emit LogSetFundingRate(4, 500);

    pStorage.setFundingRate(marketIndexes, fundingRates);

    // Verify all markets were updated correctly
    IPerpStorage.Market memory market1 = pStorage.getMarketByIndex(1);
    IPerpStorage.Market memory market2 = pStorage.getMarketByIndex(2);
    IPerpStorage.Market memory market3 = pStorage.getMarketByIndex(3);
    IPerpStorage.Market memory market4 = pStorage.getMarketByIndex(4);

    assertEq(market1.currentFundingRate, 1000);
    assertEq(market2.currentFundingRate, -2000);
    assertEq(market3.currentFundingRate, 0);
    assertEq(market4.currentFundingRate, 500);

    // All should have the same timestamp
    assertEq(market1.lastFundingTime, block.timestamp);
    assertEq(market2.lastFundingTime, block.timestamp);
    assertEq(market3.lastFundingTime, block.timestamp);
    assertEq(market4.lastFundingTime, block.timestamp);
  }
}
