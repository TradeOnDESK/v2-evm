// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { console2 } from "forge-std/console2.sol";

contract TC04 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // TC04 - manage position, adjust and flip
  function testCorrectness_TC04_AdjustPositionWithFlipDirection() external {
    // prepare token for wallet

    // mint native token
    vm.deal(BOB, 1 ether);
    vm.deal(ALICE, 1 ether);
    vm.deal(FEEVER, 1 ether);

    // mint BTC
    wbtc.mint(ALICE, 100 * 1e8);
    wbtc.mint(BOB, 100 * 1e8);

    // warp to block timestamp 1000
    vm.warp(1000);

    // Scenario: Trader able to adjust position and support flip position direction
    // Given Bob provide 1 btc as liquidity
    // And Btc price is 20,000 USD
    // And WETH price is 1,500 USD
    updatePriceData = new bytes[](2);
    // updatePriceData[0] = _createPriceFeedUpdateData(wethAssetId, 1500 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    tickPrices[0] = 73135;
    tickPrices[1] = 99039;
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    address _aliceSubAccount0 = getSubAccount(ALICE, 0);

    // When Alice deposit 1 btc as Collateral
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);
    {
      // Then Alice should has btc balance 1 btc
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 1 * 1e8, "T1: ");
    }

    // Scenario: Alice open long position and increase long position
    // When Alice open long position 15,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 15_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct long position
      // premium before = 0
      // premium after  = 15000 / 300000000 = 0.00005
      // premium        = (0 + 0.00005) / 2 = 0.000025
      // adaptive price = 1500 * (1 + 0.000025) = 1500.0375
      // average price  = 1500.0375
      // IMR (IMF 1%)   = 15000 * 1% = 150
      // MMR (MMF 0.5%) = 15000 * 0.5% = 75
      // Reserve        = 150 * 900% = 1350
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(15000 * 1e30),
        _avgPrice: 1_500.0375 * 1e30,
        _reserveValue: 1350 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T2: "
      });

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 150 * 1e30, _mmr: 75 * 1e30, _str: "T2: " });
    }

    // And Alice increase long position for 3,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct long position
      // market skew          = 15000
      // new market skew      = 15000 + 3000 = 18000
      // premium before       = 15000 / 300000000 = 0.00005
      // premium after        = 18000 / 300000000 = 0.00006
      // premium when close   = (15000 - 15000) / 300000000 = 0
      // premium              = (0.00005 + 0.00006) / 2 = 0.000055
      // adaptive price       = 1500 * (1 + 0.000055) = 1500.0825
      // premium when close   = (0.00005 + 0) / 2 = 0.000025
      // close price          = 1500 * (1 + 0.000025) = 1500.0375

      // POSITION BEFORE
      // position size    = 15000
      // average price    = 1500.0375

      // POSITION AFTER
      // position size      = 18000
      // IMR (IMF 1%)       = 18000 * 1% = 180
      // MMR (MMF 0.5%)     = 18000 * 0.5% = 90
      // Reserve            = 180 * 900% = 1620

      // -- New Average Entry price
      // pnl (long)             = 15000 * (close price - average price) / average price
      //                        = 15000 * (1500.0375 - 1500.0375) / 1500.0375
      //                        = 0
      // new premium when close = (new market skew - new position size) / max skew scale
      //                        = (18000 - 18000) / 300000000 = 0
      // new premium            = (premium after + new premium when close) / 2
      //                        = (0.00006 + 0) / 2 = 0.00003
      // new close price        = 1500 * (1 + 0.00003) = 1500.045
      // new average price      = 1500.045 * 18000 / 18000 + 0 = 1500.045
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(18000 * 1e30),
        _avgPrice: 1500.045 * 1e30,
        _reserveValue: 1620 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T2: "
      });

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 180 * 1e30, _mmr: 90 * 1e30, _str: "T2: " });

      // And asset class reservce should be corrected
      assertAssetClassReserve({ _assetClassIndex: 0, _reserved: 1620 * 1e30, _str: "T2: " });
      assertAssetClassReserve({ _assetClassIndex: 1, _reserved: 0, _str: "T2: " });
      assertAssetClassReserve({ _assetClassIndex: 2, _reserved: 0, _str: "T2: " });

      // And market position size shoule be corrected
      assertMarketLongPosition({
        _marketIndex: wethMarketIndex,
        _positionSize: 18000 * 1e30, // 15000 + 3000
        _avgPrice: 1500.045 * 1e30,
        _str: "T2: "
      });
      assertMarketShortPosition({ _marketIndex: wethMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T2: " });
    }

    // Scenario: Alice decrease long position and flip to short position
    // When Alice decrease long position 21,000 USD
    marketSell(ALICE, 0, wethMarketIndex, 21_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // note: decrease size is greater than position size for 3,000 USD
      //       this action will separated to 2 steps
      //       1. decrease long  18,000 USD
      //       2. increase short  3,000 USD
      // Then Alice should has correct short position
      // Calculation after closed long position
      // -----
      // Calculation after open new short position
      // market skew      = 0
      // new market skew  = 0 - 3000 = -3000
      // premium before   = 0 / 300000000 = 0
      // premium after    = -3000 / 300000000 = -0.00001
      // premium          = (0 + (-0.00001)) / 2 = -0.000005
      // adaptive price   = 1500 * (1 + (-0.000005)) = 1499.9925

      // IMR (IMF 1%)     = 3000 * 1% = 30
      // MMR (MMF 0.5%)   = 3000 * 0.5% = 15
      // Reserve          = 30 * 900% = 270

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: -int256(3000 * 1e30),
        _avgPrice: 1499.9925 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T3: "
      });

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 30 * 1e30, _mmr: 15 * 1e30, _str: "T3: " });

      // And asset class reservce should be corrected
      assertAssetClassReserve({ _assetClassIndex: 0, _reserved: 270 * 1e30, _str: "T3: " });
      assertAssetClassReserve({ _assetClassIndex: 1, _reserved: 0, _str: "T3: " });
      assertAssetClassReserve({ _assetClassIndex: 2, _reserved: 0, _str: "T3: " });

      // And market position size shoule be corrected
      assertMarketLongPosition({ _marketIndex: wethMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T3: " });
      assertMarketShortPosition({
        _marketIndex: wethMarketIndex,
        _positionSize: 3000 * 1e30,
        _avgPrice: 1499.9925 * 1e30,
        _str: "T3: "
      });
    }

    // Scenario: Alice increase short position
    // When Alice increase short position for 3,000 USD
    marketSell(ALICE, 0, wethMarketIndex, 3000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct position
      // market skew          = -3000
      // new market skew      = -3000 + (-3000) = -6000
      // premium before       = -3000 / 300000000 = -0.00001
      // premium after        = -6000 / 300000000 = -0.00002
      // premium when close   = (-3000 - -3000) / 300000000 = 0
      // premium              = (-0.00001 + -0.00002) / 2 = -0.000015
      // adaptive price       = 1500 * (1 + -0.000015) = 1499.9775
      // premium when close   = (-0.00001 + 0) / 2 = -0.000005
      // close price          = 1500 * (1 + -0.000005) = 1499.9925

      // POSITION BEFORE
      // position size    = -3000
      // average price    = 1499.9925

      // POSITION AFTER
      // position size      = -3000 + -3000 = -6000
      // IMR (IMF 1%)       = 6000 * 1% = 60
      // MMR (MMF 0.5%)     = 6000 * 0.5% = 30
      // Reserve            = 60 * 900% = 540

      // -- New Average Entry price
      // pnl (short)            = 3000 * (average price - close price) / average price
      //                        = 3000 * (1499.9925 - 1499.9925) / 1499.9925
      //                        = 0
      // new premium when close = (new market skew - new position size) / max skew scale
      //                        = (-6000 - -6000) / 300000000 = 0
      // new premium            = (premium after + new premium when close) / 2
      //                        = (-0.00002 + 0) / 2 = -0.00001
      // new close price        = 1500 * (1 + -0.00001) = 1499.985
      // new average price      = 1499.985 * 18000 / 18000 + 0 = 1499.985
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: -int256(6000 * 1e30),
        _avgPrice: 1499.985 * 1e30,
        _reserveValue: 540 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T4: "
      });

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 60 * 1e30, _mmr: 30 * 1e30, _str: "T4: " });
    }

    // When Alice decrease short position for 30,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 30_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // note: decrease size is greater than position size for 30_000 - 6000 = 24000 USD
      //       this action will separated to 2 steps
      //       1. decrease short  6,000 USD
      //       2. increase long  24,000 USD
      // Then Alice should has correct long position
      // Calculation after closed long position
      // -----
      // Calculation after open new long position
      // market skew      = 0
      // new market skew  = 0 + 24000 = 24000
      // premium before   = 0 / 300000000 = 0
      // premium after    = 24000 / 300000000 = 0.00008
      // premium          = (0 + (0.00008)) / 2 = 0.00004
      // adaptive price   = 1500 * (1 + (0.00004)) = 1500.06
      // IMR (IMF 1%)     = 24000 * 1% = 240
      // MMR (MMF 0.5%)   = 24000 * 0.5% = 120
      // Reserve          = 240 * 900% = 2160
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(24000 * 1e30),
        _avgPrice: 1500.06 * 1e30,
        _reserveValue: 2160 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T5: "
      });

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 240 * 1e30, _mmr: 120 * 1e30, _str: "T5: " });

      // And asset class reservce should be corrected
      assertAssetClassReserve({ _assetClassIndex: 0, _reserved: 2160 * 1e30, _str: "T5: " });
      assertAssetClassReserve({ _assetClassIndex: 1, _reserved: 0, _str: "T5: " });
      assertAssetClassReserve({ _assetClassIndex: 2, _reserved: 0, _str: "T5: " });

      // And market position size shoule be corrected
      assertMarketLongPosition({
        _marketIndex: wethMarketIndex,
        _positionSize: 24000 * 1e30,
        _avgPrice: 1500.06 * 1e30,
        _str: "T5: "
      });
      assertMarketShortPosition({ _marketIndex: wethMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T5: " });
    }
  }
}
