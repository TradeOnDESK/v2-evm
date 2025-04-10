// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { CrossMarginHandler_Base, IPerpStorage } from "./CrossMarginHandler_Base.t.sol";
import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { CrossMarginHandler } from "@hmx/handlers/CrossMarginHandler.sol";

// What is this test DONE
// - revert
//   - Try withdraw token collateral with not accepted token (Ex. Fx, Equity)
//   - Try withdraw token collateral with insufficient allowance
// - success
//   - Try deposit and withdraw collateral with happy case
//   - Try deposit and withdraw collateral with happy case and check on token list of sub account
//   - Try deposit and withdraw multi tokens and checks on  token list of sub account

contract CrossMarginHandler_WithdrawCollateral is CrossMarginHandler_Base {
  function setUp() public virtual override {
    super.setUp();
  }

  /**
   * TEST CORRECTNESS
   */

  // Try deposit and withdraw collateral with happy case
  function testCorrectness_deskVaultNotSet() external {
    vm.deal(ALICE, 1 ether);
    usdc.mint(ALICE, 1000e6);
    simulateAliceDepositToken(address(usdc), 1000e6);

    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ICrossMarginHandler_DESKVaultNotSet()"));
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(usdc),
      100e6,
      executionOrderFee,
      false,
      true
    );
    vm.stopPrank();
  }

  function testCorrectness_deskVaultNotAcceptedToken() external {
    crossMarginHandler.setDESKVault(address(mockDESKVault));

    vm.deal(ALICE, 10 ether);
    weth.mint(ALICE, 10 ether);
    simulateAliceDepositToken(address(weth), 1 ether);

    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ICrossMarginHandler_DESKVaultNotAcceptedToken()"));
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(weth),
      1 ether,
      executionOrderFee,
      true,
      true
    );
    vm.stopPrank();
  }

  function testCorrectness_deskVaulLowerThanMinDeposit() external {
    crossMarginHandler.setDESKVault(address(mockDESKVault));

    vm.deal(ALICE, 1 ether);
    usdc.mint(ALICE, 1000e6);
    simulateAliceDepositToken(address(usdc), 1000e6);

    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ICrossMarginHandler_DESKVaultMinDeposit()"));
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(usdc),
      1e6,
      executionOrderFee,
      false,
      true
    );
    vm.stopPrank();
  }

  function testCorrectness_withdrawToDESK() external {
    crossMarginHandler.setDESKVault(address(mockDESKVault));

    vm.deal(ALICE, 1 ether);
    usdc.mint(ALICE, 1000e6);
    simulateAliceDepositToken(address(usdc), 1000e6);

    simulateAliceWithdrawToken(address(usdc), 90e6, tickPrices, publishTimeDiffs, block.timestamp, false, true);

    // After withdrawn with unwrap,
    // - Vault must have 910 USDC
    // - ALICE must have 910 USDC as collateral token
    // - ALICE must have 0 USDC in her wallet
    // - DESK Vault must have 90 USDC
    assertEq(usdc.balanceOf(address(vaultStorage)), 910e6);
    assertEq(vaultStorage.traderBalances(getSubAccount(ALICE, SUB_ACCOUNT_NO), address(usdc)), 910e6);
    assertEq(usdc.balanceOf(ALICE), 0);
    assertEq(usdc.balanceOf(address(mockDESKVault)), 90e6);
  }

  function testCorrectness_withdrawToDESK_failedAtDESK() external {
    crossMarginHandler.setDESKVault(address(mockDESKVault));
    mockDESKVault.setToRevertOnDeposit(true);

    vm.deal(ALICE, 1 ether);
    usdc.mint(ALICE, 1000e6);
    simulateAliceDepositToken(address(usdc), 1000e6);

    simulateAliceWithdrawToken(address(usdc), 90e6, tickPrices, publishTimeDiffs, block.timestamp, false, true);

    // After withdrawn with unwrap,
    // - Vault must have 910 USDC
    // - ALICE must have 910 USDC as collateral token
    // - ALICE must have 0 USDC in her wallet
    // - DESK Vault must have 90 USDC
    assertEq(usdc.balanceOf(address(vaultStorage)), 1000e6);
    assertEq(vaultStorage.traderBalances(getSubAccount(ALICE, SUB_ACCOUNT_NO), address(usdc)), 1000e6);
    assertEq(usdc.balanceOf(ALICE), 0);
    assertEq(usdc.balanceOf(address(mockDESKVault)), 0);

    (, , , , , address payable account, , , , ICrossMarginHandler.WithdrawOrderStatus status, ) = CrossMarginHandler(
      payable(address(crossMarginHandler))
    ).withdrawOrders(0);
    // Withdraw order should be removed because it failed
    assertTrue(uint256(status) == 0);
    assertEq(account, address(0));
  }
}
