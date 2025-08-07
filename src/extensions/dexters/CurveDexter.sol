// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// bases
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IDexter } from "@hmx/extensions/dexters/interfaces/IDexter.sol";
import { IStableSwap } from "@hmx/interfaces/curve/IStableSwap.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";

contract CurveDexter is Ownable, IDexter {
  using SafeERC20 for ERC20;

  error CurveDexter_PoolNotSet();
  error CurveDexter_WrongCoin();

  struct PoolConfig {
    IStableSwap pool;
    int128 fromIndex;
    int128 toIndex;
  }
  mapping(address => mapping(address => PoolConfig)) public poolConfigOf;
  IWNative public immutable weth;
  address internal constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  event LogSetPoolConfig(
    address indexed tokenIn,
    address indexed tokenOut,
    address prevPool,
    int128 prevFromIndex,
    int128 prevToIndex,
    address pool,
    int128 fromIndex,
    int128 toIndex
  );

  constructor(address _weth) {
    weth = IWNative(_weth);
  }

  /// @notice Run the extension logic to swap on Curve.
  /// @param _tokenIn The token to swap from.
  /// @param _tokenOut The token to swap to.
  /// @param _amountIn The amount of _tokenIn to swap.
  function run(address _tokenIn, address _tokenOut, uint256 _amountIn) external override returns (uint256 _amountOut) {
    // SLOAD
    PoolConfig memory _poolConfig = poolConfigOf[_tokenIn][_tokenOut];

    // Check
    // If poolConfig not set, then revert
    if (address(_poolConfig.pool) == address(0)) revert CurveDexter_PoolNotSet();
    // If fromIndex is invalid
    if (
      (address(_tokenIn) != address(weth) &&
        _poolConfig.pool.coins(uint256(int256(_poolConfig.fromIndex))) != _tokenIn) ||
      (address(_tokenIn) == address(weth) &&
        _poolConfig.pool.coins(uint256(int256(_poolConfig.fromIndex))) != CURVE_ETH)
    ) revert CurveDexter_WrongCoin();
    // If toIndex is invalid
    if (
      (address(_tokenOut) != address(weth) &&
        _poolConfig.pool.coins(uint256(int256(_poolConfig.toIndex))) != _tokenOut) ||
      (address(_tokenOut) == address(weth) && _poolConfig.pool.coins(uint256(int256(_poolConfig.toIndex))) != CURVE_ETH)
    ) revert CurveDexter_WrongCoin();

    // Approve tokenIn to pool if needed
    ERC20 _tIn = ERC20(_tokenIn);
    bool _isTokenInWeth = address(_tokenIn) == address(weth);
    if (!_isTokenInWeth) {
      // If tokenIn is not WETH, then approve tokenIn to pool
      if (_tIn.allowance(address(this), address(_poolConfig.pool)) < _amountIn)
        _tIn.safeApprove(address(_poolConfig.pool), type(uint256).max);

      // Swap
      _amountOut = _poolConfig.pool.exchange(_poolConfig.fromIndex, _poolConfig.toIndex, _amountIn, 0);
    } else {
      // If tokenIn is WETH, then unwrap it
      weth.withdraw(_amountIn);

      // Swap
      _amountOut = _poolConfig.pool.exchange{ value: _amountIn }(
        _poolConfig.fromIndex,
        _poolConfig.toIndex,
        _amountIn,
        0
      );
    }

    // If tokenOut is ETH, then wrap ETH
    if (_poolConfig.pool.coins(uint256(int256(_poolConfig.toIndex))) == CURVE_ETH) {
      weth.deposit{ value: _amountOut }();
    }

    // Transfer tokenOut to msg.sender
    ERC20(_tokenOut).safeTransfer(msg.sender, _amountOut);
  }

  /*
   * Setters
   */

  /// @notice Set pool config.
  /// @param _tokenIn Token to swap from.
  /// @param _tokenOut Token to swap to.
  /// @param _pool Curve pool address.
  /// @param _fromIndex Index of tokenIn in the pool.
  /// @param _toIndex Index of tokenOut in the pool.
  function setPoolConfigOf(
    address _tokenIn,
    address _tokenOut,
    address _pool,
    int128 _fromIndex,
    int128 _toIndex
  ) external onlyOwner {
    // SLOAD
    PoolConfig memory _prevPoolConfig = poolConfigOf[_tokenIn][_tokenOut];
    emit LogSetPoolConfig(
      _tokenIn,
      _tokenOut,
      address(_prevPoolConfig.pool),
      _prevPoolConfig.fromIndex,
      _prevPoolConfig.toIndex,
      _pool,
      _fromIndex,
      _toIndex
    );
    poolConfigOf[_tokenIn][_tokenOut] = PoolConfig({
      pool: IStableSwap(_pool),
      fromIndex: _fromIndex,
      toIndex: _toIndex
    });
  }

  receive() external payable {}
}
