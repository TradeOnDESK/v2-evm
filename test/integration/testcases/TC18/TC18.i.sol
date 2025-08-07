// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

contract TC18 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // ## TC18 - Trade with Max profit
  function testCorrectness_TC18_TradeWithBadPrice() external {
    // ### Scenario: Prepare environment
    // mint native token
    vm.deal(BOB, 1 ether);
    vm.deal(ALICE, 1 ether);
    vm.deal(FEEVER, 1 ether);
    // @todo - fix function in bot handler to be payable
    vm.deal(address(botHandler), 1 ether);

    // mint BTC
    wbtc.mint(ALICE, 100 * 1e8);
    wbtc.mint(BOB, 100 * 1e8);

    // warp to block timestamp 1000
    vm.warp(1000);

    address _aliceSubAccount0 = getSubAccount(ALICE, 0);

    // Given WETH price is 1,500 USD
    // And APPLE price is 152 USD
    updatePriceData = new bytes[](2);
    // updatePriceData[0] = _createPriceFeedUpdateData(wethAssetId, 1_500 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(appleAssetId, 152 * 1e8, 0);
    tickPrices[0] = 73135; // ETH tick price $1500
    tickPrices[5] = 50241; // APPL tick price $152

    // And Bob provide 1 btc as liquidity
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    skip(100);

    // And Alice deposit 1 btc as Collateral
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);

    // ### Scenario: Alice trade on WETH's market
    // When Alice buy WETH 12,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 12_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice's WETH position should be corrected
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(12_000 * 1e30),
        _avgPrice: 1500.03 * 1e30,
        _reserveValue: 1_080 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    skip(15);

    // ### Scenario: WETH Price pump up 10% and Alice take profit
    // When Price pump to 1,650 USD
    // updatePriceData[0] = _createPriceFeedUpdateData(wethAssetId, 1_650 * 1e8, 0);
    tickPrices[0] = 74089; // ETH tick price $1650
    // And Alice partial close for 3,000 USD
    marketSell(ALICE, 0, wethMarketIndex, 3_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should get profit correctly
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(9_000 * 1e30),
        _avgPrice: 1513.784174311926605504587155963302 * 1e30,
        _reserveValue: 810 * 1e30,
        _realizedPnl: 270 * 1e30,
        _entryBorrowingRate: 0.000081243731193580 * 1e18,
        _lastFundingAccrued: -0.00000024 * 1e18
      });

      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 1.01274548 * 1e8);
    }

    // ### Scenario: Bot force close Alice's position, when alice position profit reached to reserve
    // When Bot force close ALICE's WETH position
    forceTakeMaxProfit(ALICE, 0, wethMarketIndex, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should get profit correctly
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 1.05279548 * 1e8);

      // And Alice's WETH position should be gone
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // ### Scenario: Alice trade on APPLE's market, and profit reached to reserve
    // When Alice sell APPLE 3,000 USD
    marketSell(ALICE, 0, appleMarketIndex, 3000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice's APPLE position should be corrected
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: int256(-3000 * 1e30),
        _avgPrice: 151.99442031409855 * 1e30,
        _reserveValue: 1_350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    skip(15);
    // And APPLE's price dump to 70 USD (reached to max reserve)
    // updatePriceData[1] = _createPriceFeedUpdateData(appleAssetId, 136.8 * 1e8, 0);
    tickPrices[5] = 42487; // APPL tick price $70
    // And Alice sell more position at APPLE 3,000 USD
    marketSell(ALICE, 0, appleMarketIndex, 3000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // This should be reverted as it reached to max reserve, Alice only allow to close position.
      // However, the revert is catched by the limit handler, hence Alice's position should not be altered.
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: int256(-3000 * 1e30),
        _avgPrice: 151.99442031409855 * 1e30,
        _reserveValue: 1_350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // APPLE's price rebound to $136.8
    tickPrices[5] = 49187; // APPL tick price $136.8
    // And Alice sell more position at APPLE 3,000 USD
    marketSell(ALICE, 0, appleMarketIndex, 3000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);

    // ### Scenario: Bot couldn't force close Alice's position
    // When Bot force close ALICE's APPLE position
    // Then Revert ReservedValueStillEnough
    forceTakeMaxProfit(
      ALICE,
      0,
      appleMarketIndex,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "IBotHandler_ReservedValueStillEnough()"
    );
  }
}
