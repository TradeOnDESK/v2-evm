// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

import { console2 } from "forge-std/console2.sol";

contract TC04_1 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  function setUp() external {
    configStorage.setConfigExecutor(address(this), true);

    // Raised maxProfitRateBPS so that positions can be increased
    uint256[] memory marketIndexes = new uint256[](2);
    marketIndexes[0] = wbtcMarketIndex;
    marketIndexes[1] = jpyMarketIndex;
    uint32[] memory _imfs = new uint32[](2);
    _imfs[0] = 100;
    _imfs[1] = 10;
    uint32[] memory maxProfitRateBPSs = new uint32[](2);
    maxProfitRateBPSs[0] = 1500_00; // 1500%
    maxProfitRateBPSs[1] = 1500_00; // 1500%
    configStorage.setMarketIMFAndMaxProfit(marketIndexes, _imfs, maxProfitRateBPSs);
  }

  // ## TC04.1 - manage position, adjust with profit and loss
  function testCorrectness_TC04_1_AveragePriceCalculationWithIncreasePosition() external {
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

    // ### Scenario: Prepare environment
    // Given Bob provide 1 btc as liquidity
    // And Btc price is 20,000 USD
    // And JPY price is 0.007346297098947275625720855402 USD (136.123 USDJPY)
    updatePriceData = new bytes[](2);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(jpyAssetId, 136.123 * 1e3, 0);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[6] = 49138; // JPY tick price $136.123
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    address _aliceSubAccount0 = getSubAccount(ALICE, 0);
    address _bobSubAccount0 = getSubAccount(BOB, 0);

    // When Alice deposit 1 btc as Collateral
    // And Bob deposit 1 btc as Collateral
    // Then Alice should has btc balance 1 btc
    // And Bob also should has btc balance 1 btc
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);
    assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 1 * 1e8, "T0: ");
    depositCollateral(BOB, 0, wbtc, 1 * 1e8);
    assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 1 * 1e8, "T0: ");

    // ### Scenario: Alice open & update long position with profit (BTC)
    // When Alice open long position 1,000 USD
    marketBuy(ALICE, 0, wbtcMarketIndex, 1_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // market skew              = 0
      // position size            = 0
      // position's size delta    = 1000
      // new market skew          = 0 + 1000 = 1000
      // new position size        = 0 + 1000 = 1000
      // premium before           = market skew / max scale
      //                          = 0 / 300000000 = 0
      // premium after            = market skew + size delta / max scale
      //                          = 0 + 1000 / 300000000 = 0.000003333333333333333333333333
      // actual premium           = (0 + 0.000003333333333333333333333333) / 2 = 0.000001666666666666666666666666
      // adaptive price           = 20000 * (1 + 0.000001666666666666666666666666) = 20000.03333333333333333333333332

      // close price
      // premium before           = market skew / max scale
      //                          = 0 / 300000000 = 0
      // premium after            = market skew - position size / max scale
      //                          = 0 - 0 / 300000000 = 0
      // close premium            = (0 + 0) / 2 = 0
      // close price              = 20000 * (1 + 0) = 20000

      // next close price
      // premium before           = new market skew / max scale
      //                          = 1000 / 300000000 = 0.000003333333333333333333333333
      // premium after            = new market skew - new position size / max scale
      //                          = 1000 - 1000 / 300000000 = 0
      // actual premium           = (0.000003333333333333333333333333 + 0) / 2 = 0.000001666666666666666666666666
      // next close price         = 20000 * (1 + 0.000001666666666666666666666666) = 20000.03333333333333333333333332

      // new position's average price
      // average price            = 0 (new position)
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 0 * (20000 - 0) / 0
      //                          = 0
      // divisor                  = new position size + pnl = 1000 + 0 = 1000
      // new entry average price  = next close price * new position size / divisor
      //                          = 20000.03333333333333333333333332 * 1000 / 1000

      // Then Alice should has correct long position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1000 * 1e30),
        _avgPrice: 20000.03333333333333333333333332 * 1e30,
        _reserveValue: 150 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T1: "
      });

      // new market's long average price
      // market's average price   = 0 (new position)
      // market's pnl             = position size * (position's close price - average price) / average price
      //                          = 0 * (20000 - 0) / 0 = 0
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 0 - 0 = 0
      // divisor                  = new market's position + actual market's pnl (- for SHORT)
      //                          = 1000 + 0
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 20000.03333333333333333333333332 * 1000 / 1000 = 20000.03333333333333333333333332

      // And market's state should be corrected
      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 1000 * 1e30,
        _avgPrice: 20000.03333333333333333333333332 * 1e30,
        _str: "T1: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T1: " });
    }

    // When BTC price is pump to 22,000 USD
    skip(60);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 22_000 * 1e8, 0);
    tickPrices[1] = 99993; // WBTC tick price $22,000
    // And Alice increase long position for 100 USD
    marketBuy(ALICE, 0, wbtcMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // market skew              = 1000
      // position size            = 1000
      // position's size delta    = 100
      // new market skew          = 1000 + 100 = 1100
      // new position size        = 1000 + 100 = 1100
      // premium before           = market skew / max scale
      //                          = 1000 / 300000000 = 0.000003333333333333333333333333
      // premium after            = market skew + size delta / max scale
      //                          = (1000 + 100) / 300000000 = 0.000003666666666666666666666666
      // actual premium           = (0.000003333333333333333333333333 + 0.000003666666666666666666666666) / 2
      //                          = 0.000003499999999999999999999999
      // adaptive price           = 22000 * (1 + 0.000003499999999999999999999999) = 22000.076999999999999999999999978

      // close price
      // premium before           = market skew / max scale
      //                          = 1000 / 300000000 = 0.000003333333333333333333333333
      // premium after            = market skew - position size / max scale
      //                          = 1000 - 1000 / 300000000 = 0
      // close premium            = (0.000003333333333333333333333333 + 0) / 2 = 0.000001666666666666666666666666
      // close price              = 22000 * (1 + 0.000001666666666666666666666666) = 22000.036666666666666666666666652

      // next close price
      // premium before           = new market skew / max scale
      //                          = 1100 / 300000000 = 0.000003666666666666666666666666
      // premium after            = new market skew - new position size / max scale
      //                          = 1100 - 1100 / 300000000 = 0
      // actual premium           = (0.000003666666666666666666666666 + 0) / 2 = 0.000001833333333333333333333333
      // next close price         = 22000 * (1 + 0.000001833333333333333333333333) = 22000.040333333333333333333333326

      // new position's average price
      // average price            = 20000.03333333333333333333333332
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 1000 * (22000.036666666666666666666666652 - 20000.03333333333333333333333332) / 20000.03333333333333333333333332
      //                          = 100
      // divisor                  = new position size + pnl = 1100 + 100 = 1200
      // new entry average price  = next close price * new position size / divisor
      //                          = 22000.040333333333333333333333326 * 1100 / 1200
      //                          = 20166.703638888888888888888888882166

      // Then Alice should has correct long position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1100 * 1e30),
        _avgPrice: 20166.703638888888888888888888882166 * 1e30,
        _reserveValue: 165 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 41032091620931,
        _lastFundingAccrued: -79999999980,
        _str: "T2: "
      });

      // new market's long average price
      // market's average price   = 20000.03333333333333333333333332
      // market's pnl             = position size * (position's close price - average price) / average price
      //                          = 1000 * (22000.036666666666666666666666652 - 20000.03333333333333333333333332) / 20000.03333333333333333333333332
      //                          = 100
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 100 - 0 = 100
      // divisor                  = new market's position + actual market's pnl (- for SHORT)
      //                          = 1100 + 100
      //                          = 1200
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 22000.040333333333333333333333326 * 1100 / 1200
      //                          = 20166.703638888888888888888888882166

      // And market's state should be corrected
      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 1100 * 1e30,
        _avgPrice: 20166.703638888888888888888888882166 * 1e30,
        _str: "T2: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T2: " });
    }

    // ### Scenario: Bob open & update long position with loss (BTC)
    // When Bob open long position 1,000 USD
    marketBuy(BOB, 0, wbtcMarketIndex, 1_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // market skew              = 1100
      // position size            = 0
      // position's size delta    = 1000
      // new market skew          = 1100 + 1000 = 2100
      // new position size        = 0 + 1000 = 1000
      // premium before           = market skew / max scale
      //                          = 1100 / 300000000 = 0.000003666666666666666666666666
      // premium after            = market skew + size delta / max scale
      //                          = (1100 + 1000) / 300000000 = 0.000007
      // actual premium           = (0.000003666666666666666666666666 + 0.000007) / 2
      //                          = 0.000005333333333333333333333333
      // adaptive price           = 22000 * (1 + 0.000005333333333333333333333333)
      //                          = 22000.117333333333333333333333326

      // close price
      // premium before           = market skew / max scale
      //                          = 1100 / 300000000 = 0.000003666666666666666666666666
      // premium after            = market skew - position size / max scale
      //                          = 1100 - 0 / 300000000 = 0.000003666666666666666666666666
      // close premium            = (0.000003666666666666666666666666 + 0.000003666666666666666666666666) / 2
      //                          = 0.000003666666666666666666666666
      // close price              = 22000 * (1 + 0.000003666666666666666666666666)
      //                          = 22000.080666666666666666666666652

      // next close price
      // premium before           = new market skew / max scale
      //                          = 2100 / 300000000 = 0.000007
      // premium after            = new market skew - new position size / max scale
      //                          = 2100 - 1000 / 300000000 = 0.000003666666666666666666666666
      // actual premium           = (0.000007 + 0.000003666666666666666666666666) / 2
      //                          = 0.000005333333333333333333333333
      // next close price         = 22000 * (1 + 0.000005333333333333333333333333)
      //                          = 22000.117333333333333333333333326

      // new position's average price
      // average price            = 0 (new position)
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 0 * (22000.036666666666666666666666652 - 0) / 0
      //                          = 0
      // divisor                  = new position size + pnl = 1000 + 0 = 1000
      // new entry average price  = next close price * new position size / divisor
      //                          = 22000.117333333333333333333333326 * 1000 / 1000
      //                          = 22000.117333333333333333333333326

      // Then Bob should has correct long position
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1000 * 1e30),
        _avgPrice: 22000.117333333333333333333333326 * 1e30,
        _reserveValue: 150 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 41032091620931,
        _lastFundingAccrued: -79999999980,
        _str: "T3: "
      });

      // new market's long average price
      // market's average price   = 20166.703638888888888888888888882166
      // market's pnl             = position size * (position's close price - average price) / average price
      //                          = 1100 * (22000.080666666666666666666666652 - 20166.703638888888888888888888882166) / 20166.703638888888888888888888882166
      //                          = 100.002199995966674061097554654083
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 100.002199995966674061097554654083 - 0 = 100.002199995966674061097554654083
      // divisor                  = new market's position + actual market's pnl (- for SHORT)
      //                          = 2100 + 100.002199995966674061097554654083
      //                          = 2200.002199995966674061097554654083
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 22000.117333333333333333333333326 * 2100 / 2200.002199995966674061097554654083
      //                          = 21000.090999947500148749578542857614

      // And market's state should be corrected
      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 2100 * 1e30,
        _avgPrice: 21000.090999947500148749578542857614 * 1e30,
        _str: "T3: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T3: " });
    }

    // When BTC price is dump to 20,000 USD
    skip(60);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20_000 * 1e8, 0);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    // And Bob increase long position for 100 USD
    marketBuy(BOB, 0, wbtcMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // market skew              = 2100
      // position size            = 1000
      // position's size delta    = 100
      // new market skew          = 2100 + 100 = 2200
      // new position size        = 1000 + 100 = 1100
      // premium before           = market skew / max scale
      //                          = 2100 / 300000000 = 0.000007
      // premium after            = market skew + size delta / max scale
      //                          = (2100 + 100) / 300000000 = 0.000007333333333333333333333333
      // actual premium           = (0.000007 + 0.000007333333333333333333333333) / 2
      //                          = 0.000007166666666666666666666666
      // adaptive price           = 20000 * (1 + 0.000007166666666666666666666666)
      //                          = 20000.14333333333333333333333332

      // close price
      // premium before           = market skew / max scale
      //                          = 2100 / 300000000 = 0.000007
      // premium after            = market skew - position size / max scale
      //                          = 2100 - 1000 / 300000000 = 0.000003666666666666666666666666
      // close premium            = (0.000007 + 0.000003666666666666666666666666) / 2
      //                          = 0.000005333333333333333333333333
      // close price              = 20000 * (1 + 0.000005333333333333333333333333)
      //                          = 20000.10666666666666666666666666

      // next close price
      // premium before           = new market skew / max scale
      //                          = 2200 / 300000000 = 0.000007333333333333333333333333
      // premium after            = new market skew - new position size / max scale
      //                          = 2200 - 1100 / 300000000 = 0.000003666666666666666666666666
      // actual premium           = (0.000007333333333333333333333333 + 0.000003666666666666666666666666) / 2
      //                          = 0.000005499999999999999999999999
      // next close price         = 20000 * (1 + 0.000005499999999999999999999999)
      //                          = 20000.10999999999999999999999998

      // new position's average price
      // average price            = 22000.117333333333333333333333326
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 1000 * (20000.10666666666666666666666666 - 22000.117333333333333333333333326) / 22000.117333333333333333333333326
      //                          = -90.909090909090909090909090909090
      // divisor                  = new position size + pnl = 1100 + -90.909090909090909090909090909090
      //                          = 1009.09090909090909090909090909091
      // new entry average price  = next close price * new position size / divisor
      //                          = 20000.10999999999999999999999998 * 1100 / 1009.09090909090909090909090909091
      //                          = 21801.921711711711711711711711689890

      // Then Bob should has correct long position
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1100 * 1e30),
        _avgPrice: 21801.921711711711711711711711689890 * 1e30,
        _reserveValue: 165 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 135824263179369,
        _lastFundingAccrued: -1639,
        _str: "T4: "
      });

      // new market's long average price
      // market's average price   = 21000.090999947500148749578542857614
      // market's pnl             = position size * (position's close price - average price) / average price
      //                          = 2100 * (20000.10666666666666666666666666 - 21000.090999947500148749578542857614) / 21000.090999947500148749578542857614
      //                          = -99.998000003666659944456768496288
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = -99.998000003666659944456768496288 - 0 = -99.998000003666659944456768496288
      // divisor                  = new market's position + actual market's pnl (- for SHORT)
      //                          = 2200 + -99.998000003666659944456768496288
      //                          = 2100.001999996333340055543231503712
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 20000.10999999999999999999999998 * 2200 / 2100.001999996333340055543231503712
      //                          = 20952.476235773501932546203780002303

      // And market's state should be corrected
      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 2200 * 1e30,
        _avgPrice: 20952.476235773501932546203780002303 * 1e30,
        _str: "T4: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T3: " });
    }

    // ### Scenario: Alice open & update short position with loss (JPY)
    // When Alice open short position 1,000 USD
    marketSell(ALICE, 0, jpyMarketIndex, 1_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // oracle price             = 0.007346297098947275625720855402 USD
      // market skew              = 0
      // position size            = 0
      // position's size delta    = -1000
      // new market skew          = 0 - 1000 = -1000
      // new position size        = 0 - 1000 = -1000
      // premium before           = market skew / max scale
      //                          = 0 / 300000000 = 0
      // premium after            = market skew + size delta / max scale
      //                          = 0 - 1000 / 300000000 = -0.000003333333333333333333333333
      // actual premium           = (0 - 0.000003333333333333333333333333) / 2 = -0.000001666666666666666666666666
      // adaptive price           = 0.007346297098947275625720855402 * (1 - 0.000001666666666666666666666666)
      //                          = 0.007346284855118777380261479200

      // close price
      // premium before           = market skew / max scale
      //                          = 0 / 300000000 = 0
      // premium after            = market skew - position size / max scale
      //                          = 0 - 0 / 300000000 = 0
      // close premium            = (0 + 0) / 2 = 0
      // close price              = 0.007346297098947275625720855402 * (1 + 0)
      //                          = 0.007346297098947275625720855402

      // next close price
      // premium before           = new market skew / max scale
      //                          = -1000 / 300000000 = 0.000003333333333333333333333333
      // premium after            = new market skew - new position size / max scale
      //                          = -1000 - (-1000) / 300000000 = 0
      // actual premium           = (-0.000003333333333333333333333333 + 0) / 2 = -0.000001666666666666666666666666
      // next close price         = 0.007346297098947275625720855402 * (1 - 0.000001666666666666666666666666)
      //                          = 0.007346284855118777380261479200

      // new position's average price
      // average price            = 0 (new position)
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 0 * (0 - 0.007346297098947275625720855402) / 0
      //                          = 0
      // divisor                  = new position size + pnl = 1000 + 0 = 1000
      // new entry average price  = next close price * new position size / divisor
      //                          = 0.007346284855118777380261479200 * 1000 / 1000

      // Then Alice should has correct long position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: -int256(1000 * 1e30),
        _avgPrice: 0.007346284855118777380261479200 * 1e30,
        _reserveValue: 15 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T5: "
      });

      // And market's state should be corrected
      assertMarketLongPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T5: " });

      // new market's short average price
      // market's average price   = 0 (first position)
      // market's pnl             = position size * (average price - position's close price) / average price
      //                          = 0 * (0 - 0.007346297098947275625720855402) / 0 = 0
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 0 - 0 = 0
      // divisor                  = new market's position - actual market's pnl
      //                          = -1000 - 0
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 0.007346284855118777380261479200 * 1000 / 1000
      //                          = 0.007346284855118777380261479200
      assertMarketShortPosition({
        _marketIndex: jpyMarketIndex,
        _positionSize: 1000 * 1e30,
        _avgPrice: 0.007346284855118777380261479200 * 1e30,
        _str: "T5: "
      });
    }

    skip(60);
    // updatePriceData[1] = _createPriceFeedUpdateData(jpyAssetId, 134.775 * 1e3, 0);
    tickPrices[6] = 49038; // JPY tick price $134.775
    // When JPY price is pump to 0.007419773696902244481543312928 USD (134.775 USDJPY)
    // And Alice increase short position for 100 USD
    marketSell(ALICE, 0, jpyMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // oracle price             = 0.007419773696902244481543312928 USD
      // market skew              = -1000
      // position size            = -1000
      // position's size delta    = -100
      // new market skew          = -1000 + -100 = -1100
      // new position size        = -1000 + -100 = -1100
      // premium before           = market skew / max scale
      //                          = -1000 / 300000000 = -0.000003333333333333333333333333
      // premium after            = market skew + size delta / max scale
      //                          = (-1000 - 100) / 300000000 = -0.000003666666666666666666666666
      // actual premium           = (-0.000003333333333333333333333333 -0.000003666666666666666666666666) / 2
      //                          = -0.000003499999999999999999999999
      // adaptive price           = 0.007419773696902244481543312928 * (1 - 0.000003499999999999999999999999)
      //                          = 0.007419747727694305323687627526

      // close price
      // premium before           = market skew / max scale
      //                          = -1000 / 300000000 = -0.000003333333333333333333333333
      // premium after            = market skew - position size / max scale
      //                          = -1000 - (-1000) / 300000000 = 0
      // close premium            = (-0.000003333333333333333333333333 + 0) / 2 = -0.000001666666666666666666666666
      // close price              = 0.007419773696902244481543312928 * (1 - 0.000001666666666666666666666666)
      //                          = 0.007419761330612749644469177022

      // next close price
      // premium before           = new market skew / max scale
      //                          = -1100 / 300000000 = -0.000003666666666666666666666666
      // premium after            = new market skew - new position size / max scale
      //                          = -1100 - (-1100) / 300000000 = 0
      // actual premium           = (-0.000003666666666666666666666666 + 0) / 2 = -0.000001833333333333333333333333
      // next close price         = 0.007419773696902244481543312928 * (1 - 0.000001833333333333333333333333)
      //                          = 0.007419760093983800160761763431

      // new position's average price
      // average price            = 0.007346284855118777380261479200
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = -1000 * (0.007346284855118777380261479200 - 0.007419761330612749644469177022) / 0.007346284855118777380261479200
      //                          = 10.001854943424225561120385826666 (loss)
      // divisor                  = new position size - pnl = -1100 - (10.001854943424225561120385826666)
      //                          = -1110.001854943424225561120385826666
      // new entry average price  = next close price * new position size / divisor
      //                          = 0.007419760093983800160761763431 * -1100 / -1110.001854943424225561120385826666
      //                          = 0.007352903120867465906419653230

      // Then Alice should has correct long position
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: -int256(1100 * 1e30),
        _avgPrice: 0.007352903120867465906419653230 * 1e30,
        _reserveValue: 16.5 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 13541730508752,
        _lastFundingAccrued: 321,
        _str: "T6: "
      });

      // And market's state should be corrected
      assertMarketLongPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T6: " });

      // new market's short average price
      // market's average price   = 0.007346284855118777380261479200
      // market's pnl             = position size * (average price - position's close price) / average price
      //                          = -1000 * (0.007346284855118777380261479200 - 0.007419761330612749644469177022) / 0.007346284855118777380261479200
      //                          = 10.001854943424225561120385826666 (loss)
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 10.001854943424225561120385826666 - 0 = 10.001854943424225561120385826666
      // divisor                  = new market's position - actual market's pnl
      //                          = -1100 - 10.001854943424225561120385826666
      //                          = -1110.001854943424225561120385826666
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 0.007419760093983800160761763431 * -1100 / -1110.001854943424225561120385826666
      //                          = 0.007352903120867465906419653230
      assertMarketShortPosition({
        _marketIndex: jpyMarketIndex,
        _positionSize: 1100 * 1e30,
        _avgPrice: 0.007352903120867465906419653230 * 1e30,
        _str: "T6: "
      });
    }

    // ### Scenario: Bob open & update short position with profit (JPY)
    // When Bob open short position 1,000 USD
    marketSell(BOB, 0, jpyMarketIndex, 1_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // oracle price             = 0.007419773696902244481543312928 USD
      // market skew              = -1100
      // position size            = 0
      // position's size delta    = -1000
      // new market skew          = -1100 - 1000 = -2100
      // new position size        = 0 - 1000 = -1000
      // premium before           = market skew / max scale
      //                          = -1100 / 300000000 = -0.000003666666666666666666666666
      // premium after            = market skew + size delta / max scale
      //                          = (-1100 - 1000) / 300000000 = -0.000007
      // actual premium           = (-0.000003666666666666666666666666 - 0.000007) / 2
      //                          = -0.000005333333333333333333333333
      // adaptive price           = 0.007419773696902244481543312928 * (1 - 0.000005333333333333333333333333)
      //                          = 0.007419734124775861002906078030

      // close price
      // premium before           = market skew / max scale
      //                          = -1100 / 300000000 = -0.000003666666666666666666666666
      // premium after            = market skew - position size / max scale
      //                          = -1100 - 0 / 300000000 = -0.000003666666666666666666666666
      // close premium            = (-0.000003666666666666666666666666 - 0.000003666666666666666666666666) / 2
      //                          = -0.000003666666666666666666666666
      // close price              = 0.007419773696902244481543312928 * (1 - 0.000003666666666666666666666666)
      //                          = 0.007419746491065355839980213935

      // next close price
      // premium before           = new market skew / max scale
      //                          = -2100 / 300000000 = -0.000007
      // premium after            = new market skew - new position size / max scale
      //                          = -2100 + 1000 / 300000000 = -0.000003666666666666666666666666
      // actual premium           = (-0.000007 - 0.000003666666666666666666666666) / 2
      //                          = -0.000005333333333333333333333333
      // next close price         = 0.007419773696902244481543312928 * (1 - 0.000005333333333333333333333333)
      //                          = 0.007419734124775861002906078030

      // new position's average price
      // average price            = 0 (new position)
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = 0 * (0 - 22000.036666666666666666666666652) / 0
      //                          = 0
      // divisor                  = new position size + pnl = -1000 - 0 = -1000
      // new entry average price  = next close price * new position size / divisor
      //                          = 0.007419734124775861002906078030 * -1000 / -1000
      //                          = 0.007419734124775861002906078030

      // Then Bob should has correct long position
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: -int256(1000 * 1e30),
        _avgPrice: 0.007419734124775861002906078030 * 1e30,
        _reserveValue: 15 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 13541730508752,
        _lastFundingAccrued: 321,
        _str: "T7: "
      });
      // And market's state should be corrected
      assertMarketLongPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T7: " });
      // new market's short average price
      // market's average price   = 0.007352903120867465906419653230
      // market's pnl             = position size * (average price - position's close price) / average price
      //                          = -1100 * (0.007352903120867465906419653230 - 0.007419746491065355839980213935) / 0.007352903120867465906419653230
      //                          = 9.999819936292649542150822360909 (loss)
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = 9.999819936292649542150822360909 - 0 = 9.999819936292649542150822360909
      // divisor                  = new market's position - actual market's pnl
      //                          = -2100 - 9.999819936292649542150822360909
      //                          = -2109.999819936292649542150822360909
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 0.007419734124775861002906078030 * -2100 / -2109.999819936292649542150822360909
      //                          = 0.007384570138257054213341721408
      assertMarketShortPosition({
        _marketIndex: jpyMarketIndex,
        _positionSize: 2100 * 1e30,
        _avgPrice: 0.007384570138257054213341721408 * 1e30,
        _str: "T7: "
      });
    }

    skip(60);
    // updatePriceData[1] = _createPriceFeedUpdateData(jpyAssetId, 136.123 * 1e3, 0);
    tickPrices[6] = 49138; // JPY tick price $136.123
    // When JPY price is dump to 0.007346297098947275625720855402 USD (136.123 USDJPY)
    // And Bob increase short position for 100 USD
    marketSell(BOB, 0, jpyMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // oracle price             = 0.007346297098947275625720855402 USD
      // market skew              = -2100
      // position size            = -1000
      // position's size delta    = -100
      // new market skew          = -2100 - 100 = -2200
      // new position size        = -1000 - 100 = -1100
      // premium before           = market skew / max scale
      //                          = -2100 / 300000000 = -0.000007
      // premium after            = market skew + size delta / max scale
      //                          = (-2100 - 100) / 300000000 = -0.000007333333333333333333333333
      // actual premium           = (-0.000007 - 0.000007333333333333333333333333) / 2
      //                          = -0.000007166666666666666666666666
      // adaptive price           = 0.007346297098947275625720855402 * (1 - 0.000007166666666666666666666666)
      //                          = 0.007346244450484733170245537735

      // close price
      // premium before           = market skew / max scale
      //                          = -2100 / 300000000 = -0.000007
      // premium after            = market skew - position size / max scale
      //                          = (-2100 + 1000) / 300000000 = -0.000003666666666666666666666666
      // close premium            = (-0.000007 - 0.000003666666666666666666666666) / 2
      //                          = -0.000005333333333333333333333333
      // close price              = 0.007346297098947275625720855402 * (1 - 0.000005333333333333333333333333)
      //                          = 0.007346257918696081240250851557

      // next close price
      // premium before           = new market skew / max scale
      //                          = -2200 / 300000000 = -0.000007333333333333333333333333
      // premium after            = new market skew - new position size / max scale
      //                          = -2200 + 1100 / 300000000 = -0.000003666666666666666666666666
      // actual premium           = (-0.000007333333333333333333333333 - 0.000003666666666666666666666666) / 2
      //                          = -0.000005499999999999999999999999
      // next close price         = 0.007346297098947275625720855402 * (1 - 0.000005499999999999999999999999)
      //                          = 0.007346256694313231415704913937

      // new position's average price
      // average price            = 0.007419734124775861002906078030
      // note PNL formula:  position size * (close price - average price) / average price [LONG]
      //                    position size * (average price - close price) / average price [SHORT]
      // position pnl             = -1000 * (0.007419734124775861002906078030 - 0.007346257918696081240250851557) / 0.007419734124775861002906078030
      //                          = -9.902808489380927543471713082762 (profit)
      // divisor                  = new position size + pnl = -1100 - (-9.902808489380927543471713082762)
      //                          = -1090.097191510619072456528286917238
      // new entry average price  = next close price * new position size / divisor
      //                          = 0.007346256694313231415704913937 * -1100 / -1090.097191510619072456528286917238
      //                          = 0.007412992553944980466657186968

      // Then Bob should has correct long position
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: -int256(1100 * 1e30),
        _avgPrice: 0.007412992553944980466657186968 * 1e30,
        _reserveValue: 16.5 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 41979364291901,
        _lastFundingAccrued: 1639,
        _str: "T8: "
      });
      // And market's state should be corrected
      assertMarketLongPosition({ _marketIndex: jpyMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T8: " });
      // new market's short average price
      // market's average price   = 0.007384570138257054213341721408
      // market's pnl             = position size * (average price - position's close price) / average price
      //                          = -2100 * (0.007384570138257054213341721408 - 0.007346257918696081240250851557) / 0.007384570138257054213341721408
      //                          = -10.895104193164697795057579475279 (profit)
      // actual market's pnl      = market's pnl - realized position pnl
      //                          = -10.895104193164697795057579475279 - 0 = -10.895104193164697795057579475279
      // divisor                  = new market's position - actual market's pnl
      //                          = -2200 + 10.895104193164697795057579475279
      //                          = -2189.104895806835302204942420524721
      // new average price        = next position's close price * new market's position size / divisor
      //                          = 0.007346256694313231415704913937 * -2200 / -2189.104895806835302204942420524721
      //                          = 0.007382818776042429111766384430
      assertMarketShortPosition({
        _marketIndex: jpyMarketIndex,
        _positionSize: 2200 * 1e30,
        _avgPrice: 0.007382818776042429111766384430 * 1e30,
        _str: "T8: "
      });
    }
  }
}
