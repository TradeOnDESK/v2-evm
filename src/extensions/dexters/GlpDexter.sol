// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// bases
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IDexter } from "@hmx/extensions/dexters/interfaces/IDexter.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";
import { IGmxVault } from "@hmx/interfaces/gmx/IGmxVault.sol";

contract GlpDexter is Ownable, IDexter {
  using SafeERC20 for ERC20;

  error GlpDexter_Forbidden();
  error GlpDexter_NotSupported();
  error GlpDexter_TokenNotWhitelisted();

  ERC20 public weth;
  ERC20 public sGlp;
  IGmxGlpManager public glpManager;
  IGmxVault public gmxVault;
  IGmxRewardRouterV2 public gmxRewardRouter;

  constructor(address _weth, address _sGlp, address _glpManager, address _gmxVault, address _gmxRewardRouter) {
    weth = ERC20(_weth);
    sGlp = ERC20(_sGlp);
    glpManager = IGmxGlpManager(_glpManager);
    gmxVault = IGmxVault(_gmxVault);
    gmxRewardRouter = IGmxRewardRouterV2(_gmxRewardRouter);
  }

  /// @notice Run the extension logic.
  /// @dev This function supports both switching to and from sGlp.
  /// @param _tokenIn The token to switch from.
  /// @param _tokenOut The token to switch to.
  /// @param _amountIn The amount of _tokenIn to switch.
  function run(address _tokenIn, address _tokenOut, uint256 _amountIn) external override returns (uint256 _amountOut) {
    // Check
    if (_tokenOut == address(sGlp)) {
      if (!gmxVault.whitelistedTokens(_tokenIn)) revert GlpDexter_TokenNotWhitelisted();
      _amountOut = _toGlp(_tokenIn, _amountIn);
    } else if (_tokenIn == address(sGlp)) {
      if (!gmxVault.whitelistedTokens(_tokenOut)) revert GlpDexter_TokenNotWhitelisted();
      _amountOut = _fromGlp(_tokenOut, _amountIn);
    } else {
      revert GlpDexter_NotSupported();
    }
  }

  /// @notice Perform the switch to sGlp.
  /// @param _tokenIn The token to switch from.
  /// @param _amountIn The amount of _tokenIn to switch.
  function _toGlp(address _tokenIn, uint256 _amountIn) internal returns (uint256 _amountOut) {
    ERC20(_tokenIn).approve(address(glpManager), _amountIn);
    _amountOut = gmxRewardRouter.mintAndStakeGlp(address(_tokenIn), _amountIn, 0, 0);

    // Transfer sGlp to out to msg.sender
    sGlp.safeTransfer(msg.sender, _amountOut);
  }

  /// @notice Perform the switch from sGlp.
  /// @param _tokenOut The token to switch to.
  /// @param _amountIn The amount of sGlp to switch.
  function _fromGlp(address _tokenOut, uint256 _amountIn) internal returns (uint256 _amountOut) {
    _amountOut = gmxRewardRouter.unstakeAndRedeemGlp(_tokenOut, _amountIn, 0, address(this));
    // Transfer _tokenOut to msg.sender
    ERC20(_tokenOut).safeTransfer(msg.sender, _amountOut);
  }
}
