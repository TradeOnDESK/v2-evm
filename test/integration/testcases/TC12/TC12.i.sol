// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;
import { console } from "forge-std/console.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

contract TC12 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // ## TC12 - limit number of position per sub-account
  function testCorrectness_TC12_LimitNumberOfMarketToTrade() external {
    // ### Scenario: Prepare environment
    // mint native token
    vm.deal(BOB, 1 ether);
    vm.deal(ALICE, 1 ether);
    vm.deal(FEEVER, 1 ether);

    // mint BTC
    wbtc.mint(ALICE, 100 * 1e8);
    wbtc.mint(BOB, 100 * 1e8);

    // warp to block timestamp 1000
    vm.warp(1000);

    // Given Bob provide 1 btc as liquidity
    // And Btc price is 20,000 USD
    // And WETH price is 1,500 USD
    updatePriceData = new bytes[](2);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(wethAssetId, 1500 * 1e8, 0);
    tickPrices[0] = 73135; // ETH tick price $1500
    tickPrices[1] = 99039; // WBTC tick price $20,000
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    // And Max Number of position 2
    configStorage.setTradingConfig(
      IConfigStorage.TradingConfig({
        fundingInterval: 1, // second
        devFeeRateBPS: 1500, // 15%
        minProfitDuration: 15, // second
        maxPosition: 2
      })
    );

    address _aliceSubAccount0 = getSubAccount(ALICE, 0);
    address _aliceSubAccount1 = getSubAccount(ALICE, 1);
    address _bobSubAccount0 = getSubAccount(BOB, 0);

    // When Alice deposit collateral 1 btc for sub-account 0
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);
    {
      // Then Alice should has btc balance 1 btc
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 1 * 1e8);
      // invariant test
      assertSubAccountTokenBalance(_aliceSubAccount1, address(wbtc), false, 0 * 1e8);
    }

    // ### Scenario: Alice open multiple position in sub-account 0
    // When Alice open long position at WETH 3,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    // And Alice open long position at JPY 3,000 USD
    marketBuy(ALICE, 0, jpyMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    // And Alice open short position at APPLE 3,000 USD
    // Then Revert because reach limit 2 position per sub-account
    marketSell(
      ALICE,
      0,
      appleMarketIndex,
      3_000 * 1e30,
      address(0),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_BadNumberOfPosition()"
    );
    // And Alice should has only 2 positions
    {
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(3_000 * 1e30),
        _avgPrice: 1_500.0075 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: int256(3_000 * 1e30),
        _avgPrice: 0.007346333830432770362098984006 * 1e30,
        _reserveValue: 27 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
      // should not has apple
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

    // ### Scenario: Bob open position in sub-account 0
    // Given Bob deposit collateral 1 btc for sub-account 0
    depositCollateral(BOB, 0, wbtc, 1 * 1e8);
    {
      // Then Alice should has btc balance 1 btc
      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 1 * 1e8);
    }

    // When Bob open long position at WBTC 30,0000 USD
    marketBuy(BOB, 0, wbtcMarketIndex, 30_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    // Then Bob should has corrected position
    {
      // WBTC's market
      // market skew      = 0
      // new market skew  = 0 + 30000
      // premium before   = 0 / 300000000 = 0
      // premium after    = 30000 / 300000000 = 0.0001
      // premium          = (0 + 0.0001) / 2 = 0.00005
      // adaptive price   = 20000 * (1 + 0.00005) = 20001
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(30_000 * 1e30),
        _avgPrice: 20001 * 1e30,
        _reserveValue: 2700 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
      // should not affected with ALICE sub-account 0
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(3_000 * 1e30),
        _avgPrice: 1_500.0075 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // ### Scenario: Alice try open with another sub-account
    // Given Alice deposit collateral 1 btc for sub-account 1
    depositCollateral(ALICE, 1, wbtc, 1 * 1e8);
    {
      assertSubAccountTokenBalance(_aliceSubAccount1, address(wbtc), true, 1 * 1e8);
    }

    // When alice open short position at APPLE 3,000 USD again with sub-account 1
    marketSell(ALICE, 1, appleMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // APPLE's market
      // market skew      = 0
      // new market skew  = 0 - 3000 = -3000
      // premium before   = 0
      // premium after    = -3000 / 300000000 = -0.00001
      // premium          = (0 - 0.00001) / 2 = -0.000005
      // adaptive price    = 152 * (1 + (-0.000005)) = 151.99924
      // Then Alice should has corrected position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount1,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(3_000 * 1e30),
        _avgPrice: 151.99924 * 1e30,
        _reserveValue: 1350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // ### Scenario: Alice fully close position and open another position
    // When Alice close position at JPY
    marketSell(ALICE, 0, jpyMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);

    // Then Alice should able to open long position at APPLE 3,000 USD
    marketSell(ALICE, 0, appleMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // APPLE's market
      // market skew      = -3000
      // new market skew  = -3000 - 3000 = -6000
      // premium before   = -3000 / 300000000 = -0.00001
      // premium after    = -6000 / 300000000 = -0.00002
      // premium          = (-0.00001 - 0.00002) / 2 = -0.000015
      // adaptive price    = 152 * (1 + (-0.000015)) = 151.99772
      // Then Alice should has corrected position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(3_000 * 1e30),
        _avgPrice: 151.99772 * 1e30,
        _reserveValue: 1350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    marketBuy(ALICE, 0, appleMarketIndex, 6_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // note: decrease size is greater than position size for 3,000 USD
      //       this action will separated to 2 steps
      //       1. decrease short 3,000 USD
      //       2. increase long  3,000 USD
      // Then Alice should has correct long position
      // Calculation after closed short position
      // market skew      = -6000
      // new market skew  = -6000 + 3000 = -3000

      // Calculation after open new long position
      // market skew      = -3000
      // new market skew  = -3000 + 3000 = 0
      // premium before   = -3000 / 300000000 = -0.00001
      // premium after    = 0 / 300000000 = 0
      // premium          = (-0.00001 + 0) / 2 = -0.000005
      // adaptive price   = 152 * (1 + -0.000005) = 151.99924
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: int256(3_000 * 1e30),
        _avgPrice: 151.99924 * 1e30,
        _reserveValue: 1350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0
      });
    }

    // ### Scenario: Alice flip position direction APPLE position
    // When Alice decrease short position at APPLE 6,000 USD
    // Then Alice should has long position of APPLE 3,000 USD

    // And Asset class's reserve and Market's state should be corrected

    assertAssetClassReserve({ _assetClassIndex: 0, _reserved: 2_970 * 1e30, _str: "Crypto's reserved" });
    assertAssetClassReserve({ _assetClassIndex: 1, _reserved: 2_700 * 1e30, _str: "Equity's reserved" });
    assertAssetClassReserve({ _assetClassIndex: 2, _reserved: 0, _str: "Forex's reserved" });

    // WETH's market
    assertMarketLongPosition({
      _marketIndex: wethMarketIndex,
      _positionSize: 3_000 * 1e30,
      _avgPrice: 1_500.0075 * 1e30,
      _str: "WETH: "
    });
    assertMarketShortPosition({ _marketIndex: wethMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "WETH: " });

    // JPY's market
    assertMarketLongPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "JPY: " });
    assertMarketShortPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "JPY: " });

    // WBTC's market
    assertMarketLongPosition({
      _marketIndex: wbtcMarketIndex,
      _positionSize: 30_000 * 1e30,
      _avgPrice: 20001 * 1e30,
      _str: "WBTC: "
    });
    assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "WBTC: " });

    // APPLE's market
    assertMarketLongPosition({
      _marketIndex: appleMarketIndex,
      _positionSize: 3000 * 1e30,
      _avgPrice: 151.99924 * 1e30,
      _str: "APPLE: "
    });
    assertMarketShortPosition({
      _marketIndex: appleMarketIndex,
      _positionSize: 3000 * 1e30,
      _avgPrice: 151.999239999999999999999999999999 * 1e30,
      _str: "APPLE: "
    });

    // ### Scenario: Max position changed and Alice could close position
    // When Admin set max position to be 1
    configStorage.setTradingConfig(
      IConfigStorage.TradingConfig({
        fundingInterval: 1, // second
        devFeeRateBPS: 1500, // 15%
        minProfitDuration: 15, // second
        maxPosition: 1
      })
    );

    // Then Alice should't open more position at JPY
    marketSell(
      ALICE,
      0,
      jpyMarketIndex,
      3_000 * 1e30,
      address(0),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_BadNumberOfPosition()"
    );

    // And Alice could close APPLE position
    marketSell(ALICE, 0, appleMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // And Apple position size should be 0
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
  }
}
