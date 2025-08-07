// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { console2 } from "forge-std/console2.sol";

contract TC04_2 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // ## TC04.2 - manage position, adjust with profit and loss
  function testCorrectness_TC04_2_AveragePriceCalculationWithDecreasePosition() external {
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
    // And APPLE price is 150 USD
    updatePriceData = new bytes[](2);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(appleAssetId, 150 * 1e5, 0);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[5] = 50108; // APPL tick price $150
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

    // ### Scenario: Alice & Bob open BTC position at different price
    // When Alice open long position 1,500 USD
    marketBuy(ALICE, 0, wbtcMarketIndex, 1_500 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct long position

      // oracle price       = 20_000
      // market skew        = 0
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * 0) + 1500) / (2 * 300000000) = 0.0000025
      // adaptive price     = oracle price * (1 + premium)
      //                    = 20000 * (1 + 0.0000025) = 20000.05

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * 0) - 0) / (2 * 300000000) = 0
      // close price        = oracle price * (1 + close premium)
      //                    = 20000 * (1 + 0) = 20000

      // next close price
      // new market skew    = +size delta = 0 + 1500 = 1500
      // new position size  = +size delta = 0 + 1500 = 1500
      // new close premium  = ((2 * new market skew) - position size) / (2 * max scale)
      //                    = ((2 * 1500) - 1500) / (2 * 300000000) = 0.0000025
      // next close price   = oracle price * (1 + new close premium)
      //                    = 20000 * (1 + 0.0000025) = 20000.05

      // new LONG average price
      // entry price        = 0 (new position)
      // pnl                = 0 * (20000 - 0) = 0
      // realized pnl       = size delta / position size * pnl
      //                    = 0
      // divisor            = new position size + pnl
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = 20000.05

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1500 * 1e30),
        _avgPrice: 20000.05 * 1e30,
        _reserveValue: 135 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T1: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 0 (first position)
      // pnl                = 0 * (20000 - 0) = 0
      // actual pnl         = pnl - position realized pnl
      //                    = 0
      // divisor            = new market's position size + pnl
      //                    = 1500 + 0
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = 20000.05

      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 1500 * 1e30,
        _avgPrice: 20000.05 * 1e30,
        _str: "T1: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T1: " });
    }

    // When BTC price is pump to 22,000 USD
    skip(60);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 21_000 * 1e8, 0);
    tickPrices[1] = 99527; // WBTC tick price $20,000
    // When Bob open long position 3,000 USD
    marketBuy(BOB, 0, wbtcMarketIndex, 3000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then BOB should has correct long position

      // oracle price       = 21_000
      // market skew        = 1500
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * 1500) + 3000) / (2 * 300000000) = 0.00001
      // adaptive price     = oracle price * (1 + premium)
      //                    = 21_000 * (1 + 0.00001) = 21000.21

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * 1500) - 0) / (2 * 300000000) = 0.000005
      // close price        = oracle price * (1 + close premium)
      //                    = 21_000 * (1 + 0.000005) = 21000.105

      // next close price
      // new market skew    = +size delta = 1500 + 3000 = 4500
      // new position size  = +size delta = 0 + 3000    = 3000
      // new close premium  = ((2 * new market skew) - position size) / (2 * max scale)
      //                    = ((2 * 4500) - 3000) / (2 * 300000000) = 0.00001
      // next close price   = oracle price * (1 + new close premium)
      //                    = 21_000 * (1 + 0.00001) = 21000.21

      // new LONG average price
      // entry price        = 0 (new position)
      // pnl                = 0 * (21000.105 - 0) / 0 = 0
      // realized pnl       = size delta / position size * pnl
      //                    = 0
      // divisor            = new position size + pnl
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = 21000.21

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(3000 * 1e30),
        _avgPrice: 21000.21 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 38687491044562,
        _lastFundingAccrued: -120000000000,
        _str: "T2: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 20000.05
      // pnl                = (1500 * (21000.105 - 20000.05)) / 20000.05
      //                    = 75.003937490156274609313476716308
      // actual pnl         = pnl - position realized pnl
      //                    = 75.003937490156274609313476716308 - 0
      //                    = 75.003937490156274609313476716308
      // divisor            = new market's position size + pnl
      //                    = 4500 + 75.003937490156274609313476716308
      //                    = 4575.003937490156274609313476716308
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (21000.21 * 4500) / 4575.003937490156274609313476716308
      //                    = 20655.926484697879294012208647495529

      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 4500 * 1e30,
        _avgPrice: 20655.926484697879294012208647495529 * 1e30,
        _str: "T2: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T2: " });
    }

    // ### Scenario: Alice partail close & Bob fully close BTC positions
    // When Alice partially close BTC 300 USD (profit)
    marketSell(ALICE, 0, wbtcMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct long position

      // oracle price       = 21_000
      // market skew        = 4500
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * 4500) + -(300)) / (2 * 300000000) = 0.0000145
      // adaptive price     = oracle price * (1 + premium)
      //                    = 21_000 * (1 + 0.0000145) = 21000.3045

      // close price
      // position size      = 1500
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * 4500) - 1500) / (2 * 300000000) = 0.0000125
      // close price        = oracle price * (1 + close premium)
      //                    = 21_000 * (1 + 0.0000125) = 21000.2625

      // next close price
      // new market skew    = +size delta = 4500 + (-300) = 4200
      // new position size  = +size delta = 1500 + (-300) = 1200
      // new close premium  = ((2 * new market skew) - new position size) / (2 * max scale)
      //                    = ((2 * 4200) - 1200) / (2 * 300000000) = 0.000012
      // next close price   = oracle price * (1 + new close premium)
      //                    = 21_000 * (1 + 0.000012) = 21000.252

      // new LONG average price
      // entry price        = 20000.05
      // pnl                = (1500 * (21000.2625 - 20000.05)) / 20000.05
      //                    = 75.015749960625098437253906865232
      // realized pnl       = size delta / position size * pnl
      //                    = 300 / 1500 * 75.015749960625098437253906865232
      //                    = 15.003149992125019687450781373046
      // divisor            = new position size + unrealized pnl
      //                    = 1200 + (75.015749960625098437253906865232 - 15.003149992125019687450781373046)
      //                    = 1260.012599968500078749803125492186
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = (21000.252 * 1200) / 1260.012599968500078749803125492186
      //                    = 20000.040000099998750015624804689945

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: int256(1200 * 1e30),
        _avgPrice: 20000.040000099998750015624804689945 * 1e30,
        _reserveValue: 108 * 1e30,
        _realizedPnl: 15.003149992125019687450781373046 * 1e30,
        _entryBorrowingRate: 38687491044562,
        _lastFundingAccrued: -120000000000,
        _str: "T3: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 20655.926484697879294012208647495529
      // pnl                = (4500 * (21000.2625 - 20655.926484697879294012208647495529)) / 20655.926484697879294012208647495529
      //                    = 75.015374885626045302293070204065
      // actual pnl         = pnl - position realized pnl
      //                    = 75.015374885626045302293070204065 - 15.003149992125019687450781373046
      //                    = 60.012224893501025614842288831019
      // divisor            = new market's position size + pnl
      //                    = 4200 + 60.012224893501025614842288831019
      //                    = 4260.012224893501025614842288831019
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (21000.252 * 4200) / 4260.012224893501025614842288831019
      //                    = 20704.414387497444070718313743274884

      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 4200 * 1e30,
        _avgPrice: 20704.414387497444070718313743274884 * 1e30,
        _str: "T3: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T3: " });
    }

    // When BTC price is dump to 20,000 USD
    skip(60);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20_000 * 1e8, 0);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    // When Bob fully close (loss)
    marketSell(BOB, 0, wbtcMarketIndex, 3_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then BOB should has correct long position

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T4: "
      });

      // And market's state should be corrected

      // oracle price       = 20_000
      // market skew        = 4200
      // max scale          = 300000000

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * 4200) - 3_000) / (2 * 300000000) = 0.000009
      // close price        = oracle price * (1 + close premium)
      //                    = 20_000 * (1 + 0.000009) = 20000.18

      // next close price
      // new market skew    = +size delta = 4200 + (-3000) = 1200
      // new position size  = +size delta = 3000 + (-3000) = 0
      // new close premium  = ((2 * new market skew) - position size) / (2 * max scale)
      //                    = ((2 * 1200) - 0) / (2 * 300000000) = 0.000004
      // next close price   = oracle price * (1 + new close premium)
      //                    = 20_000 * (1 + 0.000004) = 20000.08

      // average price      = 21000.21
      // pnl                = (3000 * (20000.18 - 21000.21)) / 21000.21
      //                    = -142.859999971428857140000028571142
      // realized pnl       = size delta / position size * pnl
      //                    = 3000 / 3000 * -142.859999971428857140000028571142
      //                    = -142.859999971428857140000028571142

      // new market's LONG average price
      // average price      = 20704.414387497444070718313743274884
      // pnl                = (4200 * (20000.18 - 20704.414387497444070718313743274884)) / 20704.414387497444070718313743274884
      //                    = -142.857671418871481043110508948541
      // actual pnl         = pnl - position realized pnl
      //                    = -142.857671418871481043110508948541 - (-142.859999971428857140000028571142)
      //                    = 0.002328552557376096889519622601
      // divisor            = new market's position size + pnl
      //                    = 1200 + 0.002328552557376096889519622601
      //                    = 1200.002328552557376096889519622601
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (20000.08 * 1200) / 1200.002328552557376096889519622601
      //                    = 20000.041190710781452609932471927826

      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 1200 * 1e30,
        _avgPrice: 20000.041190710781452609932471927826 * 1e30,
        _str: "T4: "
      });
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T2: " });
    }

    // ### Scenario: Alice & Bob open APPLE position at different price
    // When Alice open short position 1,500 USD
    marketSell(ALICE, 0, appleMarketIndex, 1_500 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct short position

      // oracle price       = 150
      // market skew        = 0
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * 0) + (-1500)) / (2 * 300000000) = -0.0000025
      // adaptive price     = oracle price * (1 + premium)
      //                    = 150 * (1 + -0.0000025) = 149.999625

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * 0) - 0) / (2 * 300000000) = 0
      // close price        = oracle price * (1 + close premium)
      //                    = 150 * (1 + 0) = 150

      // next close price
      // new market skew    = -size delta = 0 - 1500 = -1500
      // new position size  = -size delta = 0 - 1500 = -1500
      // new close premium  = ((2 * new market skew) - position size) / (2 * max scale)
      //                    = ((2 * 1500) - (-1500)) / (2 * 300000000) = 0.0000025
      // next close price   = oracle price * (1 + new close premium)
      //                    = 150 * (1 + -0.0000025) = 149.999625

      // new LONG average price
      // entry price        = 0 (new position)
      // pnl                = 0 * (150 - 0) = 0
      // realized pnl       = size delta / position size * pnl
      //                    = 0
      // divisor            = new position size + pnl
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = 149.999625

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(1500 * 1e30),
        _avgPrice: 149.999625 * 1e30,
        _reserveValue: 675 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T5: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 0 (first position)
      // pnl                = 0 * (150 - 0) = 0
      // actual pnl         = pnl - position realized pnl
      //                    = 0
      // divisor            = new market's position size + pnl
      //                    = 1500 + 0
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = 149.999625

      assertMarketLongPosition({ _marketIndex: appleMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T5: " });
      assertMarketShortPosition({
        _marketIndex: appleMarketIndex,
        _positionSize: 1500 * 1e30,
        _avgPrice: 149.999625 * 1e30,
        _str: "T5: "
      });
    }

    // When APPLE price is pump to 165 USD
    skip(60);
    // updatePriceData[1] = _createPriceFeedUpdateData(appleAssetId, 165 * 1e5, 0);
    tickPrices[5] = 51062; // APPL tick price $152
    // When Bob open short position 6,000 USD
    marketSell(BOB, 0, appleMarketIndex, 6_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then BOB should has correct long position

      // oracle price       = 165
      // market skew        = -1500
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * -1500) + (-6000)) / (2 * 300000000) = -0.000015
      // adaptive price     = oracle price * (1 + premium)
      //                    = 165 * (1 + (-0.000015)) = 164.997525

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * -1500) - 0) / (2 * 300000000) = -0.000005
      // close price        = oracle price * (1 + close premium)
      //                    = 165 * (1 + (-0.000005)) = 164.999175

      // next close price
      // new market skew    = +size delta = -1500 + (-6000) = -7500
      // new position size  = +size delta = 0 + (-6000)    = -6000
      // new close premium  = ((2 * new market skew) - new position size) / (2 * max scale)
      //                    = ((2 * -7500) - (-6000)) / (2 * 300000000) = -0.000015
      // next close price   = oracle price * (1 + new close premium)
      //                    = 165 * (1 + (-0.000015)) = 164.997525

      // new SHORT average price
      // entry price        = 0 (new position)
      // pnl                = 0 * (164.999175 - 0) / 0 = 0
      // realized pnl       = size delta / position size * pnl
      //                    = 0
      // divisor            = new position size + pnl
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = 164.99835

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(6000 * 1e30),
        _avgPrice: 164.997525 * 1e30,
        _reserveValue: 2700 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 403615566318282,
        _lastFundingAccrued: 120000000000,
        _str: "T6: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 149.999625
      // pnl                = (-1500 * (149.999625 - 164.999175)) / 149.999625
      //                    = 149.995874989687474218685546713866
      // actual pnl         = pnl - position realized pnl
      //                    = 149.995874989687474218685546713866 - 0
      //                    = 149.995874989687474218685546713866
      // divisor            = new market's position size - pnl
      //                    = -7500 - 149.995874989687474218685546713866
      //                    = -7649.995874989687474218685546713866
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (164.997525 * -7500) / -7649.995874989687474218685546713866
      //                    = 161.762366636788307886033771279108

      assertMarketLongPosition({ _marketIndex: appleMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T6: " });
      assertMarketShortPosition({
        _marketIndex: appleMarketIndex,
        _positionSize: 7500 * 1e30,
        _avgPrice: 161.762366636788307886033771279108 * 1e30,
        _str: "T6: "
      });
    }

    // ### Scenario: Alice partail close & Bob fully close APPLE positions
    // When Alice partially close APPLE 600 USD (loss)
    marketBuy(ALICE, 0, appleMarketIndex, 600 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice should has correct short position

      // oracle price       = 165
      // market skew        = -7500
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * -7500) + 600) / (2 * 300000000) = -0.000024
      // adaptive price     = oracle price * (1 + premium)
      //                    = 165 * (1 + -0.000024) = 164.99604

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * -7500) - (-1500)) / (2 * 300000000) = -0.0000225
      // close price        = oracle price * (1 + close premium)
      //                    = 165 * (1 + -0.0000225) = 164.9962875

      // next close price
      // new market skew    = -size delta = -7500 - (-600) = -6900
      // new position size  = -size delta = -1500 - (-600) = -900
      // new close premium  = ((2 * new market skew) - new position size) / (2 * max scale)
      //                    = ((2 * -6900) - (-900)) / (2 * 300000000) = -0.0000215
      // next close price   = oracle price * (1 + new close premium)
      //                    = 165 * (1 + -0.0000215) = 164.9964525

      // new SHORT average price
      // entry price        = 149.999625
      // pnl                = -1500 * (149.999625 - 164.9962875) / 149.999625
      //                    = 149.966999917499793749484373710934
      // realized pnl       = size delta / position size * pnl
      //                    = -600 / -1500 * 149.966999917499793749484373710934
      //                    = 59.986799966999917499793749484373
      // unrealized pnl     = 149.966999917499793749484373710934 - 59.986799966999917499793749484373
      //                    = 89.980199950499876249690624226561
      // divisor            = new position size - unrealized pnl
      //                    = -900 - 89.980199950499876249690624226561
      //                    = -989.980199950499876249690624226561
      // new average price  = (next close price * new position size) / divisor, adaptive price if position size == 0
      //                    = (164.9964525 * -900) / -989.980199950499876249690624226561
      //                    = 149.999775003000067501518784172643

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(900 * 1e30),
        _avgPrice: 149.999775003000067501518784172643 * 1e30,
        _reserveValue: 405 * 1e30,
        _realizedPnl: -59986799966999917499793749484373,
        _entryBorrowingRate: 403615566318282,
        _lastFundingAccrued: 120000000000,
        _str: "T7: "
      });

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 161.762366636788307886033771279108
      // pnl                = -7500 * (161.762366636788307886033771279108 - 164.9962875) / 161.762366636788307886033771279108
      //                    = 149.938499159987606064606595388033
      // actual pnl         = pnl - position realized pnl
      //                    = 149.938499159987606064606595388033 - 59.986799966999917499793749484373
      //                    = 89.95169919298768856481284590366
      // divisor            = new market's position size - pnl
      //                    = -6900 - 89.95169919298768856481284590366
      //                    = -6989.95169919298768856481284590366
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (164.9964525 * -6900) / -6989.95169919298768856481284590366
      //                    = 162.873160108022011855894248947783

      assertMarketLongPosition({ _marketIndex: appleMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T7: " });
      assertMarketShortPosition({
        _marketIndex: appleMarketIndex,
        _positionSize: 6900 * 1e30,
        _avgPrice: 162.873160108022011855894248947783 * 1e30,
        _str: "T7: "
      });
    }

    // When APPLE price is dump to 150 USD
    skip(60);
    // updatePriceData[1] = _createPriceFeedUpdateData(appleAssetId, 150 * 1e5, 0);
    tickPrices[5] = 50108; // APPL tick price $150
    // When Bob fully close (profit)
    marketBuy(BOB, 0, appleMarketIndex, 6_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then BOB should has correct long position

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T8: "
      });

      // oracle price       = 150
      // market skew        = -6900
      // max scale          = 300000000
      // premium            = ((2 * market skew) + size delta) / (2 * max scale)
      //                    = ((2 * -6900) + 6000) / (2 * 300000000) = -0.000013
      // adaptive price     = oracle price * (1 + premium)
      //                    = 150 * (1 + -0.000013) = 149.99805

      // close price
      // position size      = 0
      // close premium      = ((2 * market skew) - position size) / (2 * max scale)
      //                    = ((2 * -6900) - -6000) / (2 * 300000000) = -0.000013
      // close price        = oracle price * (1 + close premium)
      //                    = 150 * (1 + -0.000013) = 149.99805

      // next close price
      // new market skew    = -size delta = -6900 - (-6000) = -900
      // new position size  = -size delta = -6000 - (-6000) = 0
      // new close premium  = ((2 * new market skew) - new position size) / (2 * max scale)
      //                    = ((2 * -900) - (-0)) / (2 * 300000000) = -0.000003
      // next close price   = oracle price * (1 + new close premium)
      //                    = 150 * (1 + -0.000003) = 149.99955

      // new SHORT average price
      // entry price        = 164.997525
      // pnl                = -6000 * (164.997525 - 149.99805) / 164.997525
      //                    = -545.443636199997545417726720446261
      // realized pnl       = size delta / position size * pnl
      //                    = -6000 / -6000 * -545.443636199997545417726720446261
      //                    = -545.443636199997545417726720446261
      // unrealized pnl     = 0

      // And market's state should be corrected

      // new market's LONG average price
      // average price      = 162.873160108022011855894248947783
      // pnl                = -6900 * (162.873160108022011855894248947783 - 149.99805) / 162.873160108022011855894248947783
      //                    = -545.444440854661848207135086734652
      // actual pnl         = pnl - position realized pnl
      //                    = -545.444440854661848207135086734652 - (-545.443636199997545417726720446261)
      //                    = -0.000804654664302789408366288391
      // divisor            = new market's position size - pnl
      //                    = -900 - (-0.000804654664302789408366288391)
      //                    = -899.999195345335697210591633711609
      // new average price  = (next close price * new market's position size) / divisor, adaptive price if position size == 0
      //                    = (149.99955 * -900) / -899.999195345335697210591633711609
      //                    = 149.999684108828291237426361986358

      assertMarketLongPosition({ _marketIndex: appleMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T8: " });
      assertMarketShortPosition({
        _marketIndex: appleMarketIndex,
        _positionSize: 900 * 1e30,
        _avgPrice: 149.999684108828291237426361986358 * 1e30,
        _str: "T8: "
      });
    }
  }
}
