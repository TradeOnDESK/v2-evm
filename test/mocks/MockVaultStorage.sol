// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";

contract MockVaultStorage {
  mapping(address => mapping(address => uint256)) public traderBalances;
  mapping(address => address[]) public traderTokens;
  mapping(address => uint256) public hlpLiquidity;
  mapping(address => uint256) public hlpLiquidityOnHold;
  mapping(address => uint256) public pendingRewardDebt;

  uint256 public hlpLiquidityDebtUSDE30;
  uint256 public globalBorrowingFeeDebt;
  uint256 public globalLossDebt;

  // =========================================
  // | ---------- Setter ------------------- |
  // =========================================

  function setTraderBalance(address _subAccount, address _token, uint256 _amount) external {
    traderBalances[_subAccount][_token] = _amount;
  }

  function setTraderTokens(address _subAccount, address _token) external {
    traderTokens[_subAccount].push(_token);
  }

  function setHlpLiquidity(address _token, uint256 _amount) external {
    hlpLiquidity[_token] = _amount;
  }

  function setHlpLiquidityOnHold(address _token, uint256 _amount) external {
    hlpLiquidityOnHold[_token] = _amount;
  }

  function setPendingRewardDebt(address _token, uint256 _amount) external {
    pendingRewardDebt[_token] = _amount;
  }

  function setHlpLiquidityDebtUSDE30(uint256 _amount) external {
    hlpLiquidityDebtUSDE30 = _amount;
  }

  function setGlobalBorrowingFeeDebt(uint256 _amount) external {
    globalBorrowingFeeDebt = _amount;
  }

  function setGlobalLossDebt(uint256 _amount) external {
    globalLossDebt = _amount;
  }

  // =========================================
  // | ---------- Getter ------------------- |
  // =========================================

  function getTraderTokens(address _subAccount) external view returns (address[] memory) {
    return traderTokens[_subAccount];
  }

  function getPendingRewardDebt(address _token) external view returns (uint256) {
    return pendingRewardDebt[_token];
  }
}
