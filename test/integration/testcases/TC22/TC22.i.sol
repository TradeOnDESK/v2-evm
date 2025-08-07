// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

contract TC22 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  // TC22 - Trade with max position size
  function testCorrectness_TC22_TradeWithMaxPositionSize() external {
    // ### Scenario: Prepare environment

    // mint native token
    vm.deal(BOB, 1 ether);
    vm.deal(ALICE, 1 ether);
    vm.deal(CAROL, 1 ether);
    vm.deal(FEEVER, 1 ether);
    // @todo - fix function in bot handler to be payable
    vm.deal(address(botHandler), 1 ether);

    // mint BTC
    wbtc.mint(ALICE, 100 * 1e8);
    wbtc.mint(BOB, 1000 * 1e8);
    wbtc.mint(CAROL, 100 * 1e8);

    // warp to block timestamp 1000
    vm.warp(1000);

    address _aliceSubAccount0 = getSubAccount(ALICE, 0);
    address _bobSubAccount0 = getSubAccount(BOB, 0);
    address _carolSubAccount0 = getSubAccount(CAROL, 0);

    // Given BTC price is 20,000 USD
    // And WETH price is 1,500 USD
    // And APPLE price is 152 USD
    updatePriceData = new bytes[](3);
    // updatePriceData[0] = _createPriceFeedUpdateData(wbtcAssetId, 20000 * 1e8, 0);
    // updatePriceData[1] = _createPriceFeedUpdateData(wethAssetId, 1500 * 1e8, 0);
    // updatePriceData[2] = _createPriceFeedUpdateData(jpyAssetId, 152 * 1e3, 0);
    tickPrices[0] = 73135; // ETH tick price $1500
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[6] = 50241; // JPY tick price $152

    // And Bob provide liquidity 500 btc
    addLiquidity(BOB, wbtc, 500 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);
    {
      // HLP liquidity and total supply should be corrected
      // 500 * 0.997 = 498.5
      // 498.5 * 20000 = 9_970_000
      // Max utilized = 9_970_000 * 0.8 = 7_976_000
      assertHLPLiquidity(address(wbtc), 498.5 * 1e8);
      assertHLPTotalSupply(9_970_000 * 1e18);
      assertTVL(9_970_000 * 1e30, false);
    }

    // And Alice deposit 50 btc as Collateral
    depositCollateral(ALICE, 0, wbtc, 50 * 1e8);
    // And Bob deposit 50 btc as Collateral
    depositCollateral(BOB, 0, wbtc, 50 * 1e8);
    // And Carol deposit 50 btc as Collateral
    depositCollateral(CAROL, 0, wbtc, 50 * 1e8);
    {
      // check balances
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 50 * 1e8);
      assertSubAccountTokenBalance(_bobSubAccount0, address(wbtc), true, 50 * 1e8);
      assertSubAccountTokenBalance(_carolSubAccount0, address(wbtc), true, 50 * 1e8);

      assertTokenBalanceOf(ALICE, address(wbtc), 50 * 1e8, "Alice's wbtc: ");
      assertTokenBalanceOf(BOB, address(wbtc), 450 * 1e8, "Bob's usdc: ");
      assertTokenBalanceOf(CAROL, address(wbtc), 50 * 1e8, "Carol's usdc: ");
    }

    // ### Scenario: Trader trade normally, and someone reach max position size
    // When Alice buy WETH 7,000,000 USD
    marketBuy(ALICE, 0, wethMarketIndex, 7_000_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice's position should be corrected
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: int256(7_000_000 * 1e30),
        _avgPrice: 1517.499999999999999999999999999 * 1e30,
        _reserveValue: 630_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "Alice's BTC position"
      });
    }

    // But Bob buy 4,000,000 USD
    // And Revert ITradeService_PositionSizeExceed
    marketBuy(
      BOB,
      0,
      wethMarketIndex,
      4_000_000 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_PositionSizeExceed()"
    );

    // But Bob can sell WETH 8,000,000 USD
    marketSell(BOB, 0, wethMarketIndex, 8_000_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Bob's position should be corrected
      assertPositionInfoOf({
        _subAccount: _bobSubAccount0,
        _marketIndex: wethMarketIndex,
        _positionSize: -int256(8_000_000 * 1e30),
        _avgPrice: 1515 * 1e30,
        _reserveValue: 720_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "Bob's BTC position"
      });
    }

    // When Carol sell WETH 3,000,000 USD
    // And Revert ITradeService_PositionSizeExceed
    marketSell(
      CAROL,
      0,
      wethMarketIndex,
      3_000_000 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_PositionSizeExceed()"
    );

    // ### Scenario: Trader trade on Stock (APPLE)
    // When Alice sell APPLE 600,000 USD
    marketSell(ALICE, 0, appleMarketIndex, 600_000 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Then Alice's position should be corrected
      assertPositionInfoOf({
        _subAccount: _aliceSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: -int256(600_000 * 1e30),
        _avgPrice: 151.848 * 1e30,
        _reserveValue: 270_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "Alice's APPLE position"
      });
    }

    // When Carol buy APPLE 10,000,000 USD
    marketBuy(
      CAROL,
      0,
      appleMarketIndex,
      10_000_000 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp
    );
    {
      // Then Carol's position should be corrected
      assertPositionInfoOf({
        _subAccount: _carolSubAccount0,
        _marketIndex: appleMarketIndex,
        _positionSize: int256(10_000_000 * 1e30),
        _avgPrice: 154.229333333333333333333333333232 * 1e30,
        _reserveValue: 4_500_000 * 1e30,
        _realizedPnl: 0,
        _entryBorrowingRate: 0,
        _lastFundingAccrued: 0,
        _str: "Carol's APPLE position"
      });
    }

    // When Bob's buy APPLE 1 USD
    // And Revert ITradeService_PositionSizeExceed
    marketBuy(
      BOB,
      0,
      appleMarketIndex,
      1 * 1e30,
      address(wbtc),
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      "ITradeService_PositionSizeExceed()"
    );
  }
}
