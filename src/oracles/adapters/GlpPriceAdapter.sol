// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { IPriceAdapter } from "@hmx/oracles/interfaces/IPriceAdapter.sol";

contract GlpPriceAdapter is IPriceAdapter {
  IERC20 public sGlp;
  IGmxGlpManager public glpManager;

  constructor(IERC20 sGlp_, IGmxGlpManager glpManager_) {
    sGlp = sGlp_;
    glpManager = glpManager_;
  }

  /// @notice Return the price of GLP in 18 decimals
  function getPrice() external view returns (uint256 price) {
    price = (glpManager.getPrice(true) + glpManager.getPrice(false)) / 2e12;
  }
}
