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

// Forge
import { console } from "forge-std/console.sol";

contract MigrateWUSDM is ForkEnv, Cheats {
  // WUSDM token address from mainnet config
  IERC20 internal constant wusdm = IERC20(0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812);

  function setUp() public virtual {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"));

    // Whitelist the multi-sig as a service executor
    vm.startPrank(vaultStorage.owner());
    vaultStorage.setServiceExecutors(multiSig, true);
    vm.stopPrank();
  }

  function testMigrateWUSDM_RemoveFromHLPAndPutOnHold() external {
    // Step 1: Check initial state
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 initialWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 initialUSDCBalance = usdc.balanceOf(address(vaultStorage));

    console.log("Initial WUSDM HLP Liquidity:", initialWUSDMHLPLiquidity);
    console.log("Initial WUSDM On Hold:", initialWUSDMOnHold);
    console.log("Initial USDC Balance in Vault:", initialUSDCBalance);

    // Ensure we have WUSDM liquidity to migrate
    assertGt(initialWUSDMHLPLiquidity, 0, "Should have WUSDM liquidity to migrate");

    // Step 2: Multi-sig removes WUSDM from HLP liquidity and puts it on hold
    vm.startPrank(multiSig);

    // Remove all WUSDM from HLP liquidity and put it on hold
    vaultStorage.removeHLPLiquidityOnHold(address(wusdm), initialWUSDMHLPLiquidity);

    vm.stopPrank();

    // Step 3: Verify the state after putting WUSDM on hold
    uint256 wusdmHLPLiquidityAfter = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 wusdmOnHoldAfter = vaultStorage.hlpLiquidityOnHold(address(wusdm));

    console.log("WUSDM HLP Liquidity after on-hold:", wusdmHLPLiquidityAfter);
    console.log("WUSDM On Hold after migration:", wusdmOnHoldAfter);

    // Verify WUSDM is removed from HLP liquidity
    assertEq(wusdmHLPLiquidityAfter, 0, "WUSDM should be removed from HLP liquidity");

    // Verify WUSDM is put on hold
    assertEq(wusdmOnHoldAfter, initialWUSDMHLPLiquidity, "WUSDM should be put on hold");

    // Step 4: Multi-sig injects USDC to replace WUSDM
    vm.startPrank(multiSig);

    // Calculate equivalent USDC amount (assuming 1:1 ratio for this test)
    // In a real scenario, this would be calculated based on the actual exchange rate
    uint256 usdcAmountToInject = initialWUSDMHLPLiquidity;

    // Give the multi-sig some USDC first (in a real scenario, this would come from external sources)
    // We'll use a whale or the deployer to provide USDC to the multi-sig
    vm.stopPrank();

    // Mint USDC to the multi-sig using deal
    deal(address(usdc), multiSig, usdcAmountToInject);

    // Now the multi-sig can transfer USDC to vault storage
    vm.startPrank(multiSig);
    usdc.transfer(address(vaultStorage), usdcAmountToInject);

    // Add USDC to HLP liquidity
    vaultStorage.addHLPLiquidity(address(usdc), usdcAmountToInject);

    vm.stopPrank();

    // Step 5: Verify USDC injection
    uint256 usdcHLPLiquidityAfter = vaultStorage.hlpLiquidity(address(usdc));
    uint256 usdcBalanceAfter = usdc.balanceOf(address(vaultStorage));

    console.log("USDC HLP Liquidity after injection:", usdcHLPLiquidityAfter);
    console.log("USDC Balance in Vault after injection:", usdcBalanceAfter);

    // Verify USDC is added to HLP liquidity
    assertGt(usdcHLPLiquidityAfter, 0, "USDC should be added to HLP liquidity");

    // Step 6: Multi-sig clears the on-hold WUSDM
    vm.startPrank(multiSig);

    // Clear the on-hold WUSDM
    vaultStorage.clearOnHold(address(wusdm), initialWUSDMHLPLiquidity);

    vm.stopPrank();

    // Step 7: Verify final state
    uint256 finalWUSDMOnHold = vaultStorage.hlpLiquidityOnHold(address(wusdm));
    uint256 finalWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 finalUSDCBalance = usdc.balanceOf(address(vaultStorage));

    console.log("Final WUSDM On Hold:", finalWUSDMOnHold);
    console.log("Final WUSDM HLP Liquidity:", finalWUSDMHLPLiquidity);
    console.log("Final USDC Balance in Vault:", finalUSDCBalance);

    // Verify WUSDM on-hold is cleared
    assertEq(finalWUSDMOnHold, 0, "WUSDM on-hold should be cleared");

    // Verify WUSDM HLP liquidity remains at 0
    assertEq(finalWUSDMHLPLiquidity, 0, "WUSDM HLP liquidity should remain at 0");

    // Verify USDC is properly injected
    assertGt(usdcHLPLiquidityAfter, 0, "USDC should be in HLP liquidity");

    console.log("WUSDM migration completed successfully!");
  }

  function testMigrateWUSDM_RevertWhenNotMultiSig() external {
    // Test that only multi-sig can call removeHLPLiquidityOnHold
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));

    // Try to call with a different address (should revert)
    vm.startPrank(ALICE);

    vm.expectRevert();
    vaultStorage.removeHLPLiquidityOnHold(address(wusdm), initialWUSDMHLPLiquidity);

    vm.stopPrank();
  }

  function testMigrateWUSDM_RevertWhenInsufficientLiquidity() external {
    // Test that trying to remove more than available liquidity reverts
    uint256 initialWUSDMHLPLiquidity = vaultStorage.hlpLiquidity(address(wusdm));
    uint256 excessiveAmount = initialWUSDMHLPLiquidity + 1;

    vm.startPrank(multiSig);

    vm.expectRevert();
    vaultStorage.removeHLPLiquidityOnHold(address(wusdm), excessiveAmount);

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

    // Remove WUSDM from HLP and put on hold
    vm.startPrank(multiSig);
    vaultStorage.removeHLPLiquidityOnHold(address(wusdm), initialWUSDMHLPLiquidity);
    vm.stopPrank();

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
}
