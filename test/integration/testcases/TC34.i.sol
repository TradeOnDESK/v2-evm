// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract TC34 is BaseIntTest_WithActions {
  function test_correctness_swingPriceViaExecution() external {
    // T0: Initialized state
    uint256 _totalExecutionOrderFee = executionOrderFee - initialPriceFeedDatas.length;

    uint256 _amount = 5e7; //0.5 btc

    // mint 0.5 btc and give 0.0001 gas
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, _amount);

    // Alice Create Order And Executor Execute Order
    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      _amount,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    liquidityTester.assertLiquidityInfo(
      LiquidityTester.LiquidityExpectedData({
        token: address(wbtc),
        who: ALICE,
        lpTotalSupply: 99_70 ether,
        totalAmount: _amount,
        hlpLiquidity: 49_850_000,
        hlpAmount: 9_970 ether, //
        fee: (150_000 * 9000) / 1e4, //fee = 0.5e8( 0.5e8 -0.3%) = 0.0015 * 1e8 // 10% to dev
        executionFee: _totalExecutionOrderFee
      })
    );

    vm.deal(ALICE, executionOrderFee);
    uint256 _balanceAll = hlpV2.balanceOf(ALICE);

    IConfigStorage.HLPTokenConfig memory _config;
    _config.targetWeight = 0.95 * 1e18;
    _config.bufferLiquidity = 0;
    _config.maxWeightDiff = 1e18;
    _config.accepted = true;
    configStorage.setHlpTokenConfig(address(wbtc), _config);

    removeLiquidity(
      ALICE,
      address(wbtc),
      _balanceAll - 1 ether,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      false
    );

    // setup for remove liquidity feed only 1 token
    skip(10);
    // bytes32[] memory _newAssetIds = new bytes32[](1);
    // int64[] memory _prices = new int64[](1);
    // uint64[] memory _conf = new uint64[](1);
    // _newAssetIds[0] = wbtcAssetId;
    // _prices[0] = 21_000 * 1e8;
    // _conf[0] = 2;

    tickPrices[1] = 99527; // WBTC tick price $21,000

    executeHLPOrder(liquidityHandler.nextExecutionOrderIndex(), tickPrices, publishTimeDiff, block.timestamp);

    _totalExecutionOrderFee += (executionOrderFee - 1);
    liquidityTester.assertLiquidityInfo(
      LiquidityTester.LiquidityExpectedData({
        token: address(wbtc),
        who: ALICE,
        lpTotalSupply: 1 ether,
        totalAmount: 434132,
        hlpLiquidity: 5001,
        hlpAmount: 1 ether,
        fee: (429130 * 9000) / 1e4,
        executionFee: _totalExecutionOrderFee
      })
    );
  }
}
