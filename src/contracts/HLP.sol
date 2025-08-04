// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

// Interfaces
import { IHLP } from "./interfaces/IHLP.sol";
import { IRebaser } from "./interfaces/IRebaser.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract HLP is ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC20Upgradeable {
  mapping(address user => bool isMinter) public minters;
  address public rebaser;

  event SetMinter(address indexed minter, bool isMinter);
  event SetRebaser(address oldRebaser, address newRebaser);

  error HLP_InvalidRebaser();

  /**
   * Modifiers
   */

  modifier onlyMinter() {
    if (!minters[msg.sender]) {
      revert IHLP.IHLP_onlyMinter();
    }
    _;
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    ERC20Upgradeable.__ERC20_init("HLP", "HLP");
  }

  function setMinter(address minter, bool isMinter) external onlyOwner {
    minters[minter] = isMinter;
    emit SetMinter(minter, isMinter);
  }

  function originalTotalSupply() public view returns (uint256) {
    return super.totalSupply();
  }

  function totalSupply() public view virtual override returns (uint256) {
    return getRebasedAmount(super.totalSupply());
  }

  function originalBalanceOf(address account) public view returns (uint256) {
    return super.balanceOf(account);
  }

  function originalAllowance(address owner, address spender) public view returns (uint256) {
    return super.allowance(owner, spender);
  }

  function balanceOf(address account) public view virtual override returns (uint256) {
    return getRebasedAmount(super.balanceOf(account));
  }

  function allowance(address owner, address spender) public view virtual override returns (uint256) {
    return getRebasedAmount(super.allowance(owner, spender));
  }

  function approve(address spender, uint256 rebasedAmount) public virtual override returns (bool) {
    address owner = _msgSender();
    _approve(owner, spender, getOriginalAmount(rebasedAmount));
    return true;
  }

  function increaseAllowance(address spender, uint256 rebasedAddedValue) public virtual override returns (bool) {
    approve(spender, allowance(msg.sender, spender) + rebasedAddedValue);
    return true;
  }

  function decreaseAllowance(address spender, uint256 rebasedSubtractedValue) public virtual override returns (bool) {
    address owner = _msgSender();
    uint256 rebasedCurrentAllowance = allowance(owner, spender);
    require(rebasedCurrentAllowance >= rebasedSubtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
      approve(spender, rebasedCurrentAllowance - rebasedSubtractedValue);
    }

    return true;
  }

  function transferFrom(address from, address to, uint256 rebasedAmount) public virtual override returns (bool) {
    address spender = _msgSender();
    _spendAllowance(from, spender, getOriginalAmount(rebasedAmount));
    _transfer(from, to, getOriginalAmount(rebasedAmount));
    return true;
  }

  function _spendAllowance(address owner, address spender, uint256 amount) internal virtual override {
    uint256 currentAllowance = super.allowance(owner, spender);
    if (currentAllowance != type(uint256).max) {
      require(currentAllowance >= amount, "ERC20: insufficient allowance");
      unchecked {
        _approve(owner, spender, currentAllowance - amount);
      }
    }
  }

  function mint(address to, uint256 rebasedAmount) external onlyMinter {
    _mint(to, getOriginalAmount(rebasedAmount));
  }

  function burn(address from, uint256 rebasedAmount) external onlyMinter {
    _burn(from, getOriginalAmount(rebasedAmount));
  }

  function transfer(address to, uint256 rebasedAmount) public virtual override returns (bool) {
    address owner = _msgSender();
    _transfer(owner, to, getOriginalAmount(rebasedAmount));
    return true;
  }

  function setRebaser(address _rebaser) external onlyOwner {
    if (_rebaser == address(0)) revert HLP_InvalidRebaser();
    rebaser = _rebaser;

    emit SetRebaser(rebaser, _rebaser);
  }

  // TODO: improve preceision loss
  function getRebasedAmount(uint256 amount) public view returns (uint256) {
    if (rebaser == address(0)) {
      return amount;
    }

    uint256 rebaseIndex = IRebaser(rebaser).rebaseIndex();
    if (rebaseIndex == 0) {
      return amount;
    } else {
      return Math.mulDiv(amount, rebaseIndex, 1e18);
    }
  }

  // @param amount The amount of HLP in the rebased format
  // @return The amount of HLP in the original balance without rebase
  function getOriginalAmount(uint256 amount) public view returns (uint256) {
    if (rebaser == address(0)) {
      return amount;
    }

    uint256 rebaseIndex = IRebaser(rebaser).rebaseIndex();
    if (rebaseIndex == 0) {
      return amount;
    } else {
      // Check for potential overflow: if amount * 1e18 would overflow
      if (amount > type(uint256).max / 1e18) {
        // If multiplication would overflow, return maxUint256 as a safe fallback
        return type(uint256).max;
      }
      return Math.mulDiv(amount, 1e18, rebaseIndex);
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
