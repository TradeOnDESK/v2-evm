pragma solidity 0.8.20;

import { ERC4626Upgradeable } from "openzeppelin-contracts-upgradeable-5.4.0/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract DLP is ERC4626Upgradeable {
  constructor() ERC4626Upgradeable() {}
}
