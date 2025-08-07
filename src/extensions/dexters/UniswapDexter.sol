// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// bases
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IPermit2 } from "@hmx/interfaces/uniswap/IPermit2.sol";
import { IUniversalRouter } from "@hmx/interfaces/uniswap/IUniversalRouter.sol";
import { IDexter } from "@hmx/extensions/dexters/interfaces/IDexter.sol";

contract UniswapDexter is Ownable, IDexter {
  using SafeERC20 for ERC20;

  error UniswapUniversalRouterSwitchCollateralExt_BadPath();

  IPermit2 public permit2;
  IUniversalRouter public universalRouter;
  mapping(address => mapping(address => bytes)) public pathOf;

  event LogSetPathOf(address indexed tokenIn, address indexed tokenOut, bytes prevPath, bytes path);

  constructor(address _permit2, address _universalRouter) {
    permit2 = IPermit2(_permit2);
    universalRouter = IUniversalRouter(_universalRouter);
  }

  /// @notice Run the extension logic to swap on Uniswap V3.
  /// @param _tokenIn The token to swap from.
  /// @param _tokenOut The token to swap to.
  /// @param _amountIn The amount of _tokenIn to swap.
  function run(address _tokenIn, address _tokenOut, uint256 _amountIn) external override returns (uint256 _amountOut) {
    // Check
    if (pathOf[_tokenIn][_tokenOut].length == 0) {
      revert UniswapUniversalRouterSwitchCollateralExt_BadPath();
    }

    // Approve tokenIn to Permit2 if needed
    ERC20 _tIn = ERC20(_tokenIn);
    if (_tIn.allowance(address(this), address(permit2)) < _amountIn)
      _tIn.safeApprove(address(permit2), type(uint256).max);
    // Approve UniUniversalRouter to spend tokenIn in Permit2 if needed
    (uint160 _allowance, , ) = permit2.allowance(address(this), _tokenIn, address(universalRouter));
    if (_allowance < uint160(_amountIn))
      permit2.approve(_tokenIn, address(universalRouter), type(uint160).max, type(uint48).max);

    uint256 _balanceBefore = ERC20(_tokenOut).balanceOf(address(this));
    // 0x00 => V3_SWAP_EXACT_IN
    bytes[] memory _inputs = new bytes[](1);
    _inputs[0] = abi.encode(address(this), _amountIn, 0, pathOf[_tokenIn][_tokenOut], true);
    universalRouter.execute(abi.encodePacked(bytes1(uint8(0x00))), _inputs);
    _amountOut = ERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;

    // Transfer tokenOut back to msg.sender
    ERC20(_tokenOut).safeTransfer(msg.sender, _amountOut);
  }

  /*
   * Setters
   */

  /// @notice Set swap path from tokenIn to tokenOut
  /// @dev It will also add reverse path from tokenOut to tokenIn
  /// @param _tokenIn The token to swap from
  /// @param _tokenOut The token to swap to
  /// @param _path The swap path
  function setPathOf(address _tokenIn, address _tokenOut, bytes calldata _path) external onlyOwner {
    emit LogSetPathOf(_tokenIn, _tokenOut, pathOf[_tokenIn][_tokenOut], _path);
    pathOf[_tokenIn][_tokenOut] = _path;
  }
}
