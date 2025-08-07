// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { StdStorage, stdStorage } from "forge-std/StdStorage.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

abstract contract Cheats {
  using stdStorage for StdStorage;

  StdStorage internal stdStore;

  function motherload(address token, address user, uint256 amount) internal {
    stdStore.target(token).sig(IERC20.balanceOf.selector).with_key(user).checked_write(amount);
  }
}
