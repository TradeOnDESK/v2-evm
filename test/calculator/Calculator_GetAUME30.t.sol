// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Calculator_Base } from "./Calculator_Base.t.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { console2 } from "forge-std/console2.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";

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

  // =========================================
  // | --- Feed Reward Debt AUM Tests ----- |
  // =========================================

  function testCorrectness_WhenGetAUME30WithFeedRewardBeforeTimePassed() external {
    // Deploy a real VaultStorage for this test
    IVaultStorage realVaultStorage = Deployer.deployVaultStorage(address(proxyAdmin));

    // Deploy a new Calculator using the real VaultStorage
    ICalculator realCalculator = Deployer.deployCalculator(
      address(proxyAdmin),
      address(mockOracle),
      address(realVaultStorage),
      address(mockPerpStorage),
      address(configStorage)
    );

    // Set up service executor permissions
    realVaultStorage.setServiceExecutors(address(this), true);

    // Set up basic mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);

    // Add initial HLP liquidity using the real VaultStorage
    wbtc.mint(address(realVaultStorage), 100 * 1e8); // Mint 100 BTC to VaultStorage
    realVaultStorage.addHLPLiquidity(address(wbtc), 100 * 1e8); // 100 BTC base liquidity
    realVaultStorage.pullToken(address(wbtc)); // Update totalAmount

    // Set up minimal market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      0, // longPositionSize
      0, // longAccumSE
      0, // longAccumS2E
      0, // shortPositionSize
      0, // shortAccumSE
      0 // shortAccumS2E
    );

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

    // Calculate expected AUM without reward debt
    uint256 expectedAumWithoutReward = (100 * 1e8 * 50000 * 1e30) / 1e8; // 100 BTC * $50,000
    uint256 actualAumWithoutReward = realCalculator.getAUME30(false);
    assertEq(actualAumWithoutReward, expectedAumWithoutReward, "AUM should equal HLP value when no reward debt");

    // Simulate feed reward: 10 BTC reward with 1 day duration
    uint256 feedAmount = 10 * 1e8; // 10 BTC
    uint256 duration = 86400; // 1 day

    // Mint and approve tokens for feeding
    wbtc.mint(address(this), feedAmount);
    wbtc.approve(address(realVaultStorage), feedAmount);

    // Perform the actual feed
    realVaultStorage.feed(address(wbtc), feedAmount, duration);

    // Check AUM immediately after feed (no time passed)
    uint256 actualAumWithReward = realCalculator.getAUME30(false);

    // AUM should be reduced because the full reward debt is still pending
    // Total assets = 110 BTC (HLP) + 0 BTC (on hold) - 10 BTC (pending reward) = 100 BTC
    uint256 expectedAumWithReward = (100 * 1e8 * 50000 * 1e30) / 1e8; // 100 BTC * $50,000
    assertEq(
      actualAumWithReward,
      expectedAumWithReward,
      "AUM should be reduced by full reward debt when no time has passed"
    );
  }

  function testCorrectness_WhenGetAUME30WithFeedRewardAfterTimePassed() external {
    // Set up basic mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8); // 100 BTC base liquidity

    // Set up minimal market data
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

    // Simulate feed reward: 10 BTC reward with 1 day duration
    uint256 feedAmount = 10 * 1e8; // 10 BTC
    uint256 duration = 86400; // 1 day
    uint256 startTime = block.timestamp;
    uint256 expiredAt = startTime + duration;

    // Set up reward debt state
    mockVaultStorage.setRewardDebt(address(wbtc), feedAmount);
    mockVaultStorage.setRewardDebtStartAt(address(wbtc), startTime);
    mockVaultStorage.setRewardDebtExpiredAt(address(wbtc), expiredAt);

    // Move time forward by half the duration
    vm.warp(block.timestamp + duration / 2);

    // Check AUM after half the time has passed
    uint256 actualAumWithReward = calculator.getAUME30(false);

    // After half the time, half the reward debt should be remaining
    // Total assets = 100 BTC (HLP) + 0 BTC (on hold) - 5 BTC (remaining reward) = 95 BTC
    uint256 expectedAumWithReward = (95 * 1e8 * 50000 * 1e30) / 1e8; // 95 BTC * $50,000
    assertEq(actualAumWithReward, expectedAumWithReward, "AUM should be increased as reward debt decreases over time");
  }

  function testCorrectness_WhenGetAUME30WithFeedRewardAfterExpiry() external {
    // Deploy a real VaultStorage for this test
    IVaultStorage realVaultStorage = Deployer.deployVaultStorage(address(proxyAdmin));

    // Deploy a new Calculator using the real VaultStorage
    ICalculator realCalculator = Deployer.deployCalculator(
      address(proxyAdmin),
      address(mockOracle),
      address(realVaultStorage),
      address(mockPerpStorage),
      address(configStorage)
    );

    // Set up service executor permissions
    realVaultStorage.setServiceExecutors(address(this), true);

    // Set up basic mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);

    // Add initial HLP liquidity using the real VaultStorage
    wbtc.mint(address(realVaultStorage), 100 * 1e8); // Mint 100 BTC to VaultStorage
    realVaultStorage.addHLPLiquidity(address(wbtc), 100 * 1e8); // 100 BTC base liquidity
    realVaultStorage.pullToken(address(wbtc)); // Update totalAmount

    // Set up minimal market data
    mockPerpStorage.updateGlobalCounterTradeStates(
      0,
      0, // longPositionSize
      0, // longAccumSE
      0, // longAccumS2E
      0, // shortPositionSize
      0, // shortAccumSE
      0 // shortAccumS2E
    );

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

    // Simulate feed reward: 10 BTC reward with 1 day duration
    uint256 feedAmount = 10 * 1e8; // 10 BTC
    uint256 duration = 86400; // 1 day

    // Mint and approve tokens for feeding
    wbtc.mint(address(this), feedAmount);
    wbtc.approve(address(realVaultStorage), feedAmount);

    // Perform the actual feed
    realVaultStorage.feed(address(wbtc), feedAmount, duration);

    // Move time forward beyond the expiry
    vm.warp(block.timestamp + duration + 1);

    // Check AUM after expiry
    uint256 actualAumWithReward = realCalculator.getAUME30(false);

    // After expiry, no reward debt should remain
    // Total assets = 110 BTC (HLP) + 0 BTC (on hold) - 0 BTC (no remaining reward) = 110 BTC
    uint256 expectedAumWithReward = (110 * 1e8 * 50000 * 1e30) / 1e8; // 110 BTC * $50,000
    assertEq(actualAumWithReward, expectedAumWithReward, "AUM should return to full value after reward debt expires");
  }

  function testCorrectness_WhenGetAUME30WithMultipleFeedRewards() external {
    // Set up basic mock data
    mockOracle.setPrice(wbtcAssetId, 50000 * 1e30);
    mockVaultStorage.setHlpLiquidity(address(wbtc), 100 * 1e8); // 100 BTC base liquidity

    // Set up minimal market data
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

    // Simulate multiple feed rewards
    uint256 feedAmount1 = 5 * 1e8; // 5 BTC
    uint256 feedAmount2 = 3 * 1e8; // 3 BTC
    uint256 duration1 = 86400; // 1 day
    uint256 duration2 = 43200; // 12 hours
    uint256 startTime = block.timestamp;
    uint256 expiredAt1 = startTime + duration1;
    uint256 expiredAt2 = startTime + duration2;

    // Set up first reward debt state
    mockVaultStorage.setRewardDebt(address(wbtc), feedAmount1);
    mockVaultStorage.setRewardDebtStartAt(address(wbtc), startTime);
    mockVaultStorage.setRewardDebtExpiredAt(address(wbtc), expiredAt1);

    // Check AUM with first reward
    uint256 actualAumWithFirstReward = calculator.getAUME30(false);
    uint256 expectedAumWithFirstReward = (95 * 1e8 * 50000 * 1e30) / 1e8; // 95 BTC * $50,000
    assertEq(actualAumWithFirstReward, expectedAumWithFirstReward, "AUM should be reduced by first reward debt");

    // Move time forward and add second reward
    vm.warp(block.timestamp + 3600); // 1 hour later
    mockVaultStorage.setRewardDebt(address(wbtc), feedAmount1 + feedAmount2); // Total reward debt
    mockVaultStorage.setRewardDebtExpiredAt(address(wbtc), expiredAt2); // Use second expiry

    // Check AUM with both rewards
    uint256 actualAumWithBothRewards = calculator.getAUME30(false);
    // Calculate expected reward debt after 1 hour: (8 BTC * (43200 - 3600) / 43200) = 7.33 BTC remaining
    uint256 remainingRewardDebt = ((feedAmount1 + feedAmount2) * (expiredAt2 - block.timestamp)) /
      (expiredAt2 - startTime);
    uint256 expectedAumWithBothRewards = ((100 * 1e8 - remainingRewardDebt) * 50000 * 1e30) / 1e8;
    assertEq(actualAumWithBothRewards, expectedAumWithBothRewards, "AUM should be reduced by calculated reward debt");

    // Move to after first expiry but before second
    vm.warp(block.timestamp + duration2 / 2);
    uint256 actualAumAfterFirstExpiry = calculator.getAUME30(false);
    assertGt(actualAumAfterFirstExpiry, expectedAumWithBothRewards, "AUM should increase as first reward expires");

    // Move to after both expiries
    vm.warp(block.timestamp + duration2);
    uint256 actualAumAfterBothExpiries = calculator.getAUME30(false);
    uint256 expectedAumAfterBothExpiries = (100 * 1e8 * 50000 * 1e30) / 1e8; // 100 BTC * $50,000
    assertEq(
      actualAumAfterBothExpiries,
      expectedAumAfterBothExpiries,
      "AUM should return to full value after all rewards expire"
    );
  }
}
