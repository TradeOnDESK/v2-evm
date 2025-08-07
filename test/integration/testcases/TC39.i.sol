// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";

contract TC39 is BaseIntTest_WithActions {
  function testCorrectness_TC39_AutoCancelMarketOrder() external {
    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    _marketConfig.maxLongPositionSize = 20_000_000 * 1e30;
    _marketConfig.maxShortPositionSize = 20_000_000 * 1e30;
    configStorage.setMarketConfig(wbtcMarketIndex, _marketConfig, false);

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

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC39: before deposit collateral");
    }
    usdc.mint(BOB, 100_000 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    {
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC39: after deposit collateral");
    }

    // Long ETH
    vm.deal(BOB, 1 ether);
    // marketBuy(BOB, 0, wethMarketIndex, 100_000 * 1e30, address(usdc), tickPrices, publishTimeDiff, block.timestamp);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    vm.prank(BOB);
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      100_000 * 1e30,
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(usdc)
    );

    {
      // after create order, must contain 1 order
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 1);
      assertEq(BOB.balance, 1 ether - executionOrderFee);
    }

    // T3: Test Order stale

    // warp to exceed minExecutionTimestamp and make order stale
    skip(1000);

    uint256 _orderIndex = limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)) - 1;
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(publishTimeDiff);

    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = BOB;
    subAccountIds[0] = 0;
    orderIndexes[0] = _orderIndex;

    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    {
      // after execute market order and fail then refund execution fee
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 1);
      assertEq(BOB.balance, 1 ether);
    }

    // T4: Test Order execution fail

    vm.prank(BOB);
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      100_000_000_000 * 1e30,
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(usdc)
    );

    {
      // after create order, must contain 1 order
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 2);
      assertEq(BOB.balance, 1 ether - executionOrderFee);
    }

    skip(5);

    _orderIndex = limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)) - 1;

    accounts[0] = BOB;
    subAccountIds[0] = 0;
    orderIndexes[0] = _orderIndex;

    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    {
      // after execute market order and fail then no refund execution fee
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 2);
      assertEq(BOB.balance, 1 ether - executionOrderFee);

      // last position must be deleted
      uint256 orderIndex = limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0));
      (address account, , , , , , , , , , , ) = limitTradeHandler.limitOrders(getSubAccount(BOB, 0), orderIndex);
      assertEq(account, address(0));
    }
  }
}
