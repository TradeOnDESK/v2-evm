// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

/// @title Mock Erc20 token - for testing purposes ONLY.
contract MockErc20 is ERC20 {
  uint8 internal _decimals;

  constructor(string memory name, string memory symbol, uint8 __decimals) ERC20(name, symbol) {
    _decimals = __decimals;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
