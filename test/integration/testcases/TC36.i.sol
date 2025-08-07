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
import { console } from "forge-std/console.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract TC36 is BaseIntTest_WithActions {
  function testCorrectness_TC36_MaxUtilization() external {
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

    // Retrieve the global state

    //  Calculation for Deposit Collateral and Open Position
    //  total usd debt => (99.7*20_000) + 100_000 => 2093835.07405663
    //  max utilization = 80% = 2093835.07405663 *0.8 = 1675068.0592453

    // - reserveValue = imr * maxProfit/BPS
    // - imr = reserveValue /maxProfit * BPS
    // - imr = 1675068.0592453 / 90000 * 10000 =>  1675068.0592453 /9 => 186118.67324948
    // - open position Size = imr * IMF / BPS
    // - open position Size = imr * 100 => 186118.67324948 * 100 => 18611867.324948 => 18_611_867.324948
    // - deposit collateral = sizeDelta + (sizeDelta * tradingFeeBPS / BPS)
    // - deposit collateral = 18_613_333 + (18_613_333 * 10/10000)
    // - deposit collateral = 18631946.333

    usdc.mint(BOB, 18_631_946.333 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 18_631_946.333 * 1e6);

    uint256 _pythGasFee = initialPriceFeedDatas.length;
    vm.deal(BOB, _pythGasFee);
    vm.deal(BOB, 1 ether);
    console.log("tvl", calculator.getHLPValueE30(true));
    marketBuy(BOB, 0, wbtcMarketIndex, 18_611_867 * 1e30, address(wbtc), tickPrices, publishTimeDiff, block.timestamp);

    {
      IPerpStorage.GlobalState memory _globalState = perpStorage.getGlobalState();
      IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_marketConfig.assetClass);
      IConfigStorage.LiquidityConfig memory _liquidityConfig = configStorage.getLiquidityConfig();
      // from above input reserve have to nearly with 80% of utilization
      // imr = positionSize * IMF_BPS / BPS
      // imr => 18_613_333 *1e30 / 100 => 186133330000000000000000000000000000
      // reserveValue = 186133330000000000000000000000000000 *9 =>  1675199970000000000000000000000000000

      // MaxUtilization from above 1_675_200 *1e30 => 1675200000000000000000000000000000000

      uint256 _hlpTVL = calculator.getHLPValueE30(false);
      uint256 _maxUtilizationValue = (_hlpTVL * _liquidityConfig.maxHLPUtilizationBPS) / 10000;

      assertApproxEqRel(
        _globalState.reserveValueE30,
        1675199970000000000000000000000000000,
        MAX_DIFF,
        "Global Reserve"
      );
      assertApproxEqRel(
        _assetClass.reserveValueE30,
        1675199970000000000000000000000000000,
        MAX_DIFF,
        "AssetClass's Reserve"
      );
      assertApproxEqRel(_hlpTVL, 2094000000000000000000000000000000000, MAX_DIFF, "HLP TVL");
      assertApproxEqRel(_maxUtilizationValue, 1675200000000000000000000000000000000, MAX_DIFF, "MaxUtilizationValue");
    }

    vm.deal(ALICE, executionOrderFee);
    uint256 _hlpAliceBefore = hlpV2.balanceOf(ALICE);

    // Alice try to remove liquidity, but refund due to reach max utilization
    removeLiquidity(
      ALICE,
      address(wbtc),
      1 * 1e18,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    uint256 _hlpAliceAfter = hlpV2.balanceOf(ALICE);

    {
      // HLP before and HLP after executed remove liquidity should be the same because platform refund due to reach max utilization
      assertEq(_hlpAliceBefore, _hlpAliceAfter, "Alice HLP should get refund");
      // HLP => 1_994_000.00(WBTC) + 100_000 (USDC)
      assertHLPTotalSupply(2_094_000 * 1e18);
      // assert HLP
      assertTokenBalanceOf(ALICE, address(hlpV2), 2_094_000 * 1e18);
      assertHLPLiquidity(address(wbtc), 99.7 * 1e8);
      assertHLPLiquidity(address(usdc), 100_000 * 1e6);
    }

    // Alice able to add 1000 USDC liquidity to help reserve % better
    vm.deal(ALICE, executionOrderFee);
    usdc.mint(ALICE, 1_000 * 1e6);
    addLiquidity(
      ALICE,
      ERC20(address(usdc)),
      1_000 * 1e6,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    {
      // wbtc 99.7 * 1e30 * 20000 => 1994000000000000000000000000000000000
      // usdc 100_997.2  * 1e30 * 1 => 100997200000000000000000000000000000
      // hlpValueE30 = 2094997200000000000000000000000000000

      // PNL = -6012221
      // WBTC   LONG         20000000000000000000000000000000000              20620444433333333333333333333320000              18613333000000000000000000000000000000             =560052858364255462951685200733910932

      // AUM = hlpValueE30 -PNL + Pending Borrowing Fee;
      // AUM = 2094997200000000000000000000000000000 - (-6012221) + 0
      // AUM = 2655050058364255462951685200733910932

      assertApproxEqRel(calculator.getHLPValueE30(false), 2094997200000000000000000000000000000, MAX_DIFF, "hlp TVL");

      assertApproxEqRel(calculator.getPendingBorrowingFeeE30(), 0, MAX_DIFF, "pending Borrowing Fee");

      assertApproxEqRel(calculator.getAUME30(false), 2094332274215590197526000000006012221, MAX_DIFF, "AUM");

      assertHLPTotalSupply(2094786772875837506655217);

      assertTokenBalanceOf(ALICE, address(hlpV2), 2094786772875837506655217);
      assertHLPLiquidity(address(wbtc), 99.7 * 1e8);
      assertHLPLiquidity(address(usdc), 100_997.2 * 1e6);
    }

    vm.deal(ALICE, executionOrderFee);
    removeLiquidity(
      ALICE,
      address(wbtc),
      500 * 1e18,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );
    {
      //fee => 0.3%, liquidityRemove = 3_168_639
      // wbtc 99.66831361 * 1e30 * 20000 => 1993366272200000000000000000000000000
      // usdc 100_997.2  * 1e30 * 1 => 100997200000000000000000000000000000
      // hlpValueE30 = 2094363472200000000000000000000000000

      // PNL = -6012221
      // WBTC   LONG         20000000000000000000000000000000000              20620444433333333333333333333320000              18613333000000000000000000000000000000             =560052858364255462951685200733910932

      //  AUM =  2094363472200000000000000000000000000 - ( -6012221) + 0

      assertApproxEqRel(calculator.getHLPValueE30(false), 2094363472200000000000000000000000000, MAX_DIFF, "hlp TVL");

      assertApproxEqRel(calculator.getPendingBorrowingFeeE30(), 0, MAX_DIFF, "pending Borrowing Fee");

      assertApproxEqRel(calculator.getAUME30(false), 2094332274215590197526000000006012221, MAX_DIFF, "AUM");

      assertHLPTotalSupply(2094286772875837506655217);
      // assert HLP
      assertTokenBalanceOf(ALICE, address(hlpV2), 2094286772875837506655217);
      assertHLPLiquidity(address(wbtc), 99.66831361 * 1e8);
      assertHLPLiquidity(address(usdc), 100_997.2 * 1e6);
    }

    //BOB close all position
    {
      _pythGasFee = initialPriceFeedDatas.length;
      vm.deal(BOB, _pythGasFee);
      vm.deal(BOB, executionOrderFee);
      marketSell(
        BOB,
        0,
        wbtcMarketIndex,
        18_611_867 * 1e30,
        address(wbtc),
        tickPrices,
        publishTimeDiff,
        block.timestamp
      );
    }

    {
      //from above state
      //hlpValueE30 = 2654416330564255462951685200733910932
      //maxUtilization = 2654416330564255462951685200733910932 * 8000 / 10000 => 1675490777760000000000000000000000000
      IPerpStorage.GlobalState memory _globalState = perpStorage.getGlobalState();
      _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);
      IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_marketConfig.assetClass);
      IConfigStorage.LiquidityConfig memory _liquidityConfig = configStorage.getLiquidityConfig();
      uint256 _hlpTVL = calculator.getHLPValueE30(false);

      uint256 _maxUtilizationValue = (_hlpTVL * _liquidityConfig.maxHLPUtilizationBPS) / 10000;

      assertApproxEqRel(_globalState.reserveValueE30, 0, MAX_DIFF, "Global Reserve");
      assertApproxEqRel(_assetClass.reserveValueE30, 0, MAX_DIFF, "Global AssetClass Reserve");
      assertApproxEqRel(_hlpTVL, 2094363472200000000000000000000000000, MAX_DIFF, "HLP TVL");
      assertApproxEqRel(_maxUtilizationValue, 1675490777760000000000000000000000000, MAX_DIFF, "MaxUtilizationValue");
    }

    // Try to remove All liquidity in HLP should be success
    vm.deal(ALICE, executionOrderFee * 2);

    removeLiquidity(
      ALICE,
      address(usdc),
      100997199992639264702996,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true // execute now
    );

    IConfigStorage.HLPTokenConfig memory _config;
    _config.targetWeight = 0.95 * 1e18;
    _config.bufferLiquidity = 0;
    _config.maxWeightDiff = 1e18;
    _config.accepted = true;
    configStorage.setHlpTokenConfig(address(wbtc), _config);

    removeLiquidity(
      ALICE,
      address(wbtc),
      hlpV2.balanceOf(ALICE) - 1 ether,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true // execute now
    );

    {
      assertApproxEqRel(calculator.getHLPValueE30(false), 1e30, MAX_DIFF, "hlp TVL");

      assertApproxEqRel(calculator.getPendingBorrowingFeeE30(), 0, MAX_DIFF, "pending Borrowing Fee");

      assertApproxEqRel(calculator.getAUME30(false), 1e30, MAX_DIFF, "AUM");

      assertHLPTotalSupply(1 ether);

      assertTokenBalanceOf(ALICE, address(hlpV2), 1 ether);
      assertHLPLiquidity(address(wbtc), 0.00005001 * 1e8);
      assertHLPLiquidity(address(usdc), 0);
    }
  }
}
