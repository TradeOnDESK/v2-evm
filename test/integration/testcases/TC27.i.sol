// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

contract TC27 is BaseIntTest_WithActions {
  function test_correctness_HLP_disableDynamicFee() external {
    // T0: Initialized state
    configStorage.setDynamicEnabled(false);
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
      // HLP => 1_994_000.00(WBTC) + 99_700 (USDC)
      assertHLPTotalSupply(2_093_700 * 1e18);
      // assert HLP
      assertTokenBalanceOf(ALICE, address(hlpV2), 2_093_700 * 1e18);

      assertHLPLiquidity(address(wbtc), 99.7 * 1e8);
      assertHLPLiquidity(address(usdc), 99_700 * 1e6);
    }

    // fee increase position

    usdc.mint(BOB, 300_230 * 1e6);

    depositCollateral(BOB, 0, ERC20(address(usdc)), 300_230 * 1e6);

    {
      // Assert collateral (HLP 100,000 + Collateral 1,000) => 101_000
      assertVaultTokenBalance(address(usdc), 400_230 * 1e6, "TC27: ");
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

    // HLP LIQUIDITY 99.7 WBTC, 99_700 usdc
    {
      /* 
      BEFORE T2

      HLP VALUE = 2093700000000000000000000000000000000
      assetIds	value
      usdc	  99700000000000000000000000000000000 (1 * 99700)
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  1994000000000000000000000000000000000 (20000 * 99.7)

      PNL =  -5731632
      
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         20000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              -16663889351774704215964005932355
      JPY    LONG         7346297098947275625720855402                     7347521481797100171658475544                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1500000000000000000000000000000000               1499750000000000000000000000001000               100000000000000000000000000000000000              -16669444907484580763460576696104

      Pending Borrowing Fee = 0 (no skip)
      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM = 2093700000000000000000000000000000000- (-5731632) +0 =
      AUM = 2093749997223611033989195388580911857
      PNL = hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit
      */

      uint256 hlpValueBefore = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeBefore = calculator.getPendingBorrowingFeeE30();
      uint256 aumBefore = calculator.getAUME30(false);
      assertApproxEqRel(hlpValueBefore, 2093700000000000000000000000000000000, MAX_DIFF, "HLP TVL Before Feed Price");
      assertApproxEqRel(pendingBorrowingFeeBefore, 0, MAX_DIFF, "Pending Borrowing Fee Before Feed Price");
      assertApproxEqRel(aumBefore, 2093749997223611033989195388580911857, MAX_DIFF, "AUM Before Feed Price");
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
      // bytes32[] memory _newAssetIds = new bytes32[](2);
      // int64[] memory _prices = new int64[](2);
      // uint64[] memory _conf = new uint64[](2);
      // _newAssetIds[0] = wbtcAssetId;
      // _prices[0] = 21_000 * 1e8;
      // _conf[0] = 0;

      // _newAssetIds[1] = wethAssetId;
      // _prices[1] = 1_800 * 1e8;
      // _conf[1] = 0;

      tickPrices[0] = 74959; // ETH tick price $1,800
      tickPrices[1] = 99527; // WBTC tick price $21,000

      setPrices(tickPrices, publishTimeDiff);
    }

    //  ASSERT AFTER T2
    {
      /*
      AFTER T2
      HLP VALUE = 2193242311526886000000000000000000000
      assetIds	value
      usdc	  99700000000000000000000000000000000 (1 * 99700)
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2093700000000000000000000000000000000 (21000 * 99.7)

      PNL = 15007542563839215898193133666694455
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100171658475544                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1800000000000000000000000000000000               1499750000000000000000000000001000               100000000000000000000000000000000000              -20020003333888981496916152692035325

      Pending Borrowing Fee = 0 (no skip)
      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM = 2193242311526886000000000000000000000 + (15007542563839215898193133666694455) + 0
      AUM = 2208249854090725215898193133666694455
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit
      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      assertApproxEqRel(aumAfter, 2208249854090725215898193133666694455, MAX_DIFF, "AUM After T2");
      assertApproxEqRel(hlpValueAfter, 2193242311526886000000000000000000000, MAX_DIFF, "HLP TVL After T2");
      assertApproxEqRel(pendingBorrowingFeeAfter, 0, MAX_DIFF, "Pending Borrowing Fee After T2");
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(pnlAfter, -15007542563839215898193133666694455, MAX_DIFF, "GLOBAL PNLE30 After T2");
    }

    // T3: FEED PRICE
    // - ETH 1,800->1,000
    {
      skip(1);
      // bytes32[] memory _newAssetIds = new bytes32[](1);
      // int64[] memory _prices = new int64[](1);
      // uint64[] memory _conf = new uint64[](1);

      // _newAssetIds[0] = wethAssetId;
      // _prices[0] = 1_000 * 1e8;
      // _conf[0] = 0;
      tickPrices[0] = 69081; // ETH tick price $1,000

      setPrices(tickPrices, publishTimeDiff);
    }

    // ASSERT AFTER T3
    {
      /*
      AFTER T3

      HLP VALUE = 2193242311526886000000000000000000000
      assetIds	value
      usdc	  99700000000000000000000000000000000 (1 * 99700)
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2093700000000000000000000000000000000 (21000 * 99.7)

      PNL = -38328417888893520649432774601296349
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              33322220370061676946157692948869263

      Pending Borrowing Fee =  14883444400284000000000000000

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 1 ) / 2193242311526886000000000000000000000 = 123096562414
          Borrowing Fee = 123096562414 * 900000000000000000000000000000000 / 1e18 => 110786906172600000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 1 ) / 2193242311526886000000000000000000000 = 820643749430
          Borrowing Fee =  820643749430 * 18000000000000000000000000000000000 / 1e18 =>  14771587489740000000000000000
      Pending Equity => 0 (no position)

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  2193242311526886000000000000000000000 - 38328417888893520649432774601296349 + 14883444400284000000000000000
      AUM =  2154913908521436879634567225398703651
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 2154913908521436879634567225398703651, MAX_DIFF, "AUM After Feed Price T3");
      assertApproxEqRel(hlpValueAfter, 2193400000000000000000000000000000000, MAX_DIFF, "HLP TVL After Feed Price T3");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        14883444400284000000000000000,
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

    // ASSERT AFTER T4

    {
      // AFTER T4

      // Old Supply 2_093_700.00, PNL = 28326864724579583997165365551805191, Borrowing fee => 14882374395912600000000000000 , totalLiquidityValue = 2193400000000000000000000000000000000
      // Fee Add liquidity = 0.3%
      // HLP => 1_994_000.00(WBTC) + 99_700.000 (USDC) + 101_701.901816337596452511 (WBTC)
      // HLP => 2195401.901816337596452511
      assertHLPTotalSupply(2_195_401.901816337596452511 * 1e18);

      // assert HLP
      // BTC in liquidity
      assertTokenBalanceOf(ALICE, address(hlpV2), 2_195_401.901816337596452511 * 1e18);
      // 99.7 + 4.985  = 104.685
      assertHLPLiquidity(address(wbtc), 104.685 * 1e8);
      assertHLPLiquidity(address(usdc), 99_700 * 1e6);

      /*

      HLP VALUE (HLP TVL) = 2297919427103230300000000000000000000
      assetIds	value
      usdc	  99700000000000000000000000000000000 (1* 99700)
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  2198385000000000000000000000000000000 (21_000 * 104.685)

      PNL = 38328417888893520649432774601296349
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         21000000000000000000000000000000000              20003333333333333333333333333320000              100000000000000000000000000000000000              4982502916180636560573237793771026
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              33322220370061676946157692948869263

      Pending Borrowing Fee =  14205458909903400000000000000 (hlpTVL is changed)

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 1 ) / 2297919427103230300000000000000000000 = 117489126816
          Borrowing Fee = 117489126816 * 900000000000000000000000000000000 / 1e18 => 105740214134400000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 1 ) / 2297919427103230300000000000000000000 = 783260845443
          Borrowing Fee =  783260845443 * 18000000000000000000000000000000000 / 1e18 =>  14098695217974000000000000000

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  2297919427103230300000000000000000000 - 38328417888893520649432774601296349 + 14205458909903400000000000000
      AUM =  2259591023419795689253967225398703651
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */

      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 2259591023419795689253967225398703651, MAX_DIFF, "AUM After T4");
      assertApproxEqRel(hlpValueAfter, 2298085000000000000000000000000000000, MAX_DIFF, "HLP TVL After T4");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        14205458909903400000000000000,
        MAX_DIFF,
        "Pending Borrowing Fee After T4"
      );
      assertApproxEqRel(pnlAfter, 38328417888893520649432774601296349, MAX_DIFF, "GLOBAL PNLE30  After T4");
    }

    // T5: BTC price changed to 18,000 (check AUM)
    {
      skip(1);
      // bytes32[] memory _newAssetIds = new bytes32[](1);
      // int64[] memory _prices = new int64[](1);
      // uint64[] memory _conf = new uint64[](1);

      // _newAssetIds[0] = wbtcAssetId;
      // _prices[0] = 18_000 * 1e8;
      // _conf[0] = 0;
      tickPrices[1] = 97986; // WBTC tick price $18,000

      setPrices(tickPrices, publishTimeDiff);
    }

    {
      /*
      AFTER T5

      HLP VALUE (HLP TVL) = 1983998090613408400000000000000000000
      assetIds	value
      usdc	  99700000000000000000000000000000000 (1* 99700)
      usdt	  0
      dai	    0
      weth	  0
      wbtc	  1884330000000000000000000000000000000 (18_000 * 104.685)

      PNL = -23333561729071225690813111239655475
      Market Exposure     Price                                            AdaptivePrice                                    SIZE                                              PNL
      WBTC   LONG         18000000000000000000000000000000000              20003333333333333320000000000000000              100000000000000000000000000000000000              -10014997500416597233794367605339120
      JPY    LONG         7346297098947275625720855402                     7347521481797100166760944145                     100000000000000000000000000000000000              -16663889351774704215963998283398
      WETH   SHORT        1000000000000000000000000000000000               1499750000000000001000000000000000               100000000000000000000000000000000000              +33322220370061676946157692948869263

      Pending Borrowing Fee = 32906281668746400000000000000

         NEXT BORROWING Rate => (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL
          BorrowingFee => (NEXT BORROWING RATE * _assetClassState.reserveValueE30) / RATE_PRECISION;

      Pending Forex (JPY position) =>
          NEXT BORROWING Rate  =  (300000000000000 * 900000000000000000000000000000000 * 2 ) / 1983998090613408400000000000000000000 = 272173303831
          Borrowing Fee = 272173303831 * 900000000000000000000000000000000 / 1e18 => 244955973447900000000000000

      Pending Crypto (WETH, WBTC position) =>
          NEXT BORROWING Rate  =  (100000000000000 * 18000000000000000000000000000000000 * 2 ) / 1983998090613408400000000000000000000 = 1814488692207
          Borrowing Fee =  1814488692207 * 18000000000000000000000000000000000 / 1e18 =>  32660796459726000000000000000

      AUM = HLP VALUE - PNL + PENDING_BORROWING_FEE
      AUM =  1983998090613408400000000000000000000 - 23333561729071225690813111239655475 + 32906281668746400000000000000
      AUM =  1960664561790618843055586888760344525
      PNL =  hlpValue - aum + pendingBorrowingFee) negative of PNL means hlp is profit

      */
      uint256 hlpValueAfter = calculator.getHLPValueE30(false);
      uint256 pendingBorrowingFeeAfter = calculator.getPendingBorrowingFeeE30();
      uint256 aumAfter = calculator.getAUME30(false);
      int256 pnlAfter = int256(hlpValueAfter) - int256(aumAfter) + int256(pendingBorrowingFeeAfter);
      assertApproxEqRel(aumAfter, 1960664561790618843055586888760344525, MAX_DIFF, "AUM After T5");
      assertApproxEqRel(hlpValueAfter, 1983998090613408400000000000000000000, MAX_DIFF, "HLP TVL After T5");
      assertApproxEqRel(
        pendingBorrowingFeeAfter,
        32906281668746400000000000000,
        MAX_DIFF,
        "Pending Borrowing Fee After T5"
      );
      assertApproxEqRel(pnlAfter, 23333561729071225690813111239655475, MAX_DIFF, "GLOBAL PNLE30 After T5");
    }
  }
}
