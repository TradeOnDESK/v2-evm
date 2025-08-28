// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin-contracts-5.4.0/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin-contracts-upgradeable-5.4.0/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract DLP is ERC4626Upgradeable {
  function initialize(address asset) public initializer {
    __ERC4626_init(IERC20(asset));
    __ERC20_init("DLP", "DLP");
  }
}
