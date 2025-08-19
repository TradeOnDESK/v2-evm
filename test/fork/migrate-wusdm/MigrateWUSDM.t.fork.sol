// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// HMX
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IDESKVault } from "@hmx/interfaces/desk/IDESKVault.sol";

/// HMX Tests
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";
import { Cheats } from "@hmx-test/base/Cheats.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "forge-std/console2.sol";

// ExternalRebalancer
import { ExternalRebalancer } from "@hmx/contracts/ExternalRebalancer.sol";

// Forge
import { console } from "forge-std/console.sol";

contract MigrateWUSDM is ForkEnv, Cheats {
  // WUSDM token address from mainnet config
  IERC20 internal constant wusdm = IERC20(0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812);

  // ExternalRebalancer contract
  ExternalRebalancer public externalRebalancer;

  function setUp() public virtual {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"), 360674265);

    // Deploy ExternalRebalancer using Deployer
    externalRebalancer = Deployer.deployExternalRebalancer(
      address(proxyAdmin),
      address(vaultStorage),
      address(calculator),
      100 // 1% max AUM drop (100 basis points)
    );

    // Whitelist the test contract as an executor in ExternalRebalancer
    externalRebalancer.addWhitelistedExecutor(address(this));

    // Whitelist the ExternalRebalancer as a service executor
    vm.startPrank(vaultStorage.owner());
    vaultStorage.setServiceExecutors(address(externalRebalancer), true);
    vm.stopPrank();
  }

  function testMigrateWUSDM_RemoveFromHLPAndPutOnHold() external {
    // Step 1: Check initial state
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 initialWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 initialUSDCBalance = usdc.balanceOf(address(vaultStorage));
    uint256 initialAUM = calculator.getAUME30(false);

    console.log("Initial WUSDM HLP Liquidity:", initialWUSDMHLPLiquidity);
    console.log("Initial WUSDM On Hold:", initialWUSDMOnHold);
    console.log("Initial USDC Balance in Vault:", initialUSDCBalance);
    console.log("Initial AUM:", initialAUM);

    // Ensure we have WUSDM liquidity to migrate
    assertGt(initialWUSDMHLPLiquidity, 0, "Should have WUSDM liquidity to migrate");

    // Step 2: ExternalRebalancer removes WUSDM from HLP liquidity and puts it on hold
    // The removed tokens will be transferred to the ExternalRebalancer itself
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, address(externalRebalancer));

    // Step 3: Verify the state after putting WUSDM on hold
    uint256 wusdmHLPLiquidityAfter = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 wusdmOnHoldAfter = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 aumAfterOnHold = calculator.getAUME30(false);

    console.log("WUSDM HLP Liquidity after on-hold:", wusdmHLPLiquidityAfter);
    console.log("WUSDM On Hold after migration:", wusdmOnHoldAfter);
    console.log("AUM after putting WUSDM on hold:", aumAfterOnHold);

    // Verify WUSDM is removed from HLP liquidity
    assertEq(wusdmHLPLiquidityAfter, 0, "WUSDM should be removed from HLP liquidity");

    // Verify WUSDM is put on hold
    assertEq(wusdmOnHoldAfter, initialWUSDMHLPLiquidity, "WUSDM should be put on hold");

    // Verify AUM doesn't drop more than 1% after putting WUSDM on hold
    if (aumAfterOnHold <= initialAUM) {
      uint256 aumDropPercentage = ((initialAUM - aumAfterOnHold) * 100) / initialAUM;
      assertLe(aumDropPercentage, 1, "AUM should not drop more than 1% after putting WUSDM on hold");
      console.log("AUM drop percentage after on-hold:", aumDropPercentage);
    } else {
      console.log("AUM increased after putting WUSDM on hold - no drop to calculate");
    }

    // Step 4: ExternalRebalancer injects USDC to replace WUSDM
    uint256 usdcAmountToInject = (initialWUSDMHLPLiquidity * 108) / 100 / 1e12;

    // Mint USDC to the ExternalRebalancer using deal
    deal(address(usdc), address(this), usdcAmountToInject);

    // Complete the rebalance by adding USDC as replacement
    usdc.approve(address(externalRebalancer), usdcAmountToInject);
    console2.log("usdc.balanceOf(address(this))", usdc.balanceOf(address(this)));
    externalRebalancer.completeRebalance(address(wusdm), address(usdc), usdcAmountToInject);

    // Step 5: Verify USDC injection
    uint256 usdcHLPLiquidityAfter = vaultStorage.hlpLiquidity(address(usdc));
    uint256 aumAfterUSDCInjection = calculator.getAUME30(false);

    console.log("USDC HLP Liquidity after injection:", usdcHLPLiquidityAfter);
    console.log("AUM after USDC injection:", aumAfterUSDCInjection);

    // Verify USDC is added to HLP liquidity
    assertGt(usdcHLPLiquidityAfter, 0, "USDC should be added to HLP liquidity");

    // Verify AUM doesn't drop more than 1% after USDC injection
    if (aumAfterUSDCInjection <= initialAUM) {
      uint256 aumDropPercentageAfterUSDC = ((initialAUM - aumAfterUSDCInjection) * 100) / initialAUM;
      assertLe(aumDropPercentageAfterUSDC, 1, "AUM should not drop more than 1% after USDC injection");
      console.log("AUM drop percentage after USDC injection:", aumDropPercentageAfterUSDC);
    } else {
      console.log("AUM increased after USDC injection - no drop to calculate");
    }

    // Step 6: Verify final state
    uint256 finalWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 finalWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 finalAUM = calculator.getAUME30(false);

    console.log("Final WUSDM On Hold:", finalWUSDMOnHold);
    console.log("Final WUSDM HLP Liquidity:", finalWUSDMHLPLiquidity);
    console.log("Final AUM:", finalAUM);

    // Verify WUSDM on-hold is cleared (should be cleared during completeRebalance)
    assertEq(finalWUSDMOnHold, 0, "WUSDM on-hold should be cleared");

    // Verify WUSDM HLP liquidity remains at 0
    assertEq(finalWUSDMHLPLiquidity, 0, "WUSDM HLP liquidity should remain at 0");

    // Verify USDC is properly injected
    assertGt(usdcHLPLiquidityAfter, 0, "USDC should be in HLP liquidity");

    // Verify final AUM doesn't drop more than 1% from initial
    if (finalAUM <= initialAUM) {
      uint256 finalAUMDropPercentage = ((initialAUM - finalAUM) * 100) / initialAUM;
      assertLe(finalAUMDropPercentage, 1, "Final AUM should not drop more than 1% from initial");
      console.log("Final AUM drop percentage:", finalAUMDropPercentage);
    } else {
      console.log("Final AUM increased - no drop to calculate");
    }

    console.log("WUSDM migration completed successfully!");
  }

  function testMigrateWUSDM_RevertWhenNotWhitelisted() external {
    // Test that only whitelisted executors can call startRebalance
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));

    // Try to call with a different address (should revert)
    vm.startPrank(ALICE);

    vm.expectRevert(abi.encodeWithSelector(ExternalRebalancer.ExternalRebalancer_NotWhitelisted.selector));
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, ALICE);

    vm.stopPrank();
  }

  function testMigrateWUSDM_RevertWhenInsufficientLiquidity() external {
    // Test that trying to remove more than available liquidity reverts
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 excessiveAmount = initialWUSDMHLPLiquidity + 1;

    vm.startPrank(address(this));

    vm.expectRevert(abi.encodeWithSelector(ExternalRebalancer.ExternalRebalancer_InsufficientLiquidity.selector));
    externalRebalancer.startRebalance(address(wusdm), excessiveAmount, address(externalRebalancer));

    vm.stopPrank();
  }

  function testMigrateWUSDM_VerifyOnHoldAccounting() external {
    // Test the on-hold accounting mechanism
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 initialWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 initialTotalAmount = vaultStorage.totalAmount(address(wusdm));

    console.log("Initial total amount:", initialTotalAmount);
    console.log("Initial HLP liquidity:", initialWUSDMHLPLiquidity);
    console.log("Initial on-hold:", initialWUSDMOnHold);

    // Remove WUSDM from HLP and put on hold using ExternalRebalancer
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, address(externalRebalancer));

    uint256 totalAmountAfter = vaultStorage.totalAmount(address(wusdm));
    uint256 hlpLiquidityAfter = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 onHoldAfter = vaultStorage.hlpLiquidityOnHold(address(wusdm));

    console.log("Total amount after:", totalAmountAfter);
    console.log("HLP liquidity after:", hlpLiquidityAfter);
    console.log("On-hold after:", onHoldAfter);

    // Verify that total amount remains the same (on-hold is included in total amount)
    assertEq(totalAmountAfter, initialTotalAmount, "Total amount should remain the same");

    // Verify HLP liquidity is reduced
    assertEq(hlpLiquidityAfter, 0, "HLP liquidity should be 0");

    // Verify on-hold is increased
    assertEq(onHoldAfter, initialWUSDMHLPLiquidity, "On-hold should equal removed liquidity");
  }

  function testMigrateWUSDM_AUMDropExceeded() external {
    // Test that rebalance fails when AUM drop exceeds maximum allowed
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));

    // Set a very low max AUM drop percentage (0.1%)
    externalRebalancer.setMaxAUMDropPercentage(10); // 10 basis points = 0.1%

    // Start rebalance
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, address(externalRebalancer));

    // Try to complete rebalance with insufficient replacement amount
    uint256 insufficientReplacementAmount = 1;

    // Mint insufficient USDC to ExternalRebalancer
    deal(address(usdc), address(this), insufficientReplacementAmount);

    // approve usdc to external rebalancer
    usdc.approve(address(externalRebalancer), insufficientReplacementAmount);

    // This should revert due to AUM drop exceeding the maximum allowed
    vm.expectRevert(abi.encodeWithSelector(ExternalRebalancer.ExternalRebalancer_AUMDropExceeded.selector));
    externalRebalancer.completeRebalance(address(wusdm), address(usdc), insufficientReplacementAmount);
  }

  function testMigrateWUSDM_SuccessfulRebalanceWithAUMCheck() external {
    // Test successful rebalance with proper AUM validation
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 initialAUM = calculator.getAUME30(false);

    // Set reasonable max AUM drop percentage (1%)
    externalRebalancer.setMaxAUMDropPercentage(100); // 100 basis points = 1%

    // Start rebalance
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, address(externalRebalancer));

    // Complete rebalance with sufficient replacement amount
    uint256 replacementAmount = (initialWUSDMHLPLiquidity * 108) / 100 / 1e12;
    deal(address(usdc), address(this), replacementAmount);

    // This should succeed
    usdc.approve(address(externalRebalancer), replacementAmount);
    externalRebalancer.completeRebalance(address(wusdm), address(usdc), replacementAmount);

    // Verify final state
    uint256 finalAUM = calculator.getAUME30(false);
    uint256 finalWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 finalUSDCBalance = vaultStorage.hlpLiquidity(address(usdc));

    // Verify WUSDM on-hold is cleared
    assertEq(finalWUSDMOnHold, 0, "WUSDM on-hold should be cleared");

    // Verify USDC is added
    assertGt(finalUSDCBalance, 0, "USDC should be added to HLP liquidity");

    // Verify AUM drop is within acceptable range
    if (finalAUM <= initialAUM) {
      uint256 aumDropPercentage = ((initialAUM - finalAUM) * 10000) / initialAUM; // in basis points
      assertLe(aumDropPercentage, 100, "AUM drop should not exceed 1%");
    }

    console.log("Successful rebalance with AUM validation completed!");
  }

  function testMigrateWUSDM_AUMIncreaseExceeded() external {
    // Test that rebalance fails when AUM increase exceeds maximum allowed
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 initialAUM = calculator.getAUME30(false);

    // Set a very low max AUM change percentage (0.1%)
    externalRebalancer.setMaxAUMDropPercentage(10); // 10 basis points = 0.1%

    // Start rebalance
    externalRebalancer.startRebalance(address(wusdm), initialWUSDMHLPLiquidity, address(externalRebalancer));

    // Try to complete rebalance with excessive replacement amount that would cause AUM to increase too much
    // We'll use a much larger amount than the removed WUSDM to simulate a scenario where AUM increases significantly
    uint256 excessiveReplacementAmount = initialWUSDMHLPLiquidity * 10; // 10x the removed amount

    // Mint excessive USDC to ExternalRebalancer
    deal(address(usdc), address(this), excessiveReplacementAmount);

    // Approve USDC to external rebalancer
    usdc.approve(address(externalRebalancer), excessiveReplacementAmount);

    // This should revert due to AUM increase exceeding the maximum allowed
    vm.expectRevert(abi.encodeWithSelector(ExternalRebalancer.ExternalRebalancer_AUMIncreaseExceeded.selector));
    externalRebalancer.completeRebalance(address(wusdm), address(usdc), excessiveReplacementAmount);

    console.log("AUM increase exceeded test completed successfully!");
  }
}
