// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { console } from "forge-std/console.sol";
import { MockHLPStaking } from "@hmx-test/mocks/MockHLPStaking.sol";

contract TC01 is BaseIntTest_WithActions {
  MockHLPStaking hlpStaking;

  function testCorrectness_TC01_AddAndRemoveLiquiditySuccess() external {
    hlpStaking = new MockHLPStaking(address(hlpV2));
    liquidityHandler.setHlpStaking(address(hlpStaking));

    // T0: Initialized state
    uint256 _totalExecutionOrderFee = executionOrderFee - initialPriceFeedDatas.length;
    // WBTC = 19998.34577790
    // ALICE NEED 10k in terms of WBTC = 10000 /19998.34577790 * 10**8  = 0.50004136
    uint256 _amount = 0.50004136 * 1e8;
    pyth.getPriceUnsafe(wbtcAssetId);

    // mint 0.5 btc and give 0.0001 gas
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, _amount);

    // Alice Create Order And Executor Execute Order

    // T1: As a Liquidity, Alice adds 10,000 USD(GLP)
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
        hlpAmount: 0 ether, //
        fee: 135_000, //fee = 0.5e8( 0.5e8 -0.3%) = 0.0015 * 1e8; dev fee 10%; (0.0015 * 1e8) - (0.0015 * 1e7)
        executionFee: _totalExecutionOrderFee
      })
    );

    assertApproxEqRel(hlpStaking.userTokenAmount(ALICE), 9_970 ether, MAX_DIFF);

    // no one in HLP pool, so aum must be = totalSupply
    assertApproxEqRel(
      calculator.getAUME30(false) / 1e12,
      hlpV2.totalSupply(),
      0.0001 ether,
      "AUM & total Supply mismatch"
    );

    // T2: Alice withdraws 100,000 USD with HLP
    vm.deal(ALICE, executionOrderFee);

    uint256 amountToRemove = 100_000 ether;
    vm.startPrank(ALICE);
    hlpV2.approve(address(liquidityHandler), amountToRemove);
    vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
    liquidityHandler.createRemoveLiquidityOrder{ value: executionOrderFee }(
      address(wbtc),
      amountToRemove,
      0,
      executionOrderFee,
      false
    );
    vm.stopPrank();

    vm.prank(ALICE);
    hlpStaking.withdraw(100 ether);
    // T3: Alice withdraws HLP 100 USD
    //  10000 -> 0.5 e8
    //   100 -> 0.005 e8 btc
    removeLiquidity(
      ALICE,
      address(wbtc),
      100 ether,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    _totalExecutionOrderFee += (executionOrderFee - initialPriceFeedDatas.length);

    liquidityTester.assertLiquidityInfo(
      LiquidityTester.LiquidityExpectedData({
        token: address(wbtc),
        who: ALICE,
        lpTotalSupply: 9_870 ether, // 9970 hlp - 100 hlp
        totalAmount: 49_501_400, //(0.5 e8 - 0.005)+ 1400 fee
        hlpLiquidity: 49_350_000, // 49_850_000 - 500_000
        hlpAmount: 0 ether, // 9970 -100 (remove lq)
        //fee Alice addLiquidity (135_000) + fee Alice removeLiquidity(100 hlp => 500_000-(500_000-0.28%) => 1,400 ) = 151400 * 90 / 100 = 136260
        fee: 136260,
        executionFee: _totalExecutionOrderFee
      })
    );
    assertApproxEqRel(hlpStaking.userTokenAmount(ALICE), 9_870 ether, MAX_DIFF); // 9970 -100 (remove lq)

    // T5: As a Liquidity, Bob adds 100 USD(GLP) // 100/ 20000 => 0.005
    vm.deal(BOB, executionOrderFee);
    wbtc.mint(BOB, 500_000);

    vm.startPrank(BOB);
    wbtc.approve(address(liquidityHandler), 500_000);

    // add Liquidity
    liquidityHandler.createAddLiquidityOrder{ value: executionOrderFee }(
      address(wbtc),
      500_000,
      0,
      executionOrderFee,
      false
    );
    vm.stopPrank();

    _totalExecutionOrderFee += (executionOrderFee - initialPriceFeedDatas.length);

    ILiquidityHandler.LiquidityOrder[] memory orders = liquidityHandler.getLiquidityOrders();

    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    vm.prank(ORDER_EXECUTOR);
    liquidityHandler.executeOrder(
      orders.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );
    liquidityTester.assertLiquidityInfo(
      LiquidityTester.LiquidityExpectedData({
        token: address(wbtc),
        who: BOB,
        lpTotalSupply: 9_969.68 ether,
        totalAmount: 50001400, //49_501_400 + 500_000
        hlpLiquidity: 49_848_400, //49_350_000
        hlpAmount: 0,
        fee: 137_700, // oldFee => 151_400 + (500_000 *0.32%) => 151_400+1600 => 153000 * 90 / 100 = 137700
        executionFee: _totalExecutionOrderFee
      })
    );

    assertApproxEqRel(hlpStaking.userTokenAmount(BOB), 99.68 ether, MAX_DIFF);

    // T6: Alice max withdraws 9,870 USD HLP in pools
    vm.prank(ALICE);
    hlpStaking.withdraw(9_870 ether);

    vm.deal(ALICE, executionOrderFee);
    _totalExecutionOrderFee += (executionOrderFee - initialPriceFeedDatas.length);

    removeLiquidity(
      ALICE,
      address(wbtc),
      9_870 ether,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    // State has not changed due to pool imbalance error
    liquidityTester.assertLiquidityInfo(
      LiquidityTester.LiquidityExpectedData({
        token: address(wbtc),
        who: BOB,
        lpTotalSupply: 9_969.68 ether,
        totalAmount: 50001400, //49_501_400 + 500_000
        hlpLiquidity: 49_848_400, //49_350_000
        hlpAmount: 0 ether,
        fee: 137_700, // oldFee => 151_400 + (500_000 *0.32%) => 151_400+1600 => 153000 * 90 / 100 => 137700
        executionFee: _totalExecutionOrderFee
      })
    );
    assertApproxEqRel(hlpV2.balanceOf(ALICE), 9_870 ether, MAX_DIFF);
    assertApproxEqRel(hlpStaking.userTokenAmount(BOB), 99.68 ether, MAX_DIFF);

    // T7: Alice max withdraws 9,870 USD HLP in pools
    vm.deal(ALICE, executionOrderFee);
    _totalExecutionOrderFee += (executionOrderFee - initialPriceFeedDatas.length);

    IConfigStorage.HLPTokenConfig memory _config;
    _config.targetWeight = 0.95 * 1e18;
    _config.bufferLiquidity = 0;
    _config.maxWeightDiff = 1e18;
    _config.accepted = true;
    configStorage.setHlpTokenConfig(address(wbtc), _config);

    removeLiquidity(
      ALICE,
      address(wbtc),
      9_870 ether,
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
        lpTotalSupply: 99.68 ether, //only BOB LP LEFT
        totalAmount: 927_760,
        hlpLiquidity: 498_400,
        hlpAmount: 0, // ALICE HLP AMOUNT SHOULD BE 0
        fee: 386_424, //(153_000 + 276_36)0 * 90 / 100
        executionFee: _totalExecutionOrderFee
      })
    );
  }
}
