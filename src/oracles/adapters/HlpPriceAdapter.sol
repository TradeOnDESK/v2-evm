// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { IPriceAdapter } from "@hmx/oracles/interfaces/IPriceAdapter.sol";

contract HlpPriceAdapter is IPriceAdapter {
  IERC20 public hlp;
  ICalculator public calculator;

  constructor(IERC20 hlp_, ICalculator calculator_) {
    hlp = hlp_;
    calculator = calculator_;
  }

  /// @notice Return the price of HLP in 18 decimals
  function getPrice() external view returns (uint256 price) {
    price = (calculator.getAUME30(false) * 1e18) / hlp.totalSupply() / 1e12;
  }
}
