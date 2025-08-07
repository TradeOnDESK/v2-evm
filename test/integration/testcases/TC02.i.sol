// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

contract TC02 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // TC02 - trader could take profit both long and short position
  function testCorrectness_TC02_TradeWithTakeProfitScenario() external {
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

    // T1: BOB provide liquidity as WBTC 1 token
    // note: price has no changed0
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);
    {
      // When Bob provide 1 BTC as liquidity
      assertTokenBalanceOf(BOB, address(wbtc), 99 * 1e8, "T1: ");

      // Then Bob should pay fee for 0.3% = 0.003 BTC

      // Assert HLP Liquidity
      //    BTC = 0.997 (amount - fee)
      assertHLPLiquidity(address(wbtc), 0.997 * 1e8, "T1: ");

      // When HLP Token price is 1$
      // Then HLP Token should Mint = 0.997 btc * 20,000 USD = 19,940 USD
      //                            = 19940 / 1 = 19940 Tokens
      assertHLPTotalSupply(19_940 * 1e18, "T1: ");

      // Assert Fee distribution
      // According from T0
      // Vault's fees has nothing

      // Then after Bob provide liquidity, then Bob pay fees
      //    Add Liquidity fee
      //      BTC - 0.003 btc
      //          - distribute all  protocol fee

      // In Summarize Vault's fees
      //    BTC - protocol fee  = 0 + 0.003 = 0.00309563 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: (0.003 * 1e8 * 9000) / 1e4,
        _devFee: 0.003 * 1e7,
        _fundingFeeReserve: 0,
        _str: "T1: "
      });

      // Finally after Bob add liquidity Vault balance should be correct
      // note: token balance is including all liquidity, dev fee and protocol fee
      //    BTC - 1
      assertVaultTokenBalance(address(wbtc), 1 * 1e8, "T1: ");
    }

    // time passed for 60 seconds
    skip(60);

    // T2: alice deposit BTC 200 USD at price 20,000
    // 200 / 20000 = 0.01 BTC
    address _aliceSubAccount0 = getSubAccount(ALICE, 0);
    depositCollateral(ALICE, 0, wbtc, 0.01 * 1e8);
    {
      // When Alice deposit Collateral for 0.01 btc
      assertTokenBalanceOf(ALICE, address(wbtc), 99.99 * 1e8, "T2: ");

      // Then Vault btc's balance should be increased by 0.01
      assertVaultTokenBalance(address(wbtc), 1.01 * 1e8, "T2: ");

      // And Alice's sub-account balances should be correct
      //    BTC - 0.01
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.01 * 1e8, "T2: ");

      // And HLP total supply and Liquidity must not be changed
      // note: data from T1
      assertHLPTotalSupply(19_940 * 1e18, "T2: ");
      assertHLPLiquidity(address(wbtc), 0.997 * 1e8, "T2: ");

      // And Alice should not pay any fee
      // note: vault's fees should be same with T1
      assertVaultsFees({
        _token: address(wbtc),
        _fee: (0.003 * 1e8 * 9000) / 1e4,
        _devFee: 0.003 * 1e7,
        _fundingFeeReserve: 0,
        _str: "T2: "
      });
    }

    // time passed for 60 seconds
    skip(60);

    // T3: ALICE market buy weth with 200,000 USD (1000x) at price 20,000 USD
    // should revert InsufficientFreeCollateral
    // note: price has no changed
    marketBuy(
      ALICE,
      0,
      wethMarketIndex,
      100_000 * 1e30,
      address(0),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_InsufficientFreeCollateral()"
    );

    // T4: ALICE market buy weth with 300 USD at price 20,000 USD
    //     Then Alice should has Long Position in WETH market
    // initialPriceFeedDatas is from
    marketBuy(ALICE, 0, wethMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    assertEq(perpStorage.getEpochVolume(true, wethMarketIndex), 300 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wethMarketIndex), 0);
    {
      // When Alice Buy WETH Market
      // And Alice has no position
      // Then it means Alice open new Long position
      // Given increase size = 300 USD
      // WETH Price = 1500 USD

      // Then Check position Info
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 0
      // new Market skew      = 0 + 300
      // Premium before       = 0 / 300000000 = 0
      // Premium after        = 300 / 300000000 = 0.000001
      // Premium median       = (0 + 0.000001) / 2 = 0.0000005
      // Adaptive price       = 1500 * (1 + 0.0000005)
      //                      = 1500.00075

      // WETH market IMF      = 0.1%
      // WETH market MMF      = 0.05%
      // Inc / Dec Fee        = 0.1%
      // Position size        = 300 USD
      // Avg price            = 1500.00075 USD
      // IMR                  = 300 * IMF = 3 USD
      // MMR                  = 300 * MMF = 1.5 USD
      // Reserve              = IMR * Max profit
      //                      = 3 * 900%
      //                      = 27
      // Trading fee          = 300 * 0.1% = 0.3 USD

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(300 * 1e30),
        _avgPrice: 1_500.00075 * 1e30, // 1,500.00075
        _reserveValue: 27 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T4: "
      });

      // Sub-account's state
      // According from T2
      //    IMR           = 0 USD
      //    MMR           = 0 USD
      // In Summarize
      //    IMR = 0 + 3   =   3 USD
      //    MMR = 0 + 1.5 = 1.5 USD

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 3 * 1e30, _mmr: 1.5 * 1e30, _str: "T4: " });

      // Assert Alice Sub-account's Collateral
      // According to T2, Alice's collateral balances
      //    BTC - 0.01
      // When Alice buy WETH with 300 USD
      // Then Alice has fees to pay below
      //    Trading fee - 0.3 USD

      // Then Alice pay fee by Collateral
      //    BTC, (price: 20,000 USD)
      //      Trading fee = 0.3 / 20000 = 0.000015 btc
      // In Summarize, Alice's collateral balances
      //    BTC - 0.01 - 0.000015 = 0.009985

      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.009985 * 1e8, "T4: ");

      // Assert Fee distribution
      // According from T2
      // Vault's fees
      //    BTC - protocol fee  = 0.003 btc
      //        - dev fee       = 0 btc
      // and HLP's liquidity
      //    BTC - 0.997 btc

      // Alice paid fees list
      //    BTC
      //      Trading fee - 0.000015 btc
      //                  - pay for protocol (85%)  = 0.00001275 btc
      //                  - pay for dev (15%)       = 0.00000225 btc
      //    Borrowing fee = 0 USD
      //    Funding fee   = 0 USD

      // In Summarize Vault's fees
      //    BTC - protocol fee  = 0.003 + 0.00001275 = 0.00301275 btc
      //        - dev fee       = 0 + 0.00000225     = 0.00000225 btc
      // and HLP's liquidity still be
      //    BTC - 0.997 btc
      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.00271215 * 1e8,
        _devFee: 0.0003015 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T4: "
      });

      assertHLPLiquidity(address(wbtc), 0.997 * 1e8, "T4: ");

      // Assert Market
      assertMarketLongPosition(wethMarketIndex, 300 * 1e30, 1_500.00075 * 1e30, "T4: ");
      assertMarketShortPosition(wethMarketIndex, 0, 0, "T4: ");
      assertMarketFundingRate(wethMarketIndex, 0, 1120, "T4: ");

      // Assert Asset class
      // Crypto's reserve should be increased by = 27 USD
      assertAssetClassReserve(0, 27 * 1e30, "T4: ");
      // borrowing rate still not calculated
      assertAssetClassSumBorrowingRate(0, 0, 1120, "T4: ");

      // Invariant testing
      assertAssetClassReserve(1, 0, "T4: ");
      assertAssetClassSumBorrowingRate(1, 0, 0, "T4: ");
      assertAssetClassReserve(2, 0, "T4: ");
      assertAssetClassSumBorrowingRate(2, 0, 0, "T4: ");
    }

    // Time passed for 60 seconds
    skip(60);

    // T5: Alice withdraw BTC 200 USD (200 / 20000 = 0.01 BTC)
    // should revert ICrossMarginService_InsufficientBalance
    withdrawCollateral(ALICE, 0, wbtc, 0.1 * 1e8, tickPrices, publishTimeDiff, block.timestamp, executionOrderFee);

    // T6: Alice partial close Long position at WETH market for 150 USD
    //     WETH price 1,575 USD, then Alice should take profit ~5%
    // updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wethAssetId, 1_575 * 1e8, 0);
    tickPrices[0] = 73623;
    marketSell(ALICE, 0, wethMarketIndex, 150 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    assertEq(perpStorage.getEpochVolume(true, wethMarketIndex), 300 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wethMarketIndex), 150 * 1e30);
    {
      // When Alice Sell WETH Market
      // And Alice has Long position
      // Then it means Alice decrease Long position
      // Given decrease size = 150 USD
      // WETH Price = 1575 USD

      // Then Check position Info

      // Time passed          = 60 seconds (60 intervals)
      // TVL                  = 19,940 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 300
      // new Market skew      = 300 + -(300) = 0
      // Premium before       = 300 / 300000000 = 0.000001
      // Premium after        = 0 / 300000000 = 0.0000000
      // Premium median       = (0.000001 + 0.0000000) / 2 = 0.0000005
      // Adaptive price       = 1575 * (1 + 0.0000005) = 1575.0007875
      //                      = 1575.0007875

      // Market's Funding rate
      // Funding rate         = currentFundingRate + (fundingRateVelocity * elapsedInterval / SECONDS_IN_DAY)
      // Funding rate         = currentFundingRate + ((skew / maxSkeScale * maxFundingRate) * elapsedInterval / SECONDS_IN_DAY)
      //                      = 0 + ((300 / 300000000 * 0.0004) * 60 / 86400)
      //                      = 0.000000000000277777
      assertMarketFundingRate(wethMarketIndex, 0.000000000000277777 * 1e18, 1180, "T6: ");

      // Crypto Borrowing rate
      //    = reserve * interval * base rate / tvl
      //    = 27 * 60 * 0.01% / 19940
      //    = 0.000008124373119358
      assertAssetClassSumBorrowingRate(0, 0.000008124373119358 * 1e18, 1180, "T6: ");

      // WETH market IMF      = 0.1%
      // WETH market MMF      = 0.05%
      // Inc / Dec Fee        = 0.1%
      // Borrowing base Rate  = 0.01%

      // Before:
      //    Position size     = 300
      //    Avg price         = 1500.00075 USD
      //    Reserve           = 27 USD
      //    Borrowing rate    = 0
      //    Finding rate      = 0

      // After:
      //    Position size     = 300 - 150 = 150
      //    Avg price         = 1500.000375 USD
      //    IMR               = 150 * IMF = 1.5 USD
      //    MMR               = 150 * MMF = 0.75 USD
      //    Reserve           = IMR * Max profit
      //                      = 1.5 * 900%
      //                      = 13.5
      //    Trading fee       = 150 * 0.1% = 0.15 USD
      //    Borrowing rate    = 0.000008124373119358
      //    Funding rate      = -0.000000024

      //    Borrowing fee     = (0.000008124373119358 - 0) * 13.5 (reserve)
      //                      = 0.000219358074222666
      //    Funding fee       = (-0.000000024 - 0) * 150 (position size)
      //                      = -0.0000036 USD

      // Profit and Loss
      // note: long position: position size * (adaptive price - avg price) / avg price
      //       short position: position size * (avg price - adaptive price) / avg price
      // to realized PnL - pnl * (size delta / position size)
      // pnl             = 300 * (1575.0007875 - 1500.00075) / 1500.00075 = 15 USD
      // to realized PnL = 15 * (150 / 300) = 7.5 USD
      // Then unrealzlied PnL = 15 - 7.5 = 7.5 USD

      // new average price = (new close price * remaining size) / (remaining size + unrealized pnl)
      // premium after decrease = 300 - 150 = 150 / 300000000 = 0.0000005
      // premium after close    = 300 - 300 = 0 / 300000000 = 0
      // premium                = (0.0000005 + 0) / 2 = 0.00000025
      // price with premium     = 1575 * (1 + 0.00000025) = 1575.00039375
      // new average price      = (1575.00039375 * 150) / (150 + 7.5)
      //                        = 1500.000375 USD

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(150 * 1e30),
        _avgPrice: 1500.000375 * 1e30,
        _reserveValue: 13.5 * 1e30,
        _realizedPnl: 7.5 * 1e30,
        _entryBorrowingRate: 0.000008124373119358 * 1e18,
        _lastFundingAccrued: -96,
        _str: "T6: "
      });

      // Sub-account's state
      // According from T4
      //    IMR           =   3 USD
      //    MMR           = 1.5 USD
      // In Summarize
      //    IMR = 3 - 1.5     =  1.5 USD
      //    MMR = 1.5 + 0.75  = 0.75 USD

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T6: " });

      // Assert Alice Sub-account's Collateral
      // According to T4, Alice's collateral balances
      //    BTC - 0.009985
      // When Alice sell WETH with 150 USD (decrease Long position)
      // And Funding rate is negative so Short pay Long
      // Then Alice should receive funding fee

      // Then Alice has to pay
      //    Trading fee   - 0.15 USD
      //    Borrowing fee - 0.000219358074222666 USD

      // And Alice has to received
      //    Funding fee   - 0.0000036 USD
      //    Profit        - 7.5 USD

      // Then Alice pay fee by Collateral
      //    BTC, (price: 20,000 USD)
      //      Trading fee     = 0.15 / 20000                  = 0.0000075 btc
      //      Borrowing fee   = 0.000219358074222666 / 20000  = 0.00000001 btc

      // And Alice receive funding fee from HLP
      // When HLP pay Alice by Liquidity
      //    BTC, (price: 20,000 USD)
      //      Funding fee     = 0.0000036 / 20000             = 0.00000000 (018) btc !too small
      //      Trader's profit = 7.5 / 20000
      //                      = 0.000375 btc

      // In Summarize, Alice's collateral balances
      //    BTC - 0.009985 - 0.0000075 - 0.00000001 + 0.00000000 + 0.000375 = 0.01035249

      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.01035249 * 1e8, "T6: ");

      // Assert Fee distribution
      // According from T4
      // Vault's fees
      //    BTC - protocol fee  = 0.00301275 btc
      //        - dev fee       = 0.00000225 btc
      // and HLP's liquidity
      //    BTC - 0.997 btc

      // Alice paid list
      //    BTC
      //      Trading fee - 0.0000075 btc
      //        - pay for dev (15%)       = 0.00000112 btc
      //        - pay for protocol (85%)  = 0.00000112 - 0.0000075
      //                                  = 0.00000638 btc
      //      Borrowing fee - 0.00000001 btc
      //        - pay for dev (15%)       = 0.00000000 (15) btc !too small
      //        - pay for HLP (85%)       = 0.00000001 - 0
      //                                  = 0.00000001 btc

      // HLP paid list
      //    BTC
      //      Funding fee   - 0.00000000 (018) btc !too small
      //      Trader profit - 0.000375 btc

      // In Summarize Vault's fees
      //    BTC - protocol fee  = 0.00301275 + 0.00000638     = 0.00301913 btc
      //        - dev fee       = 0.00000225 + 0 + 0.00000112 = 0.00000337 btc
      // and HLP's liquidity
      //    BTC - 0.997 + 0.00000001 - 0.000375 = 0.99662501 btc

      // Assert Vault
      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.00271890 * 1e8,
        _devFee: 0.00030225 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T6: "
      });

      assertHLPLiquidity(address(wbtc), 0.99662501 * 1e8, "T6: ");

      // Assert Market

      // Average Price Calculation
      //  Long:
      //    Market's Avg price = 1500.00075, close price = 1575.0007875
      //                                     new close price = 1575.00039375
      //    Market's PnL  = (300 * (1575.0007875 - 1500.00075)) / 1500.00075
      //                  = 15
      //    Actual PnL    = Market's PnL - Realized PnL = 15 - 7.5
      //                  = 7.5
      //    Avg Price     = new Close price * New Position size / New Position size + Actual PnL
      //                  = (1575.00039375 * 150) / (150 + 7.5)
      //                  = 1500.000375

      assertMarketLongPosition(wethMarketIndex, 150 * 1e30, 1500.000375 * 1e30, "T6: ");
      assertMarketShortPosition(wethMarketIndex, 0, 0, "T6: ");

      // Assert Asset class
      // According T4
      // Crypto's reserve is 27
      // When alice decreased position reserve should be reduced by = 13.5 USD
      // Then 27 - 13.5 = 13.5 USD
      // note: sum of borrowing rate is calculated on position info
      assertAssetClassReserve(0, 13.5 * 1e30, "T6: ");

      // Invariant testing
      assertAssetClassReserve(1, 0, "T6: ");
      assertAssetClassReserve(2, 0, "T6: ");
    }

    // Time passed for 60 seconds
    skip(60);

    // T7: Alice Sell JPY Market for 6000 USD with same Sub-account
    marketSell(ALICE, 0, jpyMarketIndex, 6_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    assertEq(perpStorage.getEpochVolume(true, jpyMarketIndex), 0);
    assertEq(perpStorage.getEpochVolume(false, jpyMarketIndex), 6_000 * 1e30);
    {
      // When Alice Sell JPY Market
      // And Alice has no position
      // Then it means Alice open new Long position
      // Given increase size = 6000 USD
      // JPY Price = 136.123 USDJPY (pyth price)
      //           = 0.007346297098947275625720855402 USD

      // Adaptive price
      //    Market skew       = 0
      //    new Market skew   = 0 + -6000 (short position)
      //    Premium before    = 0 / 300000000 = 0
      //    Premium after     = -6000 / 300000000 = -0.00002
      //    Premium median    = (0 + -0.00002) / 2 = -0.00001
      //    Adaptive price    = 0.007346297098947275625720855402 * (1 + -0.00001)
      //                      = 0.007346223635976286152964598193

      // JPY market IMF       = 0.01%
      // JPY market MMF       = 0.005%
      // Inc / Dec Fee        = 0.03%
      // Position size        = 6000 USD
      // Avg price            = Adaptive price
      //                      = 0.007346223635976286152964598193
      // IMR                  = 6000 * IMF = 6 USD
      // MMR                  = 6000 * MMF = 3 USD
      // Reserve              = IMR * Max profit
      //                      = 6 * 900%
      //                      = 54
      // Trading fee          = 6000 * 0.03% = 1.8 USD

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: int256(-6_000 * 1e30),
        _avgPrice: 0.007346223635976286152964598193 * 1e30,
        _reserveValue: 54 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T7: "
      });

      // Assert Alice Sub-account's Collateral
      // According to T6, Alice's collateral balances
      //    BTC - 0.01035249
      // When Alice sell JPY with 6000 USD
      // Then Alice has to pay
      //    Trading fee - 1.8 USD

      // And Alice pay fee by collateral
      //    BTC, (price: 20,000 USD)
      //      Trading fee = 1.8 / 20000 = 0.00009 btc

      // In Summarize, Alice's collateral balances
      //    BTC - 0.01035249 - 0.00009 = 0.01026249

      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.01026249 * 1e8, "T7: ");

      // Sub-account's state
      // According from T6
      //    IMR             =  1.5 USD
      //    MMR             = 0.75 USD
      // In Summarize
      //    IMR = 1.5 + 6   =  7.5 USD
      //    MMR = 0.75 + 3  = 3.75 USD

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 7.5 * 1e30, _mmr: 3.75 * 1e30, _str: "T7: " });

      // Assert Fee distribution
      // According from T6
      // Vault's fees
      //    BTC - protocol fee  = 0.00301913 btc
      //        - dev fee       = 0.00000337 btc
      // and HLP's liquidity
      //    BTC - 0.99662501 btc

      // Alice paid fees list
      //    Trading fee
      //      BTC - 0.00009 btc
      //          - pay for dev (15%)       = 0.0000135 btc
      //          - pay for protocol (85%)  = 0.00009 - 0.0000135
      //                                    = 0.0000765 btc
      //    Borrowing fee = 0 USD
      //    Funding fee   = 0 USD

      // In Summarize Vault's fees
      //    BTC - protocol fee  = 0.00301913 + 0.0000765 = 0.00309563 btc
      //        - dev fee       = 0.00000337 + 0.0000135 = 0.00001687 btc
      // and HLP's liquidity
      //    BTC - 0.99662501 btc
      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.0027999 * 1e8,
        _devFee: 0.00031125 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T7: "
      });

      assertHLPLiquidity(address(wbtc), 0.99662501 * 1e8, "T7: ");

      // Assert Market
      assertMarketLongPosition(jpyMarketIndex, 0, 0, "T7: ");
      assertMarketShortPosition(jpyMarketIndex, 6_000 * 1e30, 0.007346223635976286152964598193 * 1e30, "T7: ");
      assertMarketFundingRate(jpyMarketIndex, 0, 1240, "T7: ");

      // Assert Asset class
      // Forex's reserve should be increased by = 54 USD
      assertAssetClassReserve(2, 54 * 1e30, "T7: ");
      assertAssetClassSumBorrowingRate(2, 0, 1240, "T7: ");

      // Invariant testing
      assertAssetClassReserve(0, 13.5 * 1e30, "T7: ");
      assertAssetClassSumBorrowingRate(0, 0.000008124373119358 * 1e18, 1180, "T7: ");

      assertAssetClassReserve(1, 0, "T7: ");
    }

    // Time passed for 60 seconds
    skip(60);

    // T8: Alice fully close JPY Short Position
    // updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(jpyAssetId, 136.533 * 1e3, 0);
    tickPrices[1] = 99039;
    tickPrices[6] = 86999;
    marketBuy(ALICE, 0, jpyMarketIndex, 6_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    assertEq(perpStorage.getEpochVolume(true, jpyMarketIndex), 6_000 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, jpyMarketIndex), 6_000 * 1e30);
    {
      // When Alice Buy JPY Market
      // And Alice has Short position
      // Then it means Alice decrease Short position
      // Given decrease size = 6000 USD (fully close)
      // And Price pump from T7 ~0.03%
      // JPY Price = 136.533 USDJPY (pyth price)
      //           = 0.007324236631437088469454271128 USD

      // Then Check position Info

      // Time passed          = 60 seconds (60 intervals)
      // TVL                  = 0.99662501 * 20000 = 19932.5002

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = -6000
      // new Market skew      = -6000 + 6000 (short position)
      // Premium before       = -6000 / 300000000 = -0.00002
      // Premium after        = 0 / 300000000 = 0
      // Premium median       = (-0.00002 + 0) / 2 = -0.00001
      // Adaptive price       = 0.007324236631437088469454271128 * (1 + -0.00001)
      //                      = 0.007324163389070774098569576585

      // Market's Funding rate
      // Funding rate         = -(Intervals * (Skew ratio * Max funding rate))
      //                      = -(60 * -6000 / 300000000 * 0.0004)
      //                      = 0.00000048
      // Funding rate         = currentFundingRate + (fundingRateVelocity * elapsedInterval / SECONDS_IN_DAY)
      // Funding rate         = currentFundingRate + (-(skew / maxSkeScale * maxFundingRate) * elapsedInterval / SECONDS_IN_DAY)
      //                      = 0 + ((-6000 / 300000000 * 0.0004) * 60 / 86400)
      //                      = 0.00000000000555555555555555556
      assertMarketFundingRate(jpyMarketIndex, -5555555, 1300, "T8: ");

      // Forex Borrowing rate
      //    = reserve * interval * base rate / tvl
      //    = 54 * 60 * 0.03% / 19932.5002
      //    = 0.000048764579969752
      assertAssetClassSumBorrowingRate(2, 0.000048764579969752 * 1e18, 1300, "T8: ");

      // JPY market IMF       = 0.01%
      // JPY market MMF       = 0.005%
      // Inc / Dec Fee        = 0.03%

      // Before:
      //    Position size     = -6000
      //    Avg Price         = 0.007346223635976286152964598193 USD
      //    Reserve           = 54 USD
      //    Borrowing rate    = 0
      //    Finding rate      = 0

      // After:
      //    Position size     = -6000 + 6000      = 0
      //    Avg price         = 0 USD (fully close)
      //    IMR               = 0
      //    MMR               = 0
      //    Reserve           = 0
      //    Borrowing rate    = 0
      //    Funding rate      = 0

      //    Trading fee       = 6000 * 0.03% = 1.8 USD

      //    Borrowing fee     = (0.000048764579969752 - 0) * 54 (reserve delta)
      //                      = 0.002633287318366608
      //    Funding fee       = (0.00000048 - 0) * 6000 (position size)
      //                      = 0.00288 USD

      // Profit and Loss
      // note: long position: size delta * (adaptive price - avg price) / avg price
      //       short position: size delta * (avg price - adaptive price) / avg price
      // unrealized PnL = 6000 * (0.007346223635976286152964598193 - 0.007324163389070774098569576585) / 0.007346223635976286152964598193
      //                = 18.01762211333523763485750665291 USD

      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: jpyMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T8: "
      });

      // Sub-account's state
      // According from T7
      //    IMR             =  7.5 USD
      //    MMR             = 3.75 USD
      // In Summarize
      //    IMR = 7.5 - 6   =  1.5 USD
      //    MMR = 3.75 - 3  = 0.75 USD

      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T8: " });

      // Assert Alice Sub-account's Collateral
      // According to T7, Alice's collateral balances
      //    BTC - 0.01026249
      // When Alice Buy JPY with 6000 USD (close Short position)
      // And Funding rate is position so Short pay Long
      // Then Alice should pay funding fee

      // Then Alice has to pay
      //    Trading fee   - 1.8 USD
      //    Borrowing fee - 0.002633287318366608 USD
      //    Funding fee   - 0.00288 USD

      // And Alice has to received
      //    Profit        - 18.01762211333523763485750665291 USD

      // Then Alice pay fee by Collateral
      //    BTC, (price: 20,000 USD)
      //      Trading fee     = 1.8 / 20000                   = 0.00009 btc
      //      Borrowing fee   = 0.002633287318366608 / 20000  = 0.00000013 btc
      //      Funding fee     = 0.00288 / 20000               = 0.00000014 btc

      // And Alice receive funding fee from HLP
      // When HLP pay Alice by Liquidity
      //    BTC, (price: 20,000 USD)
      //      Trader's profit = 18.01762211333523763485750665291 / 20000
      //                      = 0.00090088 btc

      // In Summarize, Alice's collateral balances
      //    BTC - 0.01026249 - 0.00009 - 0.00000013 - 0.00000014 + 0.00090088
      //        = 0.0110731

      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.01287252 * 1e8, "T8: ");

      // Assert Fee distribution
      // According from T7
      // Vault's fees
      //    BTC - protocol fee  = 0.00309563 btc
      //        - dev fee       = 0.00001687 btc
      // and HLP's liquidity
      //    BTC - 0.99662501 btc

      // Alice paid fees list
      //    Trading fee
      //      BTC - 0.00009 btc
      //          - pay for dev (15%)       = 0.0000135 btc
      //          - pay for protocol (85%)  = 0.00009 - 0.0000135
      //                                    = 0.0000765 btc
      //    Borrowing fee
      //      BTC - 0.00000013 btc
      //          - pay for dev (15%)       = 0.00000001 btc
      //          - pay for HLP (85%)       = 0.00000013 - 0.00000001
      //                                    = 0.00000012
      //    Funding fee
      //      BTC - 0.00000014 btc
      //          - pay for funding fee (100%) = 0.00000014 btc
      //

      // HLP paid list
      //    BTC
      //      Trader profit - 0.00090088 btc

      // In Summarize Vault's fees
      //    BTC - protocol fee  0.00309563 + 0.0000765              = 0.00317213 btc
      //        - dev fee       0.00001687 + 0.0000135 + 0.00000001 = 0.00003038 btc
      //        - funding fee   0.00000014 btc
      // and HLP's liquidity
      //    BTC - 0.99662501 + 0.00000012 - 0.00090088 = 0.99572425 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.0028809 * 1e8,
        _devFee: 0.00032026 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T8: "
      });

      assertHLPLiquidity(address(wbtc), 0.99572425 * 1e8, "T8: ");

      // Assert Market
      assertMarketLongPosition(jpyMarketIndex, 0, 0, "T8: ");
      assertMarketShortPosition(jpyMarketIndex, 0, 0, "T8: ");

      // Assert Asset class
      // Forex's reserve should be increased by = 54 USD
      assertAssetClassReserve(2, 0, "T8: ");

      // Invariant testing
      assertAssetClassReserve(0, 13.5 * 1e30, "T8: ");
      assertAssetClassSumBorrowingRate(0, 0.000008124373119358 * 1e18, 1180, "T8: ");

      assertAssetClassReserve(1, 0, "T8: ");
    }

    // Time passed for 60 seconds
    skip(60);

    // T9: Bob deposit BTC 100 USD at price 20,000
    // 100 / 20000 = 0.005 BTC
    address _bobSubAccount0 = getSubAccount(BOB, 0);
    depositCollateral(BOB, 0, wbtc, 0.01 * 1e8);

    assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.01 * 1e8, "T9: ");

    // And BOB create limit order to open long position for 3000 USD at Btc price 18,000 USD
    // Order Index: 0
    createLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _marketIndex: wbtcMarketIndex,
      _sizeDelta: 3000 * 1e30,
      _triggerPrice: 18_000 * 1e30,
      _acceptablePrice: 18450 * 1e30, // 18_000 * (1 + 0.025) = 18450
      _triggerAboveThreshold: false,
      _executionFee: executionOrderFee,
      _reduceOnly: false,
      _tpToken: address(wbtc)
    });

    // Time passed for 60 seconds
    skip(60);

    // T11: Btc Price has changed to 18,500 USD
    //      Should revert ILimitTradeHandler_InvalidPriceForExecution
    // updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 18_500 * 1e8, 0);
    tickPrices[1] = 98260;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 0,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });
    assertEq(perpStorage.getEpochVolume(true, wbtcMarketIndex), 0);
    assertEq(perpStorage.getEpochVolume(false, wbtcMarketIndex), 0);

    // T12: Btc Price has changed to 17,500 USD
    //      Execute Bob order index 0
    updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 17_500 * 1e8, 0);
    tickPrices[1] = 97704;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 0,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });
    {
      // When Limit order index 0 has executed
      // Then Bob should has Long position
      // And Position size should be 3000 USD at Price 18000 USD

      // Given Oracle price   = 17500 USD
      // And TVL
      //  - BTC               = 0.99572425 * 17500 = 17425.174375
      //  - Total             = 17425.174375 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 0
      // new Market skew      = 0 + 3000 (long position)
      // Premium before       = 0 / 300000000 = 0
      // Premium after        = 3000 / 300000000 = 0.00001
      // Premium median       = (0 + 0.00001) / 2 = 0.000005
      // Adaptive price       = 17500 * (1 + 0.000005) = 17500.0875
      //                      = 17500.0875

      // Market's Funding rate calculation
      // When Market skew is 0
      // Then Funding rate is 0
      assertMarketFundingRate(wbtcMarketIndex, 0, 1420, "T12: ");

      // Crypto Borrowing rate calculation
      // Given Latest info
      //    Reserve                 = 13.5 USD
      //    Sum borrowing rate      = 0.000008124373119358
      //    Latest borrowing time   = 1180
      // And Time passed            = 1420 - 1180 = 240 seconds (240 intervals)
      // Then
      //    Pending borrowing rate  = 13.5 * 240 * 0.01% / 17425.174375
      //                            = 0.000018593788103770
      // And Sum borrowing rate     = 0.000008124373119358 + 0.000018593788103770
      //                            = 0.000026718161223128
      assertAssetClassSumBorrowingRate(0, 0.000026718161223128 * 1e18, 1420, "T12: ");

      // BTC market IMF       = 1%
      // BTC market MMF       = 0.5%
      // Inc / Dec Fee        = 0.1%

      // Before:
      //    Position size     = 0
      //    Avg Price         = 0
      //    Reserve           = 0
      //    Borrowing rate    = 0
      //    Finding rate      = 0

      //    Borrowing fee     = 0
      //    Funding fee       = 0

      // After:
      //    Position size     = 3000
      //    Avg price         = 17500.0875 USD
      //    IMR               = 3000 * 1%   =  30 USD
      //    MMR               = 3000 * 0.5% =  15 USD
      //    Reserve           = 30 * 900%   = 270 USD
      //    Trading fee       = 3000 * 0.1% =   3 USD
      //    Borrowing rate    = 0.000026718161223128
      //    Funding rate      = 0

      // Profit and Loss
      // note: long position: size delta * (adaptive price - avg price) / avg price
      //       short position: size delta * (avg price - adaptive price) / avg price
      // unrealized PnL = 0

      // Given Limit price   = 18000 USD
      // And TVL
      //  - BTC               = 0.99572425 * 17500 = 17425.174375
      //  - Total             = 17425.174375 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 0
      // new Market skew      = 0 + 3000 (long position)
      // Premium before       = 0 / 300000000 = 0
      // Premium after        = 3000 / 300000000 = 0.00001
      // Premium median       = (0 + 0.00001) / 2 = 0.000005
      // Adaptive price       = 18000 * (1 + 0.000005) = 18000.09

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: 3_000 * 1e30,
        _avgPrice: 18000.09 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0.000026718161223128 * 1e18,
        _lastFundingAccrued: 0,
        _str: "T12: "
      });

      // BOB Sub-account's state
      //    IMR             = 0 USD
      //    MMR             = 0 USD
      // In Summarize
      //    IMR = 0 + 30    = 30 USD
      //    MMR = 0 + 15    = 15 USD

      assertSubAccountStatus({ _subAccount: _bobSubAccount0, _imr: 30 * 1e30, _mmr: 15 * 1e30, _str: "T12: " });

      // Invariant Testing
      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T12: " });

      // Assert Trader's balances, Vault's fees and HLP's Liquidity

      // Bob's collateral before settle payment
      //    BTC - 0.01 btc

      // Vault's fees before settle payment
      //    BTC - protocol fee  = 0.0028809 btc
      //        - dev fee       = 0.00032026 btc

      // HLP's liquidity before settle payment
      //    BTC - 0.99572425 btc

      // Settlement detail
      // Bob has to pay
      //    Trading fee   - 3 USD
      //      BTC - 3 / 17500               = 0.00017142 btc
      //          - pay for dev (10%)       = 0.00001714 btc
      //          - pay for protocol (90%)  = 0.00015428

      // And HLP has to pay
      //     nothing

      // Bob's collateral after settle payment
      //    BTC - 0.01 - 0.00017142 = 0.00982858 btc

      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.00982858 * 1e8, "T12: ");

      // Vault's fees after settle payment
      //    BTC - protocol fee  = 0.0028809 + 0.00015428 = 0.00303518 btc
      //        - dev fee       = 0.00032026 + 0.00001714 = 0.0003374 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.00303518 * 1e8,
        _devFee: 0.0003374 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T12: "
      });

      // HLP's liquidity after settle payment
      //    nothing changed
      assertHLPLiquidity(address(wbtc), 0.99572425 * 1e8, "T12: ");

      // Asset Market's state, Asset class's state

      assertMarketLongPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 3000 * 1e30,
        _avgPrice: 18_000.09 * 1e30,
        _str: "T12: "
      });
      // And Short side should invariant
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T12: " });

      // Assert Asset class
      // Given Crypto's reserve is 13.5
      // When Bob increase Btc position for 3000 USD
      // And reserve is 270 USD
      // Then Crypto's reserve should increased by 270 = 283.5 USD
      assertAssetClassReserve(0, 283.5 * 1e30, "T12: ");

      // Invariant testing
      assertAssetClassReserve(2, 0, "T12: ");
      assertAssetClassReserve(1, 0, "T12: ");
    }

    // T13: Bob create limit order to close position
    // Order Index: 1
    createLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _marketIndex: wbtcMarketIndex,
      _sizeDelta: -3000 * 1e30,
      _triggerPrice: 18_900 * 1e30,
      _acceptablePrice: 18427.5 * 1e30, // 18_900 * (1 - 0.025) = 18427.5
      _triggerAboveThreshold: true,
      _executionFee: executionOrderFee,
      _reduceOnly: true,
      _tpToken: address(wbtc)
    });

    // Time passed for 60 seconds
    skip(60);

    // T14: Btc Price has changed to 18,500 USD
    //      Execute Bob order index 1, but price is not trigger
    //      Should revert ILimitTradeHandler_InvalidPriceForExecution
    // updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 18_500 * 1e8, 0);
    tickPrices[1] = 98260;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 1,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });

    // T15: Btc Price has changed to 18,900.01 USD
    //      Execute Bob order index 1
    updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 18_900.01 * 1e8, 0);
    tickPrices[1] = 98475;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 1,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });
    assertEq(perpStorage.getEpochVolume(true, wbtcMarketIndex), 3000 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wbtcMarketIndex), 3000 * 1e30);
    {
      // When Limit order index 1 has executed
      // Then Bob Btc Long position would decreased by 3000 USD at price 18,900 USD
      // And Bob's position has been closed

      // Given Oracle price   = 18,900.01 USD
      // And TVL
      //  - BTC               = 0.99572425 * 18900.01 = 18819.1982822425
      //  - Total             = 18819.1982822425 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 3000
      // new Market skew      = 3000 - 0
      // Premium before       = 3000 / 300000000 = 0.00001
      // Premium after        = 0 / 300000000 = 0
      // Premium median       = (0.00001 + 0) / 2 = 0.000005
      // Adaptive price       = 18900.01 * (1 + 0.000005)
      //                      = 18900.10450005

      // Market's Funding rate calculation
      // When Market skew is 3000
      // And Funding rate formula = -(Intervals * (Skew ratio * Max funding rate))
      // And Time passed         = 1480 - 1420 = 60 seconds (60 intervals)
      // Then Funding rate       = -(60 * (3000 / 300000000) * 0.04%)
      //                         = -0.00000024
      assertMarketFundingRate(wbtcMarketIndex, 2777777, 1480, "T15: ");

      // Crypto Borrowing rate calculation
      // Given Latest info
      //    Reserve                 = 283.5 USD
      //    Sum borrowing rate      = 0.000026718163837437
      //    Latest borrowing time   = 1420
      // And Time passed            = 1480 - 1420 = 60 seconds (60 intervals)
      // Then
      //    Pending borrowing rate  = 283.5 * 60 * 0.01% / 18819.1982822425
      //                            = 0.000090386422125380
      // And Sum borrowing rate     = 0.000026718161223128 + 0.000090386422125380
      //                            = 0.000117104583348508
      assertAssetClassSumBorrowingRate(0, 0.000117104583348508 * 1e18, 1480, "T15: ");

      // BTC market IMF       = 1%
      // BTC market MMF       = 0.5%
      // Inc / Dec Fee        = 0.1%

      // Before:
      //    Position size     = 3000
      //    Avg Price         = 18000 USD
      //    Reserve           = 270 USD
      //    Borrowing rate    = 0.000026718163837437
      //    Finding rate      = -0.00000024

      // After: (close position)
      //    Position size     = 0
      //    Avg price         = 0
      //    IMR               = 0
      //    MMR               = 0
      //    Reserve           = 0
      //    Borrowing rate    = 0
      //    Funding rate      = 0

      //    Trading fee       = 3000 * 0.1% = 3 USD

      //    Borrowing fee     = 270 * (0.000117104583348508 - 0.000026718163837437)
      //                      = 0.02440433326798917 USD
      //    Funding fee       = (-0.00000024 - 0) * 3000
      //                      = -0.00072 USD

      // Profit and Loss
      // note: long position: size delta * (adaptive price - avg price) / avg price
      //       short position: size delta * (avg price - adaptive price) / avg price
      // unrealized PnL = 3000 * (18900 - 18000) / 18000
      //                = 150 USD

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T15: "
      });

      // BOB Sub-account's state
      //    IMR             = 30 USD
      //    MMR             = 15 USD
      // In Summarize, after close position
      //    IMR = 30 - 30   = 0 USD
      //    MMR = 15 - 15   = 0 USD

      assertSubAccountStatus({ _subAccount: _bobSubAccount0, _imr: 0, _mmr: 0, _str: "T15: " });

      // Invariant Testing
      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T15: " });

      // Assert Trader's balances, Vault's fees and HLP's Liquidity

      // Bob's collateral before settle payment
      //    BTC - 0.00982858 btc

      // Vault's fees before settle payment
      //    BTC - protocol fee  = 0.00303518 btc
      //        - dev fee       = 0.0003374 btc

      // HLP's liquidity before settle payment
      //    BTC - 0.99572425 btc

      // Settlement detail
      // Bob has to pay
      //    Trading fee - 3 USD
      //      BTC - 3 / 18900.01                    = 0.00015873 btc
      //          - pay for dev (10%)               = 0.00001587 btc
      //          - pay for protocol (90%)          = 0.00014286
      //    Borrowing fee - 0.02440433326798917 USD
      //      BTC - 0.02440433326798917 / 18900.01  = 0.00000129 btc
      //          - pay for dev (10%)               = 0.00000012 btc
      //          - pay for HLP (90%)               = 0.00000117
      //    Funding fee - 0.00072 USD
      //      BTC - 0.00072 / 18900.01              = 0.00000003 btc
      //          - pay for funding fee (100%)      = 0.00000003 btc
      //

      // And HLP has to pay
      //    Trader profit - 150 USD
      //      BTC - 150 / 18900.01                  = 0.00793650 btc

      // Bob's collateral after settle payment
      //    BTC = 0.00982858 - 0.00015873 - 0.00000129 - 0.00000003 + 0.00793650
      //        = 0.01760503 btc

      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.01760503 * 1e8, "T15: ");

      // Vault's fees after settle payment
      //    BTC - protocol fee  = 0.00303518 + 0.00014286              = 0.00317804 btc
      //        - dev fee       = 0.0003374 + 0.00001587 + 0.00000012  = 0.00035339 btc
      //        - funding fee   = 0.00000014 + 0.00000003              = 0.00000017 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.00317804 * 1e8,
        _devFee: 0.00035339 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T15: "
      });

      // HLP's liquidity after settle payment
      //    BTC - 0.99572425 + 0.0000011 - 0.00793650 = 0.98778885
      assertHLPLiquidity(address(wbtc), 0.98778885 * 1e8, "T15: ");

      // Asset Market's state, Asset class's state

      assertMarketLongPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T15: " });
      // And Short side should invariant
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T15: " });

      // Assert Asset class
      // Given Crypto's reserve is 283.5
      // When Bob decrease Btc long position for 3000 USD
      // And deceased reserve is 270 USD
      // Then Crypto's reserve should decreased by 270 = 13.5 USD
      assertAssetClassReserve(0, 13.5 * 1e30, "T15: ");

      // Invariant testing
      assertAssetClassReserve(2, 0, "T15: ");
      assertAssetClassReserve(1, 0, "T15: ");
    }

    // T16: Bob create limit order sell Btc for 3000 USD at price 21,000 USD
    // Order Index: 2

    // Given Limit price   = 21000 USD
    // And TVL
    //  - BTC               = 0.99572425 * 17500 = 17425.174375
    //  - Total             = 17425.174375 USD

    // Max Funding rate     = 0.04%
    // Max scale skew       = 300,000,000 USD
    // Market skew          = 0
    // new Market skew      = 0 + 3000 (long position)
    // Premium before       = 0 / 300000000 = 0
    // Premium after        = 3000 / 300000000 = 0.00001
    // Premium median       = (0 + 0.00001) / 2 = 0.000005
    // Adaptive price       = 21000 * (1 - 0.000005) = 20999.895

    createLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _marketIndex: wbtcMarketIndex,
      _sizeDelta: -3000 * 1e30,
      _triggerPrice: 21_000 * 1e30,
      _acceptablePrice: 20475 * 1e30, // 21_000 * (1 - 0.025) = 20475
      _triggerAboveThreshold: true,
      _executionFee: executionOrderFee,
      _reduceOnly: false,
      _tpToken: address(wbtc)
    });

    // Time passed for 60 seconds
    skip(60);

    // T17: Btc Price has changed to 21,500 USD
    //      Execute Bob order index 2
    updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 21_500 * 1e8, 0);
    tickPrices[1] = 99763;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 2,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });
    assertEq(perpStorage.getEpochVolume(true, wbtcMarketIndex), 3000 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wbtcMarketIndex), 6000 * 1e30);
    {
      // When Limit order index 2 has executed
      // Then Bob would has Btc Short position size 3000 USD at price 21,000 USD

      // Given Oracle price   = 21,500 USD
      // And TVL
      //  - BTC               = 0.98778885 * 21500 = 21237.460275
      //  - Total             = 21237.460275 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = 0
      // new Market skew      = 0 - 3000
      // Premium before       = 0 / 300000000 = 0
      // Premium after        = -3000 / 300000000 = -0.00001
      // Premium median       = (0 + -0.00001) / 2 = -0.000005
      // Adaptive price       = 21500 * (1 - 0.000005)
      //                      = 21499.8925 USD

      // Market's Funding rate calculation
      // When Market skew is 0
      // And Funding rate formula        = -(Intervals * (Skew ratio * Max funding rate))
      // And Time passed                = 1540 - 1480 = 60 seconds (60 intervals)
      // Then Pending Funding rate      = -(60 * (0 / 300000000) * 0.04%)
      //                                = 0
      // And Market's sum Funding rate  = -0.00000024 + 0
      assertMarketFundingRate(wbtcMarketIndex, 2777777, 1540, "T17: ");

      // Crypto Borrowing rate calculation
      // Given Latest info
      //    Reserve                 = 13.5 USD
      //    Sum borrowing rate      = 0.000117104583348508
      //    Latest borrowing time   = 1480
      // And Time passed            = 1540 - 1480 = 60 seconds (60 intervals)
      // Then
      //    Pending borrowing rate  = 13.5 * 60 * 0.01% / 21237.460275
      //                            = 0.000003814015374303
      // And Sum borrowing rate     = 0.000117104583348508 + 0.000003814015374303
      //                            = 0.000120918598722811
      assertAssetClassSumBorrowingRate(0, 0.000120918598722811 * 1e18, 1540, "T17: ");

      // BTC market IMF       = 1%
      // BTC market MMF       = 0.5%
      // Inc / Dec Fee        = 0.1%

      // Before:
      //    Position size     = 0
      //    Avg Price         = 0
      //    Reserve           = 0
      //    Borrowing rate    = 0
      //    Finding rate      = 0

      // After: (new position)
      //    Position size     = -3000 USD
      //    Avg price         = 21,000 USD
      //    IMR               = 30
      //    MMR               = 15
      //    Reserve           = 270
      //    Borrowing rate    = 0.000120918598722811
      //    Funding rate      = -0.00000024

      //    Trading fee       = 3000 * 0.1% = 3 USD

      //    Borrowing fee     = 0
      //    Funding fee       = 0

      // Profit and Loss
      // note: long position: size delta * (adaptive price - avg price) / avg price
      //       short position: size delta * (avg price - adaptive price) / avg price
      // unrealized PnL = 0 (new position)

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: -3_000 * 1e30,
        _avgPrice: 20999.895 * 1e30,
        _reserveValue: 270 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0.000120918598722811 * 1e18,
        _lastFundingAccrued: -2893,
        _str: "T17: "
      });

      // BOB Sub-account's state
      //    IMR             = 0 USD
      //    MMR             = 0 USD
      // In Summarize, after close position
      //    IMR = 0 + 30   = 30 USD
      //    MMR = 0 + 15   = 15 USD

      assertSubAccountStatus({ _subAccount: _bobSubAccount0, _imr: 30 * 1e30, _mmr: 15 * 1e30, _str: "T17: " });

      // Invariant Testing
      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T17: " });

      // Assert Trader's balances, Vault's fees and HLP's Liquidity

      // Bob's collateral before settle payment
      //    BTC - 0.01760503 btc

      // Vault's fees before settle payment
      //    BTC - protocol fee  = 0.00317804 btc
      //        - dev fee       = 0.00035339 btc
      //        - funding fee   = 0.00000017 btc

      // HLP's liquidity before settle payment
      //    BTC - 0.98778896 btc

      // Settlement detail
      // Bob has to pay
      //    Trading fee - 3 USD
      //      BTC - 3 / 21500                    = 0.00013953 btc
      //          - pay for dev (10%)            = 0.00001395 btc
      //          - pay for protocol (90%)       = 0.00012558

      // And HLP has to pay
      //    nothing

      // Bob's collateral after settle payment
      //    BTC = 0.01760503 - 0.00013953
      //        = 0.01746550 btc

      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.01746550 * 1e8, "T17: ");

      // Vault's fees after settle payment
      //    BTC - protocol fee  = 0.00317804 + 0.00012558 = 0.00330362 btc
      //        - dev fee       = 0.00035339 + 0.00001395 = 0.00036734 btc
      //        - funding fee   = 0.00000017              = 0.00000017 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.00330362 * 1e8,
        _devFee: 0.00036734 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T17: "
      });

      // HLP's liquidity after settle payment
      //    BTC - 0.98778885
      assertHLPLiquidity(address(wbtc), 0.98778885 * 1e8, "T17: ");

      // Asset Market's state, Asset class's state

      assertMarketLongPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T17: " });
      // And Short side should invariant
      assertMarketShortPosition({
        _marketIndex: wbtcMarketIndex,
        _positionSize: 3000 * 1e30,
        _avgPrice: 20999.895 * 1e30,
        _str: "T17: "
      });

      // Assert Asset class
      // Given Crypto's reserve is 283.5
      // When Bob open Btc short position for 3000 USD
      // And increase reserve as 270 USD
      // Then Crypto's reserve should increased by 270 = 283.5 USD
      assertAssetClassReserve(0, 283.5 * 1e30, "T17: ");

      // Invariant testing
      assertAssetClassReserve(2, 0, "T17: ");
      assertAssetClassReserve(1, 0, "T17: ");
    }

    // T18: Bob create limit order close short position 3000 USD at price 18,900 USD
    // Order Index: 3
    // Create wrong order first
    createLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _marketIndex: wbtcMarketIndex,
      _sizeDelta: -3000 * 1e30,
      _triggerPrice: 18_900 * 1e30,
      _acceptablePrice: 0,
      _triggerAboveThreshold: false,
      _executionFee: executionOrderFee,
      _reduceOnly: true,
      _tpToken: address(wbtc)
    });

    // Time passed for 60 seconds
    skip(60);

    // T19: Btc Price has changed to 17,500.00 USD
    //      Execute Bob order index 2
    updatePriceData = new bytes[](1);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 17_500 * 1e8, 0);
    tickPrices[1] = 97704;
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 3,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });

    // Create the correct order
    createLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _marketIndex: wbtcMarketIndex,
      _sizeDelta: 3000 * 1e30,
      _triggerPrice: 18_900 * 1e30,
      _acceptablePrice: 19372.5 * 1e30, // 18_900 * (1 + 0.025) = 19372.5
      _triggerAboveThreshold: false,
      _executionFee: executionOrderFee,
      _reduceOnly: true,
      _tpToken: address(wbtc)
    });
    executeLimitTradeOrder({
      _account: BOB,
      _subAccountId: 0,
      _orderIndex: 4,
      _feeReceiver: payable(FEEVER),
      _tickPrices: tickPrices,
      _publishTimeDiffs: publishTimeDiff,
      _minPublishTime: block.timestamp
    });
    assertEq(perpStorage.getEpochVolume(true, wbtcMarketIndex), 6000 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wbtcMarketIndex), 6000 * 1e30);

    skip(60);
    {
      // When Limit order index 2 has executed
      // Then Bob fully close Btc short position at price 18,900 USD

      // Given Oracle price   = 17,500 USD
      // And TVL
      //  - BTC               = 0.98778885 * 17500 = 17286.304875 USD
      //  - Total             = 17286.304875 USD

      // Max Funding rate     = 0.04%
      // Max scale skew       = 300,000,000 USD
      // Market skew          = -3000
      // new Market skew      = -3000 + 3000
      // Premium before       = -3000 / 300000000 = -0.00001
      // Premium after        = 0 / 300000000 = 0
      // Premium median       = (-0.00001 + 0) / 2 = -0.000005
      // Adaptive price       = 17500 * (1 + -0.000005)
      //                      = 17499.9125

      // Market's Funding rate calculation
      // When Market skew is -3000
      // And Funding rate formula = -(Intervals * (Skew ratio * Max funding rate))
      // And Time passed         = 1600 - 1549 = 60 seconds (60 intervals)
      // Then Funding rate       = -(60 * (-3000 / 300000000) * 0.04%)
      //                         = 0.00000024
      // And Market's sum Funding rate  = -0.00000024 + 0.00000024
      assertMarketFundingRate(wbtcMarketIndex, 0, 1600, "T19: ");

      // Crypto Borrowing rate calculation
      // Given Latest info
      //    Reserve                 = 283.5 USD
      //    Sum borrowing rate      = 0.000026718163837437
      //    Latest borrowing time   = 1420
      // And Time passed            = 1480 - 1420 = 60 seconds (60 intervals)
      // Then
      //    Pending borrowing rate  = 283.5 * 60 * 0.01% / 17286.304875
      //                            = 0.000098401596657018
      // And Sum borrowing rate     = 0.000120918598722811 + 0.000098401596657018
      //                            = 0.000219320195379829
      assertAssetClassSumBorrowingRate(0, 0.000219320195379829 * 1e18, 1600, "T19: ");

      // BTC market IMF       = 1%
      // BTC market MMF       = 0.5%
      // Inc / Dec Fee        = 0.1%

      // Before:
      //    Position size     = -3000
      //    Avg Price         = 21000 USD
      //    Reserve           = 270 USD
      //    Borrowing rate    = 0.000120918598722811
      //    Finding rate      = -0.00000024

      // After: (close short position)
      //    Position size     = 0
      //    Avg price         = 0
      //    IMR               = 0
      //    MMR               = 0
      //    Reserve           = 0
      //    Borrowing rate    = 0
      //    Funding rate      = 0

      //    Trading fee       = 3000 * 0.1% = 3 USD

      //    Borrowing fee     = 270 * (0.000219320195379829 - 0.000120918598722811)
      //                      = 0.02656843109739486 USD
      //    Funding fee       = (0 - -(0.00000024)) * 3000
      //                      = 0.00072 USD

      // Profit and Loss
      // note: long position: size delta * (adaptive price - avg price) / avg price
      //       short position: size delta * (avg price - adaptive price) / avg price
      // unrealized PnL = 3000 * (21000 - 18900) / 21000
      //                = 300 USD
      // !note: but max profit is 270 then Bob will realized profit just 270 USD

      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wbtcMarketIndex,
        _positionSize: 0,
        _avgPrice: 0,
        _reserveValue: 0,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "T19: "
      });

      // BOB Sub-account's state
      //    IMR             = 30 USD
      //    MMR             = 15 USD
      // In Summarize, after close position
      //    IMR = 30 - 30   = 0 USD
      //    MMR = 15 - 15   = 0 USD

      assertSubAccountStatus({ _subAccount: _bobSubAccount0, _imr: 0, _mmr: 0, _str: "T19: " });

      // Invariant Testing
      assertSubAccountStatus({ _subAccount: _aliceSubAccount0, _imr: 1.5 * 1e30, _mmr: 0.75 * 1e30, _str: "T19: " });

      // Assert Trader's balances, Vault's fees and HLP's Liquidity

      // Bob's collateral before settle payment
      //    BTC - 0.01746550 btc

      // Vault's fees before settle payment
      //    BTC - protocol fee  = 0.00330362 btc
      //        - dev fee       = 0.00036734 btc

      // HLP's liquidity before settle payment
      //    BTC - 0.98778885 btc

      // Settlement detail
      // Bob has to pay
      //    Trading fee - 3 USD
      //      BTC - 3 / 17500                       = 0.00017142 btc
      //          - pay for dev (10%)               = 0.00001714 btc
      //          - pay for protocol (90%)          = 0.00015428
      //    Borrowing fee - 0.02656843109739486 USD
      //      BTC - 0.02656843109739486 / 17500     = 0.00000151 btc
      //          - pay for dev (10%)               = 0.00000015 btc
      //          - pay for HLP (90%)               = 0.00000136
      //    Funding fee - 0.00072 USD
      //      BTC - 0.00072 / 17500                 = 0.00000004 btc
      //          - pay for funding fee (100%)      = 0.00000004 btc

      // And HLP has to pay
      //    Trader profit - 270 USD
      //      BTC - 270 / 17500                     = 0.01542857 btc

      // Bob's collateral after settle payment
      //    BTC = 0.01746550 - 0.00017142 - 0.00000151 - 0.00000004 + 0.01542857
      //        = 0.03272110 btc

      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 0.03272110 * 1e8, "T19: ");

      // Vault's fees after settle payment
      //    BTC - protocol fee  = 0.00330362 + 0.00015428              = 0.0034579 btc
      //        - dev fee       = 0.00036734 + 0.00001714 + 0.00000015 = 0.00038463 btc
      //        - funding fee   = 0.00000017 + 0.00000004              = 0.00000021 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: 0.0034579 * 1e8,
        _devFee: 0.00038463 * 1e8,
        _fundingFeeReserve: 0,
        _str: "T19: "
      });

      // HLP's liquidity after settle payment
      //    BTC = 0.98778885 + 0.00000129 - 0.01542857
      //        = 0.97236157
      assertHLPLiquidity(address(wbtc), 0.97236157 * 1e8, "T19: ");

      // Asset Market's state, Asset class's state

      assertMarketLongPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T19: " });
      // And Short side should invariant
      assertMarketShortPosition({ _marketIndex: wbtcMarketIndex, _positionSize: 0, _avgPrice: 0, _str: "T19: " });

      // Assert Asset class
      // Given Crypto's reserve is 283.5
      // When Bob decrease Btc short position for 3000 USD
      // And deceased reserve is 270 USD
      // Then Crypto's reserve should decreased by 270 = 13.5 USD
      assertAssetClassReserve(0, 13.5 * 1e30, "T19: ");

      // Invariant testing
      assertAssetClassReserve(2, 0, "T19: ");
      assertAssetClassReserve(1, 0, "T19: ");
    }

    // Test where epoch length is changed
    skip(30 minutes);

    marketBuy(ALICE, 0, wethMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    assertEq(perpStorage.getEpochVolume(true, wethMarketIndex), 300 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wethMarketIndex), 0);

    perpStorage.setMovingWindowConfig(15, 1 minutes);

    skip(2 minutes);

    assertEq(perpStorage.getEpochVolume(true, wethMarketIndex), 300 * 1e30);
    assertEq(perpStorage.getEpochVolume(false, wethMarketIndex), 0);
  }
}
