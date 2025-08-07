// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

contract TC20 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // TC20 - Trade with max utilization
  function testCorrectness_TC20_TradeWithMaxUtilization() external {
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
    address _bobSubAccount0 = getSubAccount(BOB, 0);

    // ### Scenario: Prepare environment
    // Given Max Utilization is 80%
    // And BTC price is 20,000 USD
    // And WETH price is 1,500 USD
    // And APPLE price is 152 USD
    updatePriceData = new bytes[](3);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(wethAssetId, 1500 * 1e8, 0);
    // updatePriceData[2] = _createPriceFeedUpdateData(jpyAssetId, 152 * 1e3, 0);
    tickPrices[0] = 73135; // ETH tick price $23,000
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[6] = 50241; // JPY tick price $152

    // And Bob provide liquidity 5 btc
    addLiquidity(BOB, wbtc, 5 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);
    {
      // HLP liquidity and total supply should be corrected
      // 5 * 0.997 = 4.985
      // 4.985 * 20000 = 99700
      assertHLPLiquidity(address(wbtc), 4.985 * 1e8);
      assertHLPTotalSupply(99700 * 1e18);
      assertTVL(99700 * 1e30, false);
    }

    // And Alice deposit 5 btc as Collateral
    depositCollateral(ALICE, 0, wbtc, 5 * 1e8);

    // And Bob deposit 0.5 btc as Collateral
    depositCollateral(BOB, 0, wbtc, 0.5 * 1e8);
    {
      // check balances
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 5 * 1e8);
      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.5 * 1e8);
    }

    // ### Scenario: Traders buy / sell
    // When Alice sell WETH 600,000 USD
    marketSell(ALICE, 0, wethMarketIndex, 600_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // avg price = 1500 * (1 + ((0 - 600000) / 300000000 / 2)) = 1498.5
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: -int256(600_000 * 1e30),
        _avgPrice: 1498.5 * 1e30,
        _reserveValue: 54_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });

      // 600000 * 1% (IMF) = 6000 * 900% (max profit) = 54,000
      // Then Alice's WETH position should be corrected
      assertAssetClassReserve(0, 54_000 * 1e30);
      assertGlobalReserve(54_000 * 1e30);
    }

    // When Bob buy APPLE 100,000 USD
    // Then Revert ITradeService_InsufficientLiquidity
    marketBuy(
      BOB,
      0,
      appleMarketIndex,
      100_000 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_InsufficientLiquidity()"
    );

    // When Bob buy APPLE 20,000 USD
    marketBuy(BOB, 0, appleMarketIndex, 20_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // premium before = 0 / 300000000 = 0
      // premium after  = 20000 / 300000000 = 0.000066666666666666666666666666
      // premium        = (0 + 0.000066666666666666666666666666) / 2 = 0.000033333333333333333333333333
      // adaptive price = 1500 * (1 + 0.000033333333333333333333333333) = 152.005066666666666666666666666616
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: int256(20_000 * 1e30),
        _avgPrice: 152.005066666666666666666666666616 * 1e30,
        _reserveValue: 9_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });

      // 20000 * 5% (IMF) = 1000 * 900% (max profit) = 9000
      // Then Bob's APPLE position should be corrected
      assertAssetClassReserve(0, 54_000 * 1e30);
      assertAssetClassReserve(1, 9_000 * 1e30);

      // 54000 + 9000 = 63000
      assertGlobalReserve(63_000 * 1e30);
    }

    // When Alice sell more WETH position 150,000 USD
    marketSell(ALICE, 0, wethMarketIndex, 150_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice's WETH position should be corrected
      // new close price = 1500 * (1 + ((-750000 + 0) / 300000000 / 2)) = 1498.125
      // new average price = 1498.125 * 750000 / 750000 + 0 (pnl) = 1498.125
      // new reserve = 750000 * 1% * 900% = 67500
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: -int256(750_000 * 1e30),
        _avgPrice: 1498.125 * 1e30,
        _reserveValue: 67_500 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });

      assertAssetClassReserve(0, 67_500 * 1e30);
      assertAssetClassReserve(1, 9_000 * 1e30);

      // 67500 + 9000 = 76500
      assertGlobalReserve(76500 * 1e30);
    }

    // When Alice buy APPLE position 20,000 USD
    // Then Revert ITradeService_InsufficientLiquidity
    marketBuy(
      ALICE,
      0,
      appleMarketIndex,
      20_000 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_InsufficientLiquidity()"
    );

    // time passed for 15 seconds
    skip(15);

    // ### Scenario: TVL has increased when price changed
    // When BTC price pump to 22,000 USD
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 22000 * 1e8, 0);
    tickPrices[1] = 99993; // WBTC tick price $22,000
    updatePriceFeeds(tickPrices, block.timestamp);
    {
      // Then TVL should be increased
      // 4.985 * 22000 = 109670
      // max utilization threshold should be increased to 109670 * 80% = 87736 USD
      assertTVL(109_670 * 1e30, false);
    }

    // And Alice buy APPLE position 20,000 USD again
    marketSell(ALICE, 0, appleMarketIndex, 20_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // premium before = 20000 / 300000000 = 0.000066666666666666666666666666
      // premium after  = 0 / 300000000 = 0
      // premium        = (0.000066666666666666666666666666 + 0) / 2 = 0.000033333333333333333333333333
      // adaptive price = 152 * (1 + 0.000033333333333333333333333333) = 152.005066666666666666666666666616
      // Then Alice should has APPLE short position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(20_000 * 1e30),
        _avgPrice: 152.005066666666666666666666666616 * 1e30,
        _reserveValue: 9_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 246193124829032,
        _lastFundingAccrued: -399999999990
      });

      assertAssetClassReserve(0, 67_500 * 1e30);
      assertAssetClassReserve(1, 18_000 * 1e30);

      // 67500 + 18_000 = 85500
      assertGlobalReserve(85_500 * 1e30);
    }

    // timepassed for 15 seconds
    skip(15);
    // ### Scenario: TVL has decreased when price changed
    // When BTC price has changed back to 20,000 USD
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    updatePriceFeeds(tickPrices, block.timestamp);
    {
      // Then TVL should be reduced
      // 4.985 * 20000 = 99700
      // max utilization threshold should be reduced to 99700 * 80% = 79,760 USD
      // note: means now global reserve is 85,500 USD it's over max utilization
      assertTVL(99_700 * 1e30, false);
    }

    // And Alice fully close APPLE's position
    marketBuy(ALICE, 0, appleMarketIndex, 20_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice Apple's position should be gone
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // And Alice's balances should be corrected
    assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 4.96130173 * 1e8);
    // And Bob's balances should be corrected
    assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.49950000 * 1e8);

    // And new APPLE's market state should corrected
    assertMarketLongPosition({
      _marketIndex: appleMarketIndex,
      _positionSize: 20_000 * 1e30,
      _avgPrice: 152.005066666666666666666666666616 * 1e30,
      _str: "APPLE: "
    });
    assertMarketShortPosition({ _marketIndex: appleMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "APPLE: " });

    // And WETH's market should be corrected
    assertMarketLongPosition({ _marketIndex: wethMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "WETH: " });
    assertMarketShortPosition({
      _marketIndex: wethMarketIndex,
      _positionSize: 750_000 * 1e30,
      _avgPrice: 1498.125 * 1e30,
      _str: "WETH:  "
    });
  }
}
