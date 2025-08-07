// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

contract BulkSendErc20 {
  using SafeERC20 for IERC20;

  error BulkSendErc20_BadArgs();

  function leggo(IERC20[] calldata _tokens, address[] calldata recipients, uint256[] calldata _amounts) external {
    if (_tokens.length != recipients.length || _tokens.length != _amounts.length) {
      revert BulkSendErc20_BadArgs();
    }

    for (uint256 i = 0; i < _tokens.length; ) {
      _tokens[i].safeTransferFrom(msg.sender, recipients[i], _amounts[i]);

      unchecked {
        ++i;
      }
    }
  }
}
