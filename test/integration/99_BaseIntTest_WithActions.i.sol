// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_Assertions } from "@hmx-test/integration/98_BaseIntTest_Assertions.i.sol";

contract BaseIntTest_WithActions is BaseIntTest_Assertions {
  /**
   * Liquidity
   */

  /// @notice Helper function to create liquidity and execute order via handler
  /// @param _liquidityProvider liquidity provider address
  /// @param _tokenIn liquidity token to add
  /// @param _amountIn amount of token to provide
  /// @param _executionFee execution fee
  /// @param _priceData Pyth's price data
  function addLiquidity(
    address _liquidityProvider,
    ERC20 _tokenIn,
    uint256 _amountIn,
    uint256 _executionFee,
    bytes[] memory _priceData,
    bool executeNow
  ) internal {
    vm.startPrank(_liquidityProvider);
    _tokenIn.approve(address(liquidityHandler), _amountIn);
    /// note: minOut always 0 to make test passed
    /// note: shouldWrap treat as false when only GLP could be liquidity
    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: _executionFee }(
      address(_tokenIn),
      _amountIn,
      0,
      _executionFee,
      false
    );
    vm.stopPrank();

    if (executeNow) {
      executePLPOrder(_orderIndex, _priceData);
    }
  }

  function executePLPOrder(uint256 _endIndex, bytes[] memory _priceData) internal {
    vm.startPrank(ORDER_EXECUTOR);
    liquidityHandler.executeOrder(_endIndex, payable(FEEVER), _priceData);
    vm.stopPrank();
  }

  /// @notice Helper function to remove liquidity and execute order via handler
  /// @param _liquidityProvider liquidity provider address
  /// @param _tokenOut liquidity token to remove
  /// @param _amountIn PLP amount to remove
  /// @param _executionFee execution fee
  /// @param _priceData Pyth's price data
  function removeLiquidity(
    address _liquidityProvider,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _executionFee,
    bytes[] memory _priceData,
    bool executeNow
  ) internal {
    vm.startPrank(_liquidityProvider);

    plpV2.approve(address(liquidityHandler), _amountIn);
    // _tokenOut.approve(address(liquidityHandler), _amountIn);
    /// note: minOut always 0 to make test passed
    /// note: shouldWrap treat as false when only GLP could be liquidity
    uint256 _orderIndex = liquidityHandler.createRemoveLiquidityOrder{ value: _executionFee }(
      _tokenOut,
      _amountIn,
      0,
      _executionFee,
      false
    );
    vm.stopPrank();

    if (executeNow) {
      executePLPOrder(_orderIndex, _priceData);
    }
  }

  /**
   * Cross Margin
   */
  /// @notice Helper function to deposit collateral via handler
  /// @param _account Trader's address
  /// @param _subAccountId Trader's sub-account ID
  /// @param _collateralToken Collateral token to deposit
  /// @param _depositAmount amount to deposit
  function depositCollateral(
    address _account,
    uint8 _subAccountId,
    ERC20 _collateralToken,
    uint256 _depositAmount
  ) internal {
    vm.startPrank(_account);
    _collateralToken.approve(address(crossMarginHandler), _depositAmount);
    crossMarginHandler.depositCollateral(_subAccountId, address(_collateralToken), _depositAmount, false);
    vm.stopPrank();
  }

  /// @notice Helper function to withdraw collateral via handler
  /// @param _account Trader's address
  /// @param _subAccountId Trader's sub-account ID
  /// @param _collateralToken Collateral token to withdraw
  /// @param _withdrawAmount amount to withdraw
  /// @param _priceData Pyth's price data
  function withdrawCollateral(
    address _account,
    uint8 _subAccountId,
    ERC20 _collateralToken,
    uint256 _withdrawAmount,
    bytes[] memory _priceData
  ) internal {
    vm.prank(_account);
    crossMarginHandler.withdrawCollateral(_subAccountId, address(_collateralToken), _withdrawAmount, _priceData, false);
  }

  /**
   * Trade
   */

  /// @notice Helper function to call MarketHandler buy
  /// @param _account Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account id.
  /// @param _marketIndex Market index.
  /// @param _buySizeE30 Buying size in e30 format.
  /// @param _tpToken Take profit token
  /// @param _priceData Pyth price feed data, can be derived from Pyth client SDK.
  function marketBuy(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _buySizeE30,
    address _tpToken,
    bytes[] memory _priceData
  ) internal {
    vm.prank(_account);
    marketTradeHandler.buy{ value: _priceData.length }(
      _account,
      _subAccountId,
      _marketIndex,
      _buySizeE30,
      _tpToken,
      _priceData
    );
  }

  /// @notice Helper function to call MarketHandler sell
  /// @param _account Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account id.
  /// @param _marketIndex Market index.
  /// @param _sellSizeE30 Buying size in e30 format.
  /// @param _tpToken Take profit token
  /// @param _priceData Pyth price feed data, can be derived from Pyth client SDK.
  function marketSell(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _sellSizeE30,
    address _tpToken,
    bytes[] memory _priceData
  ) internal {
    vm.prank(_account);
    marketTradeHandler.sell{ value: _priceData.length }(
      _account,
      _subAccountId,
      _marketIndex,
      _sellSizeE30,
      _tpToken,
      _priceData
    );
  }

  function createLimitTradeOrder(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    bool _triggerAboveThreshold,
    uint256 _executionFee,
    bool _reduceOnly,
    address _tpToken
  ) internal {
    vm.prank(_account);
    limitTradeHandler.createOrder{ value: _executionFee }(
      _subAccountId,
      _marketIndex,
      _sizeDelta,
      _triggerPrice,
      _triggerAboveThreshold,
      _executionFee,
      _reduceOnly,
      _tpToken
    );
  }

  function executeLimitTradeOrder(
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    address payable _feeReceiver,
    bytes[] memory _priceData
  ) internal {
    limitTradeHandler.executeOrder(_account, _subAccountId, _orderIndex, _feeReceiver, _priceData);
  }

  function liquidate(address _subAccount, bytes[] memory _priceData) internal {
    vm.prank(BOT);
    botHandler.liquidate(_subAccount, _priceData);
  }

  /**
   * COMMON FUNCTION
   */

  function getSubAccount(address _primary, uint8 _subAccountId) internal pure returns (address _subAccount) {
    if (_subAccountId > 255) revert();
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }

  function getPositionId(
    address _primary,
    uint8 _subAcountIndex,
    uint256 _marketIndex
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(getSubAccount(_primary, _subAcountIndex), _marketIndex));
  }
}
