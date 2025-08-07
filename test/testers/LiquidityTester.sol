// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

import { StdAssertions } from "forge-std/StdAssertions.sol";

import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";

/// @title Liquidity Tester
/// @notice This Tester help to check state after user interact with LiquidityHandler / LiquidityService
contract LiquidityTester is StdAssertions {
  /**
   * Structs
   */
  struct LiquidityExpectedData {
    address token;
    address who;
    uint256 lpTotalSupply;
    uint256 totalAmount; // totalAmount in vaultStorage
    uint256 hlpLiquidity;
    uint256 hlpAmount;
    uint256 fee;
    uint256 executionFee;
  }

  /**
   * States
   */
  IHLP hlp;

  IVaultStorage vaultStorage;
  IPerpStorage perpStorage;

  address feeReceiver;

  uint256 constant MAX_DIFF = 0.0001 ether; // 0.01 %

  constructor(IHLP _hlp, IVaultStorage _vaultStorage, IPerpStorage _perpStorage, address _feeReceiver) {
    hlp = _hlp;
    vaultStorage = _vaultStorage;
    perpStorage = _perpStorage;
    feeReceiver = _feeReceiver;
  }

  /// @notice Assert function when HLP provider add / remove liquidity
  /// @dev This function will check
  ///      - HLP total supply
  ///      - Execution fee in handler, if address is valid
  ///      - HLP liquidity in VaultStorage's state
  ///      - Total token amount in VaultStorage's state
  ///      - Fee is VaultStorage's state
  ///      - Token balance in VaultStorage
  function assertLiquidityInfo(LiquidityExpectedData memory _expectedData) external {
    address _token = _expectedData.token;

    // Check HLP total supply
    assertApproxEqRel(hlp.totalSupply(), _expectedData.lpTotalSupply, MAX_DIFF, "HLP Total supply");
    assertApproxEqRel(hlp.balanceOf(_expectedData.who), _expectedData.hlpAmount, MAX_DIFF, "HLP Amount");

    // Order execution fee is on OrderExecutor in Native
    assertApproxEqRel(feeReceiver.balance, _expectedData.executionFee, MAX_DIFF, "Execution Order Fee");

    // Check VaultStorage's state
    assertApproxEqRel(
      vaultStorage.hlpLiquidity(_token),
      _expectedData.hlpLiquidity,
      MAX_DIFF,
      "HLP token liquidity amount"
    );
    assertApproxEqRel(vaultStorage.totalAmount(_token), _expectedData.totalAmount, MAX_DIFF, "TokenAmount balance");
    assertApproxEqRel(vaultStorage.protocolFees(_token), _expectedData.fee, MAX_DIFF, "Protocol Fee");
    assertApproxEqRel(
      vaultStorage.totalAmount(_token),
      vaultStorage.hlpLiquidity(_token) + vaultStorage.protocolFees(_token) + vaultStorage.devFees(_token),
      MAX_DIFF
    );

    // Check token balance
    // balanceOf must be equals to hlpLiquidity in Vault
    assertApproxEqRel(
      IERC20(_token).balanceOf(address(vaultStorage)),
      _expectedData.totalAmount,
      MAX_DIFF,
      "Vault Storage Token Balance"
    );
  }
}
