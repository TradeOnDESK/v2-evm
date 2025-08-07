// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// bases
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { ISwitchCollateralRouter } from "@hmx/extensions/switch-collateral/interfaces/ISwitchCollateralRouter.sol";
import { IDexter } from "@hmx/extensions/dexters/interfaces/IDexter.sol";

contract SwitchCollateralRouter is Ownable, ISwitchCollateralRouter {
  using SafeERC20 for ERC20;

  error SwitchCollateral_BadAmount();
  error SwitchCollateral_BadPath();
  error SwitchCollateralRouter_NotFoundDexter();

  mapping(address tokenIn => mapping(address tokenOut => IDexter)) public dexterOf;

  event LogSetDexter(address indexed tokenIn, address indexed tokenOut, IDexter prevDexter, IDexter newDexter);

  function execute(uint256 _amount, address[] calldata _path) external returns (uint256 _amountOut) {
    if (_amount == 0) revert SwitchCollateral_BadAmount();
    if (_path.length < 2) revert SwitchCollateral_BadPath();
    for (uint i = 0; i < _path.length - 1; i++) {
      (address _tokenIn, address _tokenOut) = (_path[i], _path[i + 1]);
      IDexter _dexter = dexterOf[_tokenIn][_tokenOut];

      // Check if the dexterOf[tokenIn][tokenOut] is registered.
      if (address(_dexter) == address(0)) revert SwitchCollateralRouter_NotFoundDexter();

      // Execute dexter
      ERC20(_tokenIn).safeTransfer(address(_dexter), _amount);
      _amount = _dexter.run(_tokenIn, _tokenOut, _amount);
    }

    // Return the amount of the last token.
    ERC20(_path[_path.length - 1]).safeTransfer(msg.sender, _amount);

    return _amount;
  }

  /*
   * Setters
   */
  function setDexterOf(address _tokenIn, address _tokenOut, address _switchCollateralExt) external onlyOwner {
    emit LogSetDexter(_tokenIn, _tokenOut, dexterOf[_tokenIn][_tokenOut], IDexter(_switchCollateralExt));
    dexterOf[_tokenIn][_tokenOut] = IDexter(_switchCollateralExt);
  }
}
