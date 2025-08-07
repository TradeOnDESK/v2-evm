// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { StdAssertions } from "forge-std/StdAssertions.sol";

import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

/// @title CrossMargin Tester
/// @notice This Tester help to check information after user interact with CrossMarginHandler / CrossMarginService
contract CrossMarginTester is StdAssertions {
  /**
   * Struct
   */

  struct CrossMarginExpectedData {
    address trader;
    uint256 traderRemainingBalance;
    uint256 vaultTraderBalance;
    uint256 vaultTokenBalance;
    ERC20 token;
  }

  struct VaultStorageExpectedData {
    uint256 traderBalance;
    uint8 tokenLength;
  }
  /**
   * States
   */

  IVaultStorage vaultStorage;
  IPerpStorage perpStorage;

  address crossMarginHandler;

  constructor(IVaultStorage _vaultStorage, IPerpStorage _perpStorage, address _crossMarginHandler) {
    vaultStorage = _vaultStorage;
    perpStorage = _perpStorage;
    crossMarginHandler = _crossMarginHandler;
  }

  /// @notice Assert function when Trader interact deposit / withdraw collateral
  /// @dev This function will check
  ///       - Token balance
  ///         - Account
  ///         - VaultStorage
  ///         - CrossMarginHandler, if address is valid
  ///       - VaultStorage's state
  ///         - Trader balance
  ///         - Trader token list
  ///         - Total Amount - should be same with VaultStorage token balanceOf
  function assertCrossMarginInfo(VaultStorageExpectedData memory _vault, CrossMarginExpectedData memory _cm) internal {
    address _tokenAddress = address(_cm.token);
    uint256 _vaultTokenBalance = _cm.vaultTokenBalance;

    // Check token balance
    assertEq(_cm.token.balanceOf(_cm.trader), _vault.traderBalance, "Trader token balance in Wallet");
    assertEq(_cm.token.balanceOf(address(vaultStorage)), _vaultTokenBalance, "Token balance in VaultStorage");

    // note: to integrate this tester with CrossMarginService
    if (crossMarginHandler != address(0)) {
      assertEq(_cm.token.balanceOf(crossMarginHandler), 0, "Token balance in CrossMarginHandler");
    }

    // Check vault storage state
    assertEq(vaultStorage.totalAmount(_tokenAddress), _vaultTokenBalance, "Total amount of Token in VaultStorage");
    assertEq(
      vaultStorage.traderBalances(_cm.trader, _tokenAddress),
      _cm.vaultTraderBalance,
      "Total amount of Token in VaultStorage"
    );
  }
}
