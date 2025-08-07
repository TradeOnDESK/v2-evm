// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

import { console2 } from "forge-std/console2.sol";

contract TC25 is BaseIntTest_WithActions {
  function test_correctness_HLP_effectPriceChange() external {
    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB is open position

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    vm.deal(ALICE, executionOrderFee);
    usdc.mint(ALICE, 100_000 * 1e6);

    addLiquidity(
      ALICE,
      ERC20(address(usdc)),
      100_000 * 1e6,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    {
      // HLP => 1_994_000.00(WBTC) + 100_000 (USDC)
      assertHLPTotalSupply(2_094_000 * 1e18);
      // assert HLP
      assertTokenBalanceOf(ALICE, address(hlpV2), 2_094_000 * 1e18);
      assertHLPLiquidity(address(wbtc), 99.7 * 1e8);
      assertHLPLiquidity(address(usdc), 100_000 * 1e6);
    }

    //  Deposit Collateral => 1000 dollar
    // fee increase position

    usdc.mint(BOB, 300_230 * 1e6);

    depositCollateral(BOB, 0, ERC20(address(usdc)), 300_230 * 1e6);

    {
      // Assert collateral (HLP 100,000 + Collateral 1,000) => 101_000
      assertVaultTokenBalance(address(usdc), 400_230 * 1e6, "TC25: ");
    }

    //  Open position
    // - Long  BTCUSD 100,000 USD (Tp in wbtc) //  (100_000 + 0.1%) => 100_100
    // - Long JPYUSD 100,000 USD (tp in usdc) // (100_000 + 0.03%)  => 100_030
    // - Short ETHUSD 100,000 USD (tp in usdc) //  (100_000 + 0.1%) => 100_100
    uint256 _pythGasFee = initialPriceFeedDatas.length;
    vm.deal(BOB, _pythGasFee * 3);

    // Long BTC
    // Short ETH
    // LONG JPY
    vm.deal(BOB, 1 ether);
    marketBuy(BOB, 0, wbtcMarketIndex, 100_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    marketBuy(BOB, 0, jpyMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);
    marketSell(BOB, 0, wethMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);

    // HLP LIQUIDITY 99.7 WBTC, 100_000 usdc
    {
      /* 
      BEFORE T2

      HLP VALUE = 2094000000000000000000000000000000000
      assetIds	value
      usdc	  100000000000000000000000000000000000
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  1994000000000000000000000000000000000 (20_000 * 99.7)

      PNL =  -5731632
      
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         20000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              -16663889351774704215964005932355
      JPY    LONG         7346297098947275625720855402                     7347521481797100171658475544                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1500000000000000000000000000000000               1499750000000000000000000000001000               100000000000000000000000000000000000              -16669444907484580763460576696104

      Pending Borrowing Fee = 0 (no skip)
      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM = 2094000000000000000000000000000000000- (-5731632) + 0 
      AUM = 2094000000000000000000000000005731632
      PNL = hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit
      */

      uint256 hlpValueBefore = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeBefore = calculator.getPendingBorrowingFeeE30();
      uint256 aumBefore = calculator.getAUME30(false);

      assertApproxEqRel(hlpValueBefore, 2093835074056630000000000000000000000, MAX_DIFF, "HLP TVL Before Feed Price");
      assertApproxEqRel(pendingBorrowingFeeBefore, 0, MAX_DIFF, "Pending Borrowing Fee Before Feed Price");
      assertApproxEqRel(aumBefore, 2093835074056629999999999999994268368, MAX_DIFF, "AUM Before Feed Price");
      console2.log("aumBefore", aumBefore);
      console2.log("hlpValueBefore", hlpValueBefore);
      console2.log("pendingBorrowingFeeBefore", pendingBorrowingFeeBefore);
      assertApproxEqRel(
        int256(aumBefore) - int256(hlpValueBefore) - int256(pendingBorrowingFeeBefore),
        -5731632,
        MAX_DIFF,
        "GLOBAL PNLE30"
      );
    }

    // T2: Price changed (at same block, no borrowing fee in this case)
    // - BTC 20,000 => 21,000
    // - ETH 1,500 => 1,800
    {
      tickPrices[0] = 74959; // ETH tick price $1,800
      tickPrices[1] = 99527; // WBTC tick price $21,000
      setPrices(tickPrices, publishTimeDiff);
    }

    //  ASSERT AFTER T2
    {
      /*
      AFTER T2
      HLP VALUE = 2193542311526886000000000000000000000
      assetIds	value
      usdc	  100000000000000000000000000000000000
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2093700000000000000000000000000000000 (21_000 * 99.7)

      PNL = 15007542563839215898193133666694455a
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100171658475544                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1800000000000000000000000000000000               1499750000000000000000000000001000               100000000000000000000000000000000000              -20020003333888981496916152692035325

      Pending Borrowing Fee = 0 (no skip)
      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM = 2193542311526886000000000000000000000 + (15007542563839215898193133666694455) + 0
      AUM = 2208549854090725215898193133666694455
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit
      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      assertApproxEqRel(aumAfter, 2208549854090725215898193133666694455, MAX_DIFF, "AUM After T2");
      assertApproxEqRel(hlpValueAfter, 2193700000000000000000000000000000000, MAX_DIFF, "HLP TVL After T2");
      assertApproxEqRel(pendingBorrowingFeeAfter, 0, MAX_DIFF, "Pending Borrowing Fee After T2");
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(pnlAfter, -15007542563839215898193133666694455, MAX_DIFF, "GLOBAL PNLE30 After T2");
    }

    // T3: FEED PRICE
    // - ETH 1,800->1,000
    {
      skip(1);
      tickPrices[0] = 69081; // ETH tick price $1,000
      setPrices(tickPrices, publishTimeDiff);
    }

    // ASSERT AFTER T3
    {
      /*
      AFTER T3

      HLP VALUE = 2155213908519401344106767225398703651
      assetIds	value
      usdc	  100000000000000000000000000000000000
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2093700000000000000000000000000000000 (21_000 * 99.7)

      PNL = -38328417888893520649432774601296349
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              33322220370061676946157692948869263

      Pending Borrowing Fee =  14880339153010800000000000000

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 1 ) / 2155213908519401344106767225398703651 = 123079728312
          Borrowing Fee = 123079728312 * 900000000000000000000000000000000 / 1e18 => 110771755480800000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 1 ) / 2155213908519401344106767225398703651 = 820531522085
          Borrowing Fee =  820531522085 * 18000000000000000000000000000000000 / 1e18 =>  14769567397530000000000000000
      Pending Equity => 0 (no position)

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  2155213908519401344106767225398703651 - (-38328417888893520649432774601296349) + 14880339153010800000000000000
      AUM =  2193542341288634017767000000000000000
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 2155213908519401344106767225398703651, MAX_DIFF, "AUM After Feed Price T3");
      assertApproxEqRel(hlpValueAfter, 2193700000000000000000000000000000000, MAX_DIFF, "HLP TVL After Feed Price T3");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        14880339153010800000000000000,
        MAX_DIFF,
        "Pending Borrowing Fee After Feed Price T3"
      );
      assertApproxEqRel(pnlAfter, 38328417888893520649432774601296349, MAX_DIFF, "GLOBAL PNLE30 After Feed Price T3");
    }

    // T4: Add BTC in hlp
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 5 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      5 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // ASSERT AFTER T4 (Add Liquidity)
    {
      /* AFTER T4
      Fee = 0.31%, Old Supply 2_094_000.00, PNL = 38288059396890538983595352201440684, Borrowing fee => 14880339153010800000000000000
      HLP => 1_994_000.00(WBTC)+ 100_000 (USDC)  + 101_692.116183347924019124 (WBTC)
      HLP => 2195692116183347924019124 */
      assertHLPTotalSupply(2195692116183347924019124);

      /*  assert HLP
      BTC in liquidity
      99.7 + 4.984500 */
      assertTokenBalanceOf(ALICE, address(hlpV2), 2195692116183347924019124);
      assertHLPLiquidity(address(wbtc), 104.6845 * 1e8);
      assertHLPLiquidity(address(usdc), 100_000 * 1e6);

      /*
      HLP VALUE = 2298208927894045110000000000000000000
      assetIds	value
      usdc	  100000000000000000000000000000000000
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2198374500000000000000000000000000000 (21_000 * 104.6845)

      PNL = -38328417888893520649432774601296349
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              33322220370061676946157692948869263

      Pending Borrowing Fee =  14203669476608100000000000000 (hlpTVL is changed)

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 1 ) / 2298208927894045110000000000000000000 = 117474328052
          Borrowing Fee = 117474328052 * 900000000000000000000000000000000 / 1e18 => 105726895246800000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 1 ) / 2298208927894045110000000000000000000 = 783162187015
          Borrowing Fee =  783162187015 * 18000000000000000000000000000000000 / 1e18 =>  14096919366270000000000000000
      Pending Equity => 0 (no position)

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  2298208927894045110000000000000000000 - 38328417888893520649432774601296349 + 14203669476608100000000000000
      AUM =  2259880524208821065958667225398703651
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 2259880524208821065958667225398703651, MAX_DIFF, "AUM After T4");
      assertApproxEqRel(hlpValueAfter, 2298374500000000000000000000000000000, MAX_DIFF, "HLP TVL After T4");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        14202646261516800000000000000,
        MAX_DIFF,
        "Pending Borrowing Fee After T4"
      );
      assertApproxEqRel(pnlAfter, 38328417888893520649432774601296349, MAX_DIFF, "GLOBAL PNLE30  After T4");
    }

    // T5: BTC price changed to 18,000 (check AUM)
    {
      skip(1);
      tickPrices[1] = 97986; // WBTC tick price $18,000
      setPrices(tickPrices, publishTimeDiff);
    }

    // ASSERT AFTER T5
    {
      /*
      AFTER T5

      HLP VALUE = 1984289090765815080000000000000000000
      assetIds	value
      usdc	  100000000000000000000000000000000000
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  1884321000000000000000000000000000000 (18_000 * 104.6845)

      PNL = -23333561729071225690813111239655475
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         18000000000000000000000000000000000              20003333333333333320000000000000000              100000000000000000000000000000000000              -10014997500416597233794367605339120
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              +33322220370061676946157692948869263

      Pending Borrowing Fee = 32901455893598100000000000000

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 2 ) / 1984289090765815080000000000000000000 = 272133389708
          Borrowing Fee = 272133389708 * 900000000000000000000000000000000 / 1e18 => 244920050737200000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 2 ) / 1984289090765815080000000000000000000 = 1814222598057
          Borrowing Fee =  1814222598057 * 18000000000000000000000000000000000 / 1e18 =>  32656006765026000000000000000
      Pending Equity => 0 (no position)

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  1984289090765815080000000000000000000 - 23333561729071225690813111239655475 + 32901455893598100000000000000
      AUM =  1960955561938199747907286888760344525
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */
      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 1960955561938199747907286888760344525, MAX_DIFF, "AUM After T5");
      assertApproxEqRel(hlpValueAfter, 1984321000000000000000000000000000000, MAX_DIFF, "HLP TVL After T5");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        32900926815763200000000000000,
        MAX_DIFF,
        "Pending Borrowing Fee After T5"
      );
      assertApproxEqRel(pnlAfter, 23333561729071225690813111239655475, MAX_DIFF, "GLOBAL PNLE30 After T5");
    }
  }
}
