// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { console } from "forge-std/console.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract TC30 is BaseIntTest_WithActions {
  function test_correctness_executeMultipleOrders() external {
    // T0: Initialized state
    uint256 _pythGasFee = initialPriceFeedDatas.length;

    vm.deal(ALICE, executionOrderFee);
    uint256 _aliceBTCAmount = 1e8;
    wbtc.mint(ALICE, _aliceBTCAmount);

    // Alice Create Order
    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      _aliceBTCAmount,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 1, "liquidityOrder size After Created");
      assertEq(liquidityOrders[0].orderId, 0, "OrderId After Created");
    }
    //  ALICE add 1 BTC
    //  hlp Liquidity => (wbtc) 0.9970000
    // fee (wbtc) 0.003000000
    // feetotal (wbtc) 0.003000000
    // ALICE received HLP amount = 19,940.00
    // hlpTotalSupply = 19,940.00

    vm.deal(ALICE, executionOrderFee);
    uint256 _aliceUSDCAmount = 20_000 * 1e6;
    usdc.mint(ALICE, _aliceUSDCAmount);
    addLiquidity(
      ALICE,
      ERC20(address(usdc)),
      _aliceUSDCAmount,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 2, "liquidityOrder size After Created");
      assertEq(liquidityOrders[1].orderId, 1, "OrderId After Created");
    }
    // ALICE add 20000 USDC
    // hlp liquidity  (wbtc) 0.9970000  => (wbtc) 0.9970000, usdc(19840.0000000)
    // fee = 160 (usdc)
    // feetotal 0.003000000 (wbtc) + 160 (usdc)
    // ALICE received HLP amount = 19,840.00
    //hlpTotalSupply = 39780

    uint256 _bobUSDCAmount = 0.5 * 1e6;
    vm.deal(BOB, executionOrderFee);
    usdc.mint(BOB, _bobUSDCAmount);
    addLiquidity(
      BOB,
      ERC20(address(usdc)),
      _bobUSDCAmount,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );

    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 3, "liquidityOrder size After Created");
      assertEq(liquidityOrders[2].orderId, 2, "OrderId After Created");
    }
    // BOB ADD 0.5 USDC
    // LQ After fee = 0.496
    // hlp liquidity (wbtc) 0.9970000, usdc(19840.0000000) => (wbtc) 0.9970000, usdc(19840.4960000)
    // fee = 0.004000000 (usdc)
    // feetotal 0.003000000 (wbtc) + 160 (usdc) => 0.003000000 (wbtc) + 160.004 (usdc)
    // BOB received HLP amount = 0.496
    // hlpTotalSupply = 39780 => 39780.496

    vm.deal(BOB, executionOrderFee);
    uint256 _bobBTCAmount = 0.5 * 1e8;
    wbtc.mint(BOB, _bobBTCAmount);
    addLiquidity(
      BOB,
      ERC20(address(wbtc)),
      _bobBTCAmount,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 4, "liquidityOrder size After Created");
      assertEq(liquidityOrders[3].orderId, 3, "OrderId After Created");
    }

    // BOB ADD 0.5 BTC
    // LQ After fee => 0.4996500
    // hlp liquidity (wbtc) 0.9970000, usdc(19840.4960000) => (wbtc) 1.49665, usdc(19840.4960000)
    // fee => 0.000350000 (wbtc)
    // feetotal => 0.003000000 (wbtc) + 160.004 (usdc) => 0.00335 (wbtc) + 160.004 (usdc)
    // BOB received HLP amount =>  9,993.0000000
    // hlpTotalSupply = 39780.496 => 49_773.496
    uint256 _lastOrderIndex = liquidityHandler.getLiquidityOrders().length - 1;
    executeHLPOrder(_lastOrderIndex, tickPrices, publishTimeDiff, block.timestamp);

    assertEq(calculator.getAUME30(false) / hlpV2.totalSupply() / 1e12, 1, "AUM");
    assertHLPTotalSupply(49_773.496 * 1e18);

    // assert HLP
    {
      // ALICE received HLP =>  19,940.00 +  19,840.00 => 39,780
      // BOB received HLP =>  0.496+ 9,993.0000000 => 9,993.496
      assertTokenBalanceOf(ALICE, address(hlpV2), 39_780 * 1e18);
      assertTokenBalanceOf(BOB, address(hlpV2), 9993.496 * 1e18);
    }

    //asert USDC
    {
      address _usdc = address(usdc);
      assertHLPLiquidity(_usdc, 19840.4960000 * 1e6);
      assertEq(vaultStorage.protocolFees(_usdc), (160.004 * 9000 * 1e6) / 1e4, "Vault's Fee USDC is not matched");
    }

    //assert BTC
    {
      address _wbtc = address(wbtc);
      assertHLPLiquidity(_wbtc, 1.49665 * 1e8);
      assertEq(vaultStorage.protocolFees(_wbtc), (0.00335 * 1e8 * 9000) / 1e4, "Vault's Fee WBTC is not matched");
    }

    // assert FEEVER
    uint256 nextExecutedIndex = liquidityHandler.nextExecutionOrderIndex();
    uint256 _executionFeeAddliquidity = ((executionOrderFee * nextExecutedIndex) - _pythGasFee);
    assertEq(FEEVER.balance, _executionFeeAddliquidity, "FEEVER fee");

    // END PART ADD LIQUIDITY

    // current state
    // hlp liquidity => (wbtc) 1.49665, usdc(19840.4960000)
    // ALICE HLP in hand => 39,780
    // BOB HLP in hand => 9,993.496
    vm.deal(ALICE, executionOrderFee);
    console.log("A", hlpV2.balanceOf(ALICE));
    console.log(hlpV2.totalSupply());
    removeLiquidity(
      ALICE,
      address(wbtc),
      29930.52420849 * 1e18,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    console.log("B", hlpV2.balanceOf(ALICE));
    console.log(hlpV2.totalSupply());
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 5, "liquidityOrder size After Created");
      assertEq(liquidityOrders[4].orderId, 4, "OrderId After Created");
    }
    // ALICE REMOVE 29_933 HLP (price = 20000)
    // hlpTotalSupply = 49_773.496 - 29_933(HLP) => 19840.496
    // TOKEN OUT AMOUNT BEFORE FEE => 1.49665 wbtc

    // hlp liquidity  1.49665 (wbtc),19840.4960000 (usdc) =>  0 (wbtc), 19840.4960000 (usdc)
    // fee => 0.009578560 (wbtc)
    // feetotal => 0.00335 (wbtc) + 160.004 (usdc) =>  0.01292856 (wbtc)  + 160.004 (usdc)
    // ALICE received WBTC amount => 1.49665 - 0.009578560 =>  1.48707144 (wbtc)

    vm.deal(ALICE, executionOrderFee);
    console.log("C", hlpV2.balanceOf(ALICE));
    console.log(hlpV2.totalSupply());

    IConfigStorage.HLPTokenConfig memory _config;
    _config.targetWeight = 0.95 * 1e18;
    _config.bufferLiquidity = 0;
    _config.maxWeightDiff = 1e18;
    _config.accepted = true;
    configStorage.setHlpTokenConfig(address(wbtc), _config);

    removeLiquidity(
      ALICE,
      address(usdc),
      hlpV2.balanceOf(ALICE),
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    console.log("D", hlpV2.balanceOf(ALICE));
    console.log(hlpV2.totalSupply());
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 6, "liquidityOrder size After Created");
      assertEq(liquidityOrders[5].orderId, 5, "OrderId After Created");
    }
    // ALICE REMOVE 9_847 HLP (price =1)
    // hlpTotalSupply = 19840.496 - 9_847(HLP) => 9,993.496
    // TOKEN OUT AMOUNT BEFORE FEE => 9,847 USDC

    // hlp liquidity 19840.4960000 (usdc) => 9,993.496 (usdc)
    // fee => 0
    // feetotal => 0.01292856 (wbtc)  + 160.004 (usdc)
    // ALICE received USDC amount 9_847

    vm.deal(BOB, executionOrderFee);
    console.log("E", hlpV2.balanceOf(BOB));
    console.log(hlpV2.totalSupply());
    removeLiquidity(
      BOB,
      address(usdc),
      hlpV2.balanceOf(BOB) - 1 ether,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );
    console.log("F", hlpV2.balanceOf(BOB));
    console.log(hlpV2.totalSupply());
    {
      ILiquidityHandler.LiquidityOrder[] memory liquidityOrders = liquidityHandler.getLiquidityOrders();
      assertEq(liquidityOrders.length, 7, "liquidityOrder size After Created");
      assertEq(liquidityOrders[6].orderId, 6, "OrderId After Created");
    }
    // BOB REMOVE 9_993.496 HLP (price =1)
    // hlpTotalSupply = 9,993.496- 9,993.496(HLP) = 0
    // TOKEN OUT AMOUNT BEFORE FEE => 9_993.496

    // hlp liquidity  9,993.496 (usdc) => 0 (usdc)
    // fee => 0 because it's 100% pool weight 5% => reduce make it better
    // feetotal => 0.01292856 (wbtc)  + 160.004 (usdc)
    // BOB received USDC amount => 9_993.496

    // SUMMARY
    // ALICE get 1.48707144 (wbtc) + 9_847 (usdc)
    // BOB get 9_993.496 (usdc)
    // feetotal => 0.01292856 (wbtc)  + 160.004 (usdc)

    _lastOrderIndex = liquidityHandler.getLiquidityOrders().length - 1;
    executeHLPOrder(_lastOrderIndex, tickPrices, publishTimeDiff, block.timestamp);
    console.log(hlpV2.totalSupply());

    nextExecutedIndex = liquidityHandler.nextExecutionOrderIndex();

    //execute 3 orders

    uint256 _executionFeeTotal = _executionFeeAddliquidity + (3 * executionOrderFee) - _pythGasFee;
    // END PART REMOVE LIQUIDITY

    assertHLPTotalSupply(1 ether);

    assertEq(calculator.getAUME30(false), 1.000001 * 1e30, "AUM");

    assertHLPLiquidity(address(wbtc), 0);
    assertHLPLiquidity(address(usdc), 1.000001 * 1e6);

    assertEq(nextExecutedIndex, 7, "nextExecutionOrder Index");
    assertTokenBalanceOf(address(liquidityHandler), address(wbtc), 0);
    assertTokenBalanceOf(address(liquidityHandler), address(usdc), 0);

    assertEq(FEEVER.balance, _executionFeeTotal, "FEEVER fee");

    //assert btc
    {
      address _wbtc = address(wbtc);
      // alice remove 29_933 hlp into wbtc
      assertTokenBalanceOf(ALICE, _wbtc, 1.48707144 * 1e8);
      //bob remove liquidity in usdc only
      assertTokenBalanceOf(BOB, _wbtc, 0);
      assertEq(vaultStorage.protocolFees(_wbtc), 0.01163571 * 1e8, "Vault's Fee WBTC is not matched"); // due to the precision, hence the value mismatched a bit, rounding to the exact val. from (0.01292856 * 1e8 * 9000) / 1e4 to 1163571
    }

    //assert usdc
    {
      address _usdc = address(usdc);
      assertTokenBalanceOf(ALICE, _usdc, 9_847 * 1e6);
      assertTokenBalanceOf(BOB, _usdc, 9_993.496 * 1e6);
      assertEq(vaultStorage.protocolFees(_usdc), (160.004 * 1e6 * 9000) / 1e4, "Vault's Fee USDC is not matched");
    }
  }
}
