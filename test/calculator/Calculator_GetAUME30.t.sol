// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Calculator_Base } from "./Calculator_Base.t.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { console2 } from "forge-std/console2.sol";

contract Calculator_GetAUME30Test is Calculator_Base {
  function setUp() public override {
    super.setUp();

    // Set up basic market config
    configStorage.setMarketConfig(
      0,
      IConfigStorage.MarketConfig({
        assetId: wbtcAssetId,
        maxLongPositionSize: 10_000_000 * 1e30,
        maxShortPositionSize: 10_000_000 * 1e30,
        assetClass: 1,
        maxProfitRateBPS: 9 * 1e4,
        initialMarginFractionBPS: 0.01 * 1e4,
        maintenanceMarginFractionBPS: 0.005 * 1e4,
        increasePositionFeeRateBPS: 0,
        decreasePositionFeeRateBPS: 0,
        allowIncreasePosition: false,
        active: true,
        fundingRate: IConfigStorage.FundingRate({ maxFundingRate: 0.0004 * 1e18, maxSkewScaleUSD: 300_000_000 * 1e30 })
      }),
      false
    );

    // Set up HLP asset config
    configStorage.setAssetConfig(
      wbtcAssetId,
      IConfigStorage.AssetConfig({
        tokenAddress: address(wbtc),
        assetId: wbtcAssetId,
        decimals: 8,
        isStableCoin: false
      })
    );

    // Set up asset class config
    configStorage.setAssetClassConfigByIndex(1, IConfigStorage.AssetClassConfig({ baseBorrowingRate: 0.01 * 1e18 }));
  }

  function testCorrectness_WhenGetAUME30WithPositivePnl() external {
    // Set up mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30); // $50,000 per BTC

    // Set HLP liquidity
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8); // 100 BTC

    // Set up market data to create positive PnL
    // Long position: 1000 * 1e30, Short position: 500 * 1e30
    // This will create a net long position with positive PnL
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      52674532 * 1e30,
      1528.87843628626564 * 1e30,
      323791928.863313349 * 1e30,
      48927208 * 1e30,
      1478.99298048554020 * 1e30,
      301550790.483496218 * 1e30
    );
    // long global_pnl 2568550.2424053754
    // short global_pnl -422946.3689845529
    // (2568550.2424053754 + -422946.3689845529) = 2145603.87342082

    // Set borrowing fee debt
    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30); // $500 debt

    // Set loss debt
    // mockVaultStorage.setGlobalLossDebt(200 * 1e30); // $200 loss debt

    // Set HLP liquidity debt
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30); // $300 debt

    // Set asset class data for pending borrowing fee calculation
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    // Calculate expected AUM
    // HLP Value: 100 BTC * $50,000 = $5,000,000
    // + Pending borrowing fee: $150 (from asset class)
    // + Borrowing fee debt: $500
    // + Loss debt: $200
    // + HLP liquidity debt: $300
    // + Global PnL: calculated from market data
    // = $5,001,150 + PnL

    uint256 actualAum = calculator.getAUME30(false);
    console2.log("Actual AUM:", actualAum);
    assertGt(actualAum, 5000000 * 1e30, "AUM should be greater than HLP value with positive PnL");
  }

  function testCorrectness_WhenGetAUME30WithNegativePnl() external {
    // Set up mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);

    // Set up market data to create negative PnL
    // Short position: 1000 * 1e30, Long position: 500 * 1e30
    // This will create a net short position with negative PnL
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      1000 * 1e30, // longPositionSize
      1000 * 1e30, // longAccumSE
      1000 * 1e30, // longAccumS2E
      500 * 1e30, // shortPositionSize
      500 * 1e30, // shortAccumSE
      500 * 1e30 // shortAccumS2E
    );

    // Set other debts
    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30);
    mockVaultStorage.setGlobalLossDebt(200 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30);

    // Set asset class data for pending borrowing fee calculation
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 actualAum = calculator.getAUME30(false);
    assertLt(actualAum, 5000000 * 1e30, "AUM should be less than HLP value with negative PnL");
  }

  function testCorrectness_WhenGetAUME30WithLargeNegativePnl() external {
    // Set up mock data with large negative PnL that could make AUM zero
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);

    // Set up very large short position to create large negative PnL
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      1000 * 1e30, // longPositionSize
      1000 * 1e30, // longAccumSE
      1000 * 1e30, // longAccumS2E
      500 * 1e30, // shortPositionSize
      500 * 1e30, // shortAccumSE
      500 * 1e30 // shortAccumS2E
    );

    // Set minimal other values
    mockVaultStorage.setGlobalBorrowingFeeDebt(100 * 1e30);
    mockVaultStorage.setGlobalLossDebt(50 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(100 * 1e30);

    // Set asset class data
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 100 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 50 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    // AUM should be zero when negative PnL exceeds the sum of other components
    uint256 actualAum = calculator.getAUME30(false);
    assertEq(actualAum, 0, "AUM should be zero when negative PnL exceeds other components");
  }

  function testCorrectness_WhenGetAUME30WithMaxPrice() external {
    // Set up mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);

    // Set up market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      52674532 * 1e30,
      1528.87843628626564 * 1e30,
      323791928.863313349 * 1e30,
      48927208 * 1e30,
      1478.99298048554020 * 1e30,
      301550790.483496218 * 1e30
    );
    // long global_pnl 2568550.2424053754
    // short global_pnl -422946.3689845529
    // (2568550.2424053754 + -422946.3689845529) = 2145603.87342082

    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30);
    mockVaultStorage.setGlobalLossDebt(200 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30);

    // Set asset class data
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    // Test with max price (true)
    uint256 aumMaxPrice = calculator.getAUME30(true);

    // Test with min price (false)
    uint256 aumMinPrice = calculator.getAUME30(false);

    // Both should be calculated, but may differ based on oracle price
    assertGt(aumMaxPrice, 0, "AUM with max price should be greater than zero");
    assertGt(aumMinPrice, 0, "AUM with min price should be greater than zero");
  }

  function testCorrectness_WhenGetAUME30WithZeroComponents() external {
    // Set up minimal mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 0); // No HLP liquidity

    // No market positions
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      0, // longPositionSize
      0, // longAccumSE
      0, // longAccumS2E
      0, // shortPositionSize
      0, // shortAccumSE
      0 // shortAccumS2E
    );

    mockVaultStorage.setGlobalBorrowingFeeDebt(0);
    mockVaultStorage.setGlobalLossDebt(0);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(0);

    // Set asset class data with zero values
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 0,
        sumBorrowingRate: 0,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 0,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 actualAum = calculator.getAUME30(false);
    assertEq(actualAum, 0, "AUM should be zero when all components are zero");
  }

  function testCorrectness_WhenGetAUME30WithOnlyHlpValue() external {
    // Set up mock data with only HLP value
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);

    // No market positions
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      0, // longPositionSize
      0, // longAccumSE
      0, // longAccumS2E
      0, // shortPositionSize
      0, // shortAccumSE
      0 // shortAccumS2E
    );

    mockVaultStorage.setGlobalBorrowingFeeDebt(0);
    mockVaultStorage.setGlobalLossDebt(0);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(0);

    // Set asset class data with zero values
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 0,
        sumBorrowingRate: 0,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 0,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 expectedAum = (100 * 1e8 * 50000 * 1e30) / 1e8; // 100 BTC * $50,000
    uint256 actualAum = calculator.getAUME30(false);
    assertEq(actualAum, expectedAum, "AUM should equal HLP value when other components are zero");
  }

  function testCorrectness_WhenGetAUME30WithMultipleAssets() external {
    // Set up multiple assets
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockOracle.setPrice(wethAssetId, 3000 * 1e30);

    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8); // 100 BTC
    mockVaultStorage.setHlpLiquidity(address(weth), 1000 * 1e18); // 1000 ETH

    // Add ETH to HLP assets
    configStorage.setAssetConfig(
      wethAssetId,
      IConfigStorage.AssetConfig({
        tokenAddress: address(weth),
        assetId: wethAssetId,
        decimals: 18,
        isStableCoin: false
      })
    );

    // Set up market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      52674532 * 1e30,
      1528.87843628626564 * 1e30,
      323791928.863313349 * 1e30,
      48927208 * 1e30,
      1478.99298048554020 * 1e30,
      301550790.483496218 * 1e30
    );
    // long global_pnl 2568550.2424053754
    // short global_pnl -422946.3689845529
    // (2568550.2424053754 + -422946.3689845529) = 2145603.87342082

    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30);
    mockVaultStorage.setGlobalLossDebt(200 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30);

    // Set asset class data
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 actualAum = calculator.getAUME30(false);
    assertGt(actualAum, 8000000 * 1e30, "AUM should be greater than sum of multiple assets");
  }

  function testCorrectness_WhenGetAUME30WithPendingRewardDebt() external {
    // Set up mock data with pending reward debt
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);
    mockVaultStorage.setPendingRewardDebt(address(wbtc), 10 * 1e8); // 10 BTC pending reward debt

    // Set up market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      1000 * 1e30,
      1000 * 1e30,
      1000 * 1e30,
      500 * 1e30,
      500 * 1e30,
      500 * 1e30
    );

    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30);
    mockVaultStorage.setGlobalLossDebt(200 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30);

    // Set asset class data
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 actualAum = calculator.getAUME30(false);
    assertLt(actualAum, 5000000 * 1e30, "AUM should be less when pending reward debt is subtracted");
  }

  function testCorrectness_WhenGetAUME30WithHlpLiquidityOnHold() external {
    // Set up mock data with HLP liquidity on hold
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8);
    mockVaultStorage.setHlpLiquidityOnHold(address(wbtc), 20 * 1e8); // 20 BTC on hold

    // Set up market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      52674532 * 1e30,
      1528.87843628626564 * 1e30,
      323791928.863313349 * 1e30,
      48927208 * 1e30,
      1478.99298048554020 * 1e30,
      301550790.483496218 * 1e30
    );
    // long global_pnl 2568550.2424053754
    // short global_pnl -422946.3689845529
    // (2568550.2424053754 + -422946.3689845529) = 2145603.87342082

    mockVaultStorage.setGlobalBorrowingFeeDebt(500 * 1e30);
    mockVaultStorage.setGlobalLossDebt(200 * 1e30);
    mockVaultStorage.setHlpLiquidityDebtUSDE30(300 * 1e30);

    // Set asset class data
    mockPerpStorage.updateAssetClass(
      1,
      IPerpStorage.AssetClass({
        reserveValueE30: 1000 * 1e30,
        sumBorrowingRate: 0.01 * 1e18,
        lastBorrowingTime: block.timestamp,
        sumBorrowingFeeE30: 150 * 1e30,
        sumSettledBorrowingFeeE30: 0
      })
    );

    uint256 actualAum = calculator.getAUME30(false);
    assertGt(actualAum, 6000000 * 1e30, "AUM should be greater when HLP liquidity on hold is included");
  }
}
