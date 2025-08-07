// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

/// Forge
import { console2 } from "forge-std/console2.sol";

/// HMX tests
import { RebalanceHLPv2Service_BaseForkTest } from "@hmx-test/fork/rebalance-gmx-v2/RebalanceHLPv2_Base.t.fork.sol";
import { MockEcoPyth } from "@hmx-test/mocks/MockEcoPyth.sol";

/// HMX
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IRebalanceHLPv2Service } from "@hmx/services/interfaces/IRebalanceHLPv2Service.sol";
import { IGmxV2Oracle } from "@hmx/interfaces/gmx-v2/IGmxV2Oracle.sol";

contract RebalanceHLPv2Service_DepositForkTest is RebalanceHLPv2Service_BaseForkTest {
  function setUp() public override {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"), 283542883);
    super.setUp();
  }

  function testRevert_WhenDeployMoreThanLiquidity() external {
    rebalanceHLPv2_createDepositOrder(GM_WBTCUSDC_ASSET_ID, 10 * 1e8, 0, 0, "IVaultStorage_HLPBalanceRemaining()");
  }

  function testCorrectness_RebalanceHLPv2Deposit_WhenNoOneJamInTheMiddle() external {
    // Override GM(WBTC-USDC) price
    MockEcoPyth(address(ecoPyth2)).overridePrice(GM_WBTCUSDC_ASSET_ID, 1.11967292 * 1e8);

    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);
    uint256 beforeTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    uint256 beforeWbtc = wbtc.balanceOf(address(vaultStorage));

    // Create deposit order on GMXv2
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(GM_WBTCUSDC_ASSET_ID, 0.01 * 1e8, 0, 0);

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);
    uint256 afterTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    uint256 afterWbtc = wbtc.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    // 3. 0.01 WBTC should be on-hold.
    // 4. pullToken should return zero.
    // 5. afterTotalWbtc should be the same as beforeTotalWbtc.
    // 6. beforeWbtc should be 0.01 more than afterWbtc.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");
    assertEq(0.01 * 1e8, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0.01 WBTC should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(wbtc)), "pullToken should return zero");
    assertEq(afterTotalWbtc, beforeTotalWbtc, "afterTotalWbtc should the same as before");
    assertEq(beforeWbtc - afterWbtc, 0.01 * 1e8, "wbtcBefore should be 0.01 more than wbtcAfter");

    beforeTvl = calculator.getHLPValueE30(false);
    beforeAum = calculator.getAUME30(false);
    uint256 beforeGmBtcTotal = vaultStorage.totalAmount(address(gmBTCUSD));
    uint256 beforeGmBtc = gmBTCUSD.balanceOf(address(vaultStorage));
    beforeTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    beforeWbtc = wbtc.balanceOf(address(vaultStorage));

    // Execute deposit order on GMXv2
    gmxV2Keeper_executeDepositOrder(GM_WBTCUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);
    uint256 afterGmBtcTotal = vaultStorage.totalAmount(address(gmBTCUSD));
    uint256 afterGmBtc = gmBTCUSD.balanceOf(address(vaultStorage));

    afterTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    afterWbtc = wbtc.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. totalWBtcAfter should decrease by 0.01 WBTC.
    // 4. wbtcBefore should remain the same.
    // 5. totalWbtcAfter should match wbtcBefore.
    // 6. gmBtcTotalAfter should more than gmBtcTotalBefore.
    // 7. gmBtcAfter should more than gmBtcBefore.
    // 8. gmBtcAfter should match with gmBtcTotalAfter.
    // 9. TVL should not change more than 0.01%
    // 10. AUM should not change more than 0.01%
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0 WBTC should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(wbtc)), "pullToken should return zero");
    assertEq(afterTotalWbtc, beforeTotalWbtc - 0.01 * 1e8, "totalWbtcAfter should decrease by 0.01 WBTC");
    assertEq(beforeWbtc, afterWbtc, "wbtcBefore should remains the same");
    assertEq(afterWbtc, afterTotalWbtc, "total[WBTC] should match wbtcAfter");
    assertTrue(afterGmBtcTotal > beforeGmBtcTotal, "gmBtcTotalAfter should more than gmBtcTotalBefore");
    assertTrue(afterGmBtc > beforeGmBtc, "gmBtcAfter should more than gmBtcBefore");
    assertEq(afterGmBtc, afterGmBtcTotal, "gmBtcAfter should match with gmBtcTotalAfter");
    assertApproxEqRel(beforeTvl, afterTvl, 0.0001 ether, "tvl must remains the same");
    assertApproxEqRel(beforeAum, afterAum, 0.0001 ether, "aum must remains the same");
  }

  function testCorrectness_WhenErr_WhenNoOneJamInTheMiddle() external {
    // Override GM(WBTC-USDC) price
    MockEcoPyth(address(ecoPyth2)).overridePrice(GM_WBTCUSDC_ASSET_ID, 1.11967292 * 1e8);

    uint256 wbtcInitialHlpLiquidity = vaultStorage.hlpLiquidity(address(wbtc));
    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);
    uint256 beforeTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    uint256 beforeWbtc = wbtc.balanceOf(address(vaultStorage));

    // Create deposit order on GMXv2
    // Assuming slippage hit.
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(
      GM_WBTCUSDC_ASSET_ID,
      0.01 * 1e8,
      0,
      307089148973164794124
    );

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);
    uint256 afterTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    uint256 afterWbtc = wbtc.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    // 3. 0.01 WBTC should be on-hold.
    // 4. pullToken should return zero.
    // 5. afterTotalWbtc should be the same as beforeTotalWbtc.
    // 6. beforeWbtc should be 0.01 more than afterWbtc.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");
    assertEq(0.01 * 1e8, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0.01 WBTC should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(wbtc)), "pullToken should return zero");
    assertEq(afterTotalWbtc, beforeTotalWbtc, "afterTotalWbtc should the same as before");
    assertEq(beforeWbtc - afterWbtc, 0.01 * 1e8, "wbtcBefore should be 0.01 more than wbtcAfter");

    beforeTvl = calculator.getHLPValueE30(false);
    beforeAum = calculator.getAUME30(false);
    beforeTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    beforeWbtc = wbtc.balanceOf(address(vaultStorage));

    // Execute here should callback to `afterDepositCancellation`
    gmxV2Keeper_executeDepositOrder(GM_WBTCUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);
    afterTotalWbtc = vaultStorage.totalAmount(address(wbtc));
    afterWbtc = wbtc.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. totalWbtc should remain the same.
    // 4. wbtcBefore should increase by 0.01 WBTC.
    // 5. afterTotalWbtc should match afterWbtc.
    // 6. TVL should remain unchanged.
    // 7. AUM should remain unchanged.
    // 8. HLP WBTC liquidity should match with initial HLP WBTC liquidity.
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0 WBTC should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(wbtc)), "pullToken should return zero");
    assertEq(afterTotalWbtc, beforeTotalWbtc, "totalWbtcAfter remain the same");
    assertEq(beforeWbtc + 0.01 * 1e8, afterWbtc, "wbtcBefore should increase by 0.01 WBTC");
    assertEq(afterWbtc, afterTotalWbtc, "total[WBTC] should match wbtcAfter");
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");
    assertEq(wbtcInitialHlpLiquidity, vaultStorage.hlpLiquidity(address(wbtc)), "hlpLiquidity must remains the same");
  }

  function testCorrectness_RebalanceHLPv2Deposit_WhenETH_WhenErr_WhenNoOneJamInTheMiddle() external {
    bytes32 gmxOrderKey = rebalanceHLPv2_createWithdrawalOrder(GM_ETHUSDC_ASSET_ID, 4000 ether, 0, 0); // get some ETH from GM-ETHUSDC
    gmxV2Keeper_executeWithdrawalOrder(GM_ETHUSDC_ASSET_ID, gmxOrderKey);

    uint256 wethInitialHlpLiquidity = vaultStorage.hlpLiquidity(address(weth));
    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);
    uint256 beforeTotalWeth = vaultStorage.totalAmount(address(weth));
    uint256 beforeWeth = weth.balanceOf(address(vaultStorage));

    // Create deposit order on GMXv2
    // Assuming slippage hit.
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(
      GM_ETHUSDC_ASSET_ID,
      1 ether,
      0,
      1818862156288003735002
    );

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);
    uint256 afterTotalWeth = vaultStorage.totalAmount(address(weth));
    uint256 afterWeth = weth.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    // 3. 1 ETH should be on-hold.
    // 4. pullToken should return zero.
    // 5. afterTotalWeth should be the same as beforeTotalWeth.
    // 6. beforeWeth should be 1 ether more than afterWeth.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");
    assertEq(1 ether, vaultStorage.hlpLiquidityOnHold(address(weth)), "1 ETH should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(weth)), "pullToken should return zero");
    assertEq(afterTotalWeth, beforeTotalWeth, "afterTotalWeth should the same as before");
    assertEq(beforeWeth - afterWeth, 1 ether, "wethBefore should be 1 more than wethAfter");

    beforeTvl = afterTvl;
    beforeAum = afterAum;
    beforeTotalWeth = vaultStorage.totalAmount(address(weth));
    beforeWeth = weth.balanceOf(address(vaultStorage));

    gmxV2Keeper_executeDepositOrder(GM_ETHUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);
    afterTotalWeth = vaultStorage.totalAmount(address(weth));
    afterWeth = weth.balanceOf(address(vaultStorage));

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. totalWeth should remain the same.
    // 4. afterWeth should increase by 1 WETH as it returns from GMXv2.
    // 5. afterTotalWeth should match afterWeth.
    // 6. TVL should remain unchanged.
    // 7. AUM should remain unchanged.
    // 8. HLP WETH liquidity should match with initial HLP WETH liquidity.
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(weth)), "0 WETH should be on-hold");
    assertEq(0, vaultStorage.pullToken(address(weth)), "pullToken should return zero");
    assertEq(afterTotalWeth, beforeTotalWeth, "totalWeth remain the same");
    assertEq(beforeWeth + 1 ether, afterWeth, "wethBefore should increase by 1 WETH");
    assertEq(afterWeth, afterTotalWeth, "total[WETH] should match afterWeth");
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");
    assertEq(wethInitialHlpLiquidity, vaultStorage.hlpLiquidity(address(weth)), "hlpLiquidity must remains the same");
  }

  function testCorrectness_RebalanceHLPv2Deposit_WhenSomeoneJamInTheMiddle_AddRemoveLiquidity() external {
    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);

    // Create deposit order on GMXv2
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(GM_WBTCUSDC_ASSET_ID, 0.01 * 1e8, 0, 0);

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");

    beforeTvl = afterTvl;
    beforeAum = afterAum;

    /// Assuming Alice try to deposit in the middle
    vm.deal(ALICE, 1 ether);
    motherload(address(usdc_e), ALICE, 10_000_000 * 1e6);
    addLiquidity(ALICE, usdc_e, 10_000_000 * 1e6, true);

    uint256 liquidityValue = ((10_000_000 * 1e22 * uint256(int256(ecoPyth2.getPriceUnsafe(bytes32("USDC")).price))) *
      9950) / 10000;

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. TVL should increase by ~10,000,000 USD
    // 2. AUM should increase by ~10,000,000 USD
    assertEq(beforeTvl + liquidityValue, afterTvl, "tvl should increase by ~10,000,000 USD");
    assertApproxEqRel(beforeAum + liquidityValue, afterAum, 0.0001 ether, "aum should increase by ~10,000,000 USD");

    beforeTvl = afterTvl;
    beforeAum = afterAum;

    /// Assuming Alice try to withdraw.
    uint256 hlpPrice = (beforeAum * 1e6) / hlp.totalSupply();
    uint256 estimateWithdrawValueE30 = (((5_000_000 ether * hlpPrice) / 1e6) * 9950) / 10000;
    unstakeHLP(ALICE, 5_000_000 ether);
    removeLiquidity(ALICE, usdc_e, 5_000_000 ether, true);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. TVL should decrease by ~5,000,000 USD
    // 2. AUM should decrease by ~5,000,000 USD
    assertApproxEqRel(
      beforeTvl - estimateWithdrawValueE30,
      afterTvl,
      0.003 ether,
      "tvl should decrease by ~5,000,000 USD"
    );
    assertApproxEqRel(
      beforeAum - estimateWithdrawValueE30,
      afterAum,
      0.003 ether,
      "aum should decrease by ~5,000,000 USD"
    );

    beforeTvl = calculator.getHLPValueE30(false);
    beforeAum = calculator.getAUME30(false);

    gmxV2Keeper_executeDepositOrder(GM_WBTCUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. TVL should not change more than 0.01%
    // 4. AUM should not change more than 0.01%
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0 WBTC should be on-hold");
    assertEq(vaultStorage.pullToken(address(wbtc)), 0, "pullToken should return zero");
    assertApproxEqRel(beforeTvl, afterTvl, 0.0001 ether, "tvl should not change more than 0.01%");
    assertApproxEqRel(beforeAum, afterAum, 0.0001 ether, "aum should not change more than 0.01%");
  }

  function testCorrectness_RebalanceHLPv2Deposit_WhenSomeoneJamInTheMiddle_DepositWithdrawCollateral() external {
    // Override GM(WBTC-USDC) price
    MockEcoPyth(address(ecoPyth2)).overridePrice(GM_WBTCUSDC_ASSET_ID, 1.11967292 * 1e8);

    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);

    // Create deposit order on GMXv2
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(GM_WBTCUSDC_ASSET_ID, 0.01 * 1e8, 0, 0);

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");

    // Alice try to deposit 1 WBTC as collateral in the middle
    motherload(address(wbtc), ALICE, 1 * 1e8);
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);

    // Assert the following conditions:
    // 1. WBTC's total amount should 23.48908996
    // 2. WBTC's balance should 23.47908996
    // 3. Alice's WBTC balance in HMX should be 1e8
    assertEq(vaultStorage.totalAmount(address(wbtc)), 23.48908996 * 1e8, "totalAmount should be 23.48908996 WBTC");
    assertEq(wbtc.balanceOf(address(vaultStorage)), 23.47908996 * 1e8, "balance should be 23.47908996 WBTC");
    assertEq(vaultStorage.traderBalances(ALICE, address(wbtc)), 1 * 1e8, "Alice's WBTC balance should be 1e8");

    // Alice try withdraw 1 WBTC as collateral in the middle
    vm.deal(ALICE, 1 ether);
    withdrawCollateral(ALICE, 0, wbtc, 1 * 1e8);

    // Assert the following conditions:
    // 1. WBTC's total amount should 22.48908996
    // 2. WBTC's balance should 22.47908996
    // 3. Alice's WBTC balance in HMX should be 0
    // 4. Alice's WBTC balance should be 1e8
    assertEq(vaultStorage.totalAmount(address(wbtc)), 22.48908996 * 1e8, "totalAmount should be 22.48908996 WBTC");
    assertEq(wbtc.balanceOf(address(vaultStorage)), 22.47908996 * 1e8, "balance should be 22.47908996 WBTC");
    assertEq(vaultStorage.traderBalances(ALICE, address(wbtc)), 0, "Alice's WBTC balance should be 0");
    assertEq(wbtc.balanceOf(ALICE), 1 * 1e8, "Alice's WBTC balance should be 1e8 (not in HMX)");

    beforeTvl = calculator.getHLPValueE30(false);
    beforeAum = calculator.getAUME30(false);

    gmxV2Keeper_executeDepositOrder(GM_WBTCUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. TVL should not change more than 0.01%
    // 4. AUM should not change more than 0.01%
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0 WBTC should be on-hold");
    assertEq(vaultStorage.pullToken(address(wbtc)), 0, "pullToken should return zero");
    assertApproxEqRel(beforeTvl, afterTvl, 0.0001 ether, "tvl should not change more than 0.01%");
    assertApproxEqRel(beforeAum, afterAum, 0.0001 ether, "aum should not change more than 0.01%");
  }

  function testCorrectness_RebalanceHLPv2Deposit__WhenSomeoneJamInTheMiddle_WhenTraderTakeProfitMoreThanHlpLiquidity()
    external
  {
    // Some liquidity is on-hold, but trader try to take profit more than available liquidity.
    // This should be handled correctly.
    // Override GM(WBTC-USDC) price
    MockEcoPyth(address(ecoPyth2)).overridePrice(GM_WBTCUSDC_ASSET_ID, 1.11967292 * 1e8);

    uint256 beforeTvl = calculator.getHLPValueE30(false);
    uint256 beforeAum = calculator.getAUME30(false);
    uint256 initialHmxBtcBalance = wbtc.balanceOf(address(vaultStorage));

    // Create deposit order on GMXv2
    bytes32 gmxDepositOrderKey = rebalanceHLPv2_createDepositOrder(GM_WBTCUSDC_ASSET_ID, 0.01 * 1e8, 0, 0);

    uint256 afterTvl = calculator.getHLPValueE30(false);
    uint256 afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. TVL should remains the same.
    // 2. AUM should remains the same.
    assertEq(beforeTvl, afterTvl, "tvl must remains the same");
    assertEq(beforeAum, afterAum, "aum must remains the same");

    // Alice try to deposit 1 WBTC as collateral and long ETH in the middle
    vm.deal(ALICE, 1 ether);
    motherload(address(wbtc), ALICE, 1 * 1e8);
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);
    marketBuy(ALICE, 0, 0, 750_000 * 1e30, address(wbtc));
    marketBuy(ALICE, 0, 0, 750_000 * 1e30, address(wbtc));
    // Assuming ETH moon to 20_000 USD and min profit passed
    vm.warp(block.timestamp + 60);
    MockEcoPyth(address(ecoPyth2)).overridePrice(bytes32("ETH"), 30_000 * 1e8);
    // Alice try to close position
    marketSell(ALICE, 0, 0, 750_000 * 1e30, address(wbtc));
    marketSell(ALICE, 0, 0, 750_000 * 1e30, address(wbtc));

    // Assert the following conditions:
    // 1. HLP's WBTC liquidity should be drained.
    // 2. HLP's WBTC liquidity on-hold should be 0.01 * 1e8.
    // 3. HMX actual WBTC balance should be initialHmxBtcBalance + 1e8 - 0.01 * 1e8.
    assertEq(vaultStorage.hlpLiquidity(address(wbtc)), 0, "HLP liquidity should be drained after Alice take profit");
    assertEq(vaultStorage.hlpLiquidityOnHold(address(wbtc)), 0.01 * 1e8, "0.01 WBTC should be on-hold");
    assertEq(
      wbtc.balanceOf(address(vaultStorage)),
      initialHmxBtcBalance + 1e8 - 0.01 * 1e8,
      "HMX WBTC balance should correct"
    );

    uint256 aliceWbtcBalanceBefore = vaultStorage.traderBalances(ALICE, address(wbtc));
    motherload(address(wbtc), ALICE, 1 * 1e8);
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);
    uint256 aliceWbtcBalanceAfter = vaultStorage.traderBalances(ALICE, address(wbtc));

    // Assert the following conditions:
    // 1. Alice's WBTC balance in HMX should increase by 1e8
    // 2. HMX actual WBTC balance should be initialHmxBtcBalance + 2e8 - 0.01 * 1e8.
    assertEq(aliceWbtcBalanceAfter, aliceWbtcBalanceBefore + 1 * 1e8, "Alice's WBTC balance should increase by 1e8");
    assertEq(
      wbtc.balanceOf(address(vaultStorage)),
      initialHmxBtcBalance + 2e8 - 0.01 * 1e8,
      "HMX WBTC balance should correct"
    );

    beforeTvl = calculator.getHLPValueE30(false);
    beforeAum = calculator.getAUME30(false);
    uint256 gmBtcLiquidityBefore = vaultStorage.hlpLiquidity(address(gmBTCUSD));

    gmxV2Keeper_executeDepositOrder(GM_WBTCUSDC_ASSET_ID, gmxDepositOrderKey);

    afterTvl = calculator.getHLPValueE30(false);
    afterAum = calculator.getAUME30(false);

    // Assert the following conditions:
    // 1. 0 WBTC should be on-hold.
    // 2. pullToken should return zero.
    // 3. TVL should not change more than 0.01%
    // 4. AUM should not change more than 0.01%
    // 5. GM(BTC-USDC) liquidity should increase
    assertEq(0, vaultStorage.hlpLiquidityOnHold(address(wbtc)), "0 WBTC should be on-hold");
    assertEq(vaultStorage.pullToken(address(wbtc)), 0, "pullToken should return zero");
    assertApproxEqRel(beforeTvl, afterTvl, 0.0001 ether, "tvl should not change more than 0.01%");
    assertApproxEqRel(beforeAum, afterAum, 0.0001 ether, "aum should not change more than 0.01%");
    assertTrue(
      vaultStorage.hlpLiquidity(address(gmBTCUSD)) > gmBtcLiquidityBefore,
      "GM(BTC-USDC) liquidity should increase"
    );
  }
}
