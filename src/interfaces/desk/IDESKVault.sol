// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IDESKVault {
  function deposit(address _tokenAddress, bytes32 _subaccount, uint256 _amount) external;

  function minDeposits(address _tokenAddress) external returns (uint256 minDeposit);

  function depositRequests(
    uint256 requestId
  ) external returns (bytes32 subaccount, uint256 amount, address tokenAddress);

  function totalDepositRequests() external returns (uint256);
}
