// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

contract Calculator_LiquidateAndCheckGlobalPnl is BaseIntTest_WithActions {
  function _prepareEnviroment() private {
    configStorage.setPnlFactor(1 * 10000);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);
    usdc.mint(BOB, 100_000 * 1e6);
    usdc.mint(CAROL, 100_000 * 1e6);
    usdc.mint(DAVE, 100_000 * 1e6);
    usdc.mint(EVE, 10_000 * 1e6);

    vm.deal(BOB, 1 ether);
    vm.deal(CAROL, 1 ether);
    vm.deal(DAVE, 1 ether);
    vm.deal(EVE, 1 ether);

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

    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    depositCollateral(CAROL, 0, ERC20(address(usdc)), 100_000 * 1e6);
    depositCollateral(DAVE, 0, ERC20(address(usdc)), 100_000 * 1e6);
    depositCollateral(EVE, 0, ERC20(address(usdc)), 10_000 * 1e6);
  }

  function testIntegration_WhenCallGetGlobalPnl() external {
    _prepareEnviroment();

    // Before any trading global pnl must start with Zero
    {
      assertEq(calculator.getGlobalPNLE30(), 0, "getGlobalPNLE30");
    }

    // Traders Opening Positions
    // WETH Market
    marketBuy(BOB, 0, wethMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);
    marketSell(CAROL, 0, wethMarketIndex, 50_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);
    // WBTC Market
    marketBuy(DAVE, 0, wbtcMarketIndex, 25_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);
    {
      (int256 BobUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 CarolUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);
      (int256 DaveUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(DAVE, 0), 0, 0);
      int256 totalUnrealizedPnlForTrader = BobUnrealizedPnl + CarolUnrealizedPnl + DaveUnrealizedPnl;
      int256 totalUnrealizedPnlForHlp = totalUnrealizedPnlForTrader < 0
        ? -totalUnrealizedPnlForTrader
        : totalUnrealizedPnlForTrader;
      assertApproxEqRel(calculator.getGlobalPNLE30(), totalUnrealizedPnlForHlp, MAX_DIFF, "getGlobalPNLE30");
    }

    // Update ETH Price from 1,500 -> 1555.6247687960245
    vm.warp(block.timestamp + 100);
    tickPrices[0] = 73500; // ETH tick price $1555.6247687960245
    setPrices(tickPrices, publishTimeDiff);

    {
      (int256 BobUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 CarolUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);
      (int256 DaveUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(DAVE, 0), 0, 0);

      int256 totalUnrealizedPnlForTrader = BobUnrealizedPnl + CarolUnrealizedPnl + DaveUnrealizedPnl;
      int256 totalUnrealizedPnlForHlp = totalUnrealizedPnlForTrader > 0
        ? -totalUnrealizedPnlForTrader
        : totalUnrealizedPnlForTrader;
      assertApproxEqRel(calculator.getGlobalPNLE30(), totalUnrealizedPnlForHlp, MAX_DIFF, "getGlobalPNLE30");
    }

    // WETH Market
    marketSell(EVE, 0, wethMarketIndex, 600_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);
    {
      // Currently EVE's equity must greater than mmr
      assertTrue(uint(calculator.getEquity(getSubAccount(EVE, 0), 0, 0)) > calculator.getMMR(getSubAccount(EVE, 0)));
    }

    // Update ETH Price from 1,500 -> 1571.258272065732
    vm.warp(block.timestamp + 100);
    tickPrices[0] = 73600; // ETH tick price 1571.258272065732
    setPrices(tickPrices, publishTimeDiff);

    // Make EVE's position liquidate able
    {
      // Currently EVE's equity must greater than mmr
      assertTrue(uint(calculator.getEquity(getSubAccount(EVE, 0), 0, 0)) < calculator.getMMR(getSubAccount(EVE, 0)));
    }

    // Call liquidate
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    botHandler.liquidate(
      getSubAccount(EVE, 0),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assert Global Pnl before calls liquidate
    {
      (int256 BobUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(BOB, 0), 0, 0);
      (int256 CarolUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(CAROL, 0), 0, 0);
      (int256 DaveUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(DAVE, 0), 0, 0);
      (int256 EveUnrealizedPnl, ) = calculator.getUnrealizedPnlAndFee(getSubAccount(EVE, 0), 0, 0);

      int256 totalUnrealizedPnlForTrader = BobUnrealizedPnl + CarolUnrealizedPnl + DaveUnrealizedPnl + EveUnrealizedPnl;
      int256 totalUnrealizedPnlForHlp = totalUnrealizedPnlForTrader > 0
        ? -totalUnrealizedPnlForTrader
        : totalUnrealizedPnlForTrader;
      assertApproxEqRel(calculator.getGlobalPNLE30(), totalUnrealizedPnlForHlp, MAX_DIFF, "getGlobalPNLE30");
    }
  }
}
