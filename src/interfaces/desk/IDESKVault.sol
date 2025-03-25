// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IDESKVault {
  function deposit(address _tokenAddress, bytes32 _subaccount, uint256 _amount) external;

  function minDeposits(address _tokenAddress) external returns (uint256 minDeposit);
}
