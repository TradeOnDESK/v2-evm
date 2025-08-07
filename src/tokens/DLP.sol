pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "openzeppelin-contracts-upgradeable-5.4.0/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract DLP is ERC4626Upgradeable {
  function initialize(address asset) public initializer {
    __ERC4626_init(IERC20(asset));
  }
}
