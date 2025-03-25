// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IDESKVault } from "@hmx/interfaces/desk/IDESKVault.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract MockDESKVault is IDESKVault {
  mapping(address token => uint256 minDeposit) public minDeposits;

  function deposit(address _tokenAddress, bytes32 _subaccount, uint256 _amount) external {
    ERC20Upgradeable(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
  }

  function setMinDeposit(address _tokenAddress, uint256 _minDeposit) external {
    minDeposits[_tokenAddress] = _minDeposit;
  }
}
