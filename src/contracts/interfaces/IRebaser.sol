// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IRebaser {
  function rebase(uint256 newRebaseIndex) external;

  function rebaseIndex() external view returns (uint256);
}
