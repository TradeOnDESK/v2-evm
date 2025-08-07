// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// OZ
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

/// HMX Tests
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";
import { MockEcoPyth } from "@hmx-test/mocks/MockEcoPyth.sol";

/// HMX
import { HMXLib } from "@hmx/libraries/HMXLib.sol";

abstract contract ForkEnvWithActions is ForkEnv {
  function makeEcoPythMockable() public {
    // Make EcoPyth mockable in every fork environment.
    MockEcoPyth mockEcoPyth = new MockEcoPyth();
    vm.etch(address(ecoPyth2), address(mockEcoPyth).code);
  }

  function unstakeHLP(address _account, uint256 _amount) internal {
    vm.startPrank(_account);
    hlpStaking.withdraw(_amount);
    vm.stopPrank();
  }

  function addLiquidity(address _liquidityProvider, IERC20 _tokenIn, uint256 _amountIn, bool executeNow) internal {
    vm.startPrank(_liquidityProvider);
    uint256 _executionFee = liquidityHandler.minExecutionOrderFee();
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
      executeHLPOrder(_orderIndex);
    }
  }

  function removeLiquidity(address _liquidityProvider, IERC20 _tokenOut, uint256 _amountIn, bool executeNow) internal {
    vm.startPrank(_liquidityProvider);
    uint256 _executionFee = liquidityHandler.minExecutionOrderFee();
    hlp.approve(address(liquidityHandler), _amountIn);
    // _tokenOut.approve(address(liquidityHandler), _amountIn);
    /// note: minOut always 0 to make test passed
    /// note: shouldWrap treat as false when only GLP could be liquidity
    uint256 _orderIndex = liquidityHandler.createRemoveLiquidityOrder{ value: _executionFee }(
      address(_tokenOut),
      _amountIn,
      0,
      _executionFee,
      false
    );
    vm.stopPrank();

    if (executeNow) {
      executeHLPOrder(_orderIndex);
    }
  }

  function executeHLPOrder(uint256 _endIndex) internal {
    (
      bytes32[] memory priceData,
      bytes32[] memory publishedTimeData,
      uint256 minPublishedTime,
      bytes32 encodedVaas
    ) = MockEcoPyth(address(ForkEnv.ecoPyth2)).getLastestPriceUpdateData();
    vm.startPrank(liquidityOrderExecutor);
    liquidityHandler.executeOrder(
      _endIndex,
      payable(liquidityOrderExecutor),
      priceData,
      publishedTimeData,
      minPublishedTime,
      encodedVaas
    );
    vm.stopPrank();
  }

  function depositCollateral(
    address _account,
    uint8 _subAccountId,
    IERC20 _collateralToken,
    uint256 _depositAmount
  ) internal {
    vm.startPrank(_account);
    _collateralToken.approve(address(crossMarginHandler), _depositAmount);
    crossMarginHandler.depositCollateral(_subAccountId, address(_collateralToken), _depositAmount, false);
    vm.stopPrank();
  }

  function withdrawCollateral(
    address _account,
    uint8 _subAccountId,
    IERC20 _collateralToken,
    uint256 _withdrawAmount
  ) internal {
    uint256 _executionFee = crossMarginHandler.minExecutionOrderFee();
    vm.startPrank(_account);
    crossMarginHandler.createWithdrawCollateralOrder{ value: _executionFee }(
      _subAccountId,
      address(_collateralToken),
      _withdrawAmount,
      _executionFee,
      false
    );
    vm.stopPrank();
    // Keeper comes and execute the order
    vm.startPrank(crossMarginOrderExecutor);
    (
      bytes32[] memory priceData,
      bytes32[] memory publishedTimeData,
      uint256 minPublishedTime,
      bytes32 encodedVaas
    ) = MockEcoPyth(address(ecoPyth2)).getLastestPriceUpdateData();
    crossMarginHandler.executeOrder(
      type(uint256).max,
      payable(crossMarginHandler),
      priceData,
      publishedTimeData,
      minPublishedTime,
      encodedVaas
    );
    vm.stopPrank();
  }

  function marketBuy(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _buySizeE30,
    address _tpToken
  ) internal {
    vm.startPrank(_account);
    uint256 executionOrderFee = limitTradeHandler.minExecutionFee();
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      _subAccountId,
      _marketIndex,
      int256(_buySizeE30),
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      _tpToken
    );
    vm.stopPrank();

    uint256 _orderIndex = limitTradeHandler.limitOrdersIndex(HMXLib.getSubAccount(_account, _subAccountId)) - 1;

    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = _account;
    subAccountIds[0] = _subAccountId;
    orderIndexes[0] = _orderIndex;

    (
      bytes32[] memory priceData,
      bytes32[] memory publishedTimeData,
      uint256 minPublishedTime,
      bytes32 encodedVaas
    ) = MockEcoPyth(address(ForkEnv.ecoPyth2)).getLastestPriceUpdateData();

    vm.startPrank(limitOrderExecutor);
    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(limitOrderExecutor),
      priceData,
      publishedTimeData,
      minPublishedTime,
      encodedVaas
    );
    vm.stopPrank();
  }

  function marketSell(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _sellSizeE30,
    address _tpToken
  ) internal {
    vm.startPrank(_account);
    uint256 executionOrderFee = limitTradeHandler.minExecutionFee();
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      _subAccountId,
      _marketIndex,
      -int256(_sellSizeE30),
      0, // trigger price always be 0
      0,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      _tpToken
    );
    vm.stopPrank();

    uint256 _orderIndex = limitTradeHandler.limitOrdersIndex(HMXLib.getSubAccount(_account, _subAccountId)) - 1;

    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = _account;
    subAccountIds[0] = _subAccountId;
    orderIndexes[0] = _orderIndex;

    (
      bytes32[] memory priceData,
      bytes32[] memory publishedTimeData,
      uint256 minPublishedTime,
      bytes32 encodedVaas
    ) = MockEcoPyth(address(ForkEnv.ecoPyth2)).getLastestPriceUpdateData();

    vm.startPrank(limitOrderExecutor);
    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(limitOrderExecutor),
      priceData,
      publishedTimeData,
      minPublishedTime,
      encodedVaas
    );
    vm.stopPrank();
  }
}
