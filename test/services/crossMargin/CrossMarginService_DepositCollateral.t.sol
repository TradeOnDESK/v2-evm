// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { CrossMarginService_Base, MockErc20 } from "./CrossMarginService_Base.t.sol";

// What is this test DONE
// - revert
//   - Try deposit token collateral with not in whitelist
//   - Try deposit token collaeral with not accepted token (Ex. Fx, Equity)
//   - Try deposit token collateral with transfer amount to VaultStorage less than state accounting
// - success
//   - Try deposit token collateral with initial balance and test accounting balance
//   - Try deposit token collateral with initial balance and test deposit token lists
//   - Try deposit token collateral with existing balance and test deposit token lists + balance

contract CrossMarginService_DepositCollateral is CrossMarginService_Base {
  function setUp() public virtual override {
    super.setUp();
  }

  // =========================================
  // | ------- Test Revert ----------------- |
  // =========================================

  // Try deposit token collateral with not in whitelist
  function testRevert_service_depositCollateral_onlyWhitelistedExecutor() external {
    vm.expectRevert(abi.encodeWithSignature("IConfigStorage_NotWhiteListed()"));
    crossMarginService.depositCollateral(CROSS_MARGIN_HANDLER, 1, address(weth), 10 ether);
  }

  // Try deposit token collateral with not accepted token (Ex. Fx, Equity)
  function testRevert_service_depositCollateral_onlyAcceptedToken() external {
    vm.prank(CROSS_MARGIN_HANDLER);
    vm.expectRevert(abi.encodeWithSignature("IConfigStorage_NotAcceptedCollateral()"));
    crossMarginService.depositCollateral(CROSS_MARGIN_HANDLER, 1, address(dai), 10 ether);
  }

  // Try deposit token collateral with transfer amount to VaultStorage less than state accounting
  function testRevert_service_depositCollateral_invalidDepositBalance() external {
    address token = address(weth);
    weth.mint(ALICE, 1 ether);

    vm.startPrank(ALICE);
    // simulate transfer from Handler to VaultStorage
    IERC20(token).transfer(address(vaultStorage), 0.5 ether);

    MockErc20(token).approve(address(crossMarginService), type(uint256).max);
    vm.expectRevert(abi.encodeWithSignature("ICrossMarginService_InvalidDepositBalance()"));
    crossMarginService.depositCollateral(ALICE, 1, token, 1 ether);
    vm.stopPrank();
  }

  // =========================================
  // | ------- Test Correctness ------------ |
  // =========================================

  // Try deposit token collateral with initial balance and test accounting balance
  function testCorrectness_service_depositCollateral_newDepositingToken() external {
    // Before start depositing, ALICE must has 0 amount of WETH token
    assertEq(vaultStorage.traderBalances(getSubAccount(ALICE, 1), address(weth)), 0);
    assertEq(weth.balanceOf(address(vaultStorage)), 0);

    weth.mint(ALICE, 10 ether);
    simulateAliceDepositToken(address(weth), 10 ether);

    // After deposited, ALICE must has 10 WETH as collateral token
    assertEq(vaultStorage.traderBalances(getSubAccount(ALICE, 1), address(weth)), 10 ether);
    assertEq(weth.balanceOf(address(vaultStorage)), 10 ether);
  }

  // Try deposit token collateral with initial balance and test deposit token lists
  function testCorrectness_service_depositCollateral_newDepositingToken_traderTokenList() external {
    // Before ALICE start depositing, token lists must contains no token
    address[] memory traderTokenBefore = vaultStorage.getTraderTokens(getSubAccount(ALICE, 1));
    assertEq(traderTokenBefore.length, 0);

    weth.mint(ALICE, 10 ether);
    simulateAliceDepositToken(address(weth), 10 ether);

    // After ALICE start depositing, token lists must contains 1 token
    address[] memory traderTokenAfter = vaultStorage.getTraderTokens(getSubAccount(ALICE, 1));
    assertEq(traderTokenAfter.length, 1);
  }

  // Try deposit token collateral with existing balance and test deposit token lists + balance
  function testCorrectness_service_depositCollateral_oldDepositingToken_traderTokenList() external {
    // Before ALICE start depositing, token lists must contains no token
    address[] memory traderTokenBefore = vaultStorage.getTraderTokens(getSubAccount(ALICE, 1));
    assertEq(traderTokenBefore.length, 0);

    // ALICE deposits first time
    weth.mint(ALICE, 10 ether);
    simulateAliceDepositToken(address(weth), 10 ether);

    // ALICE deposits second time
    weth.mint(ALICE, 10 ether);
    simulateAliceDepositToken(address(weth), 10 ether);

    // After ALICE start depositing, token lists must contains 1 token
    address[] memory traderTokenAfter = vaultStorage.getTraderTokens(getSubAccount(ALICE, 1));
    assertEq(traderTokenAfter.length, 1);

    // After deposited, ALICE must has 20 WETH as collateral token
    assertEq(vaultStorage.traderBalances(getSubAccount(ALICE, 1), address(weth)), 20 ether);
    assertEq(weth.balanceOf(address(vaultStorage)), 20 ether);
  }
}
