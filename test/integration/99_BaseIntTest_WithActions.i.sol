// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_Assertions } from "@hmx-test/integration/98_BaseIntTest_Assertions.i.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";

contract BaseIntTest_WithActions is BaseIntTest_Assertions {
  /**
   * Liquidity
   */

  /// @notice Helper function to create liquidity and execute order via handler
  /// @param _liquidityProvider liquidity provider address
  /// @param _tokenIn liquidity token to add
  /// @param _amountIn amount of token to provide
  /// @param _executionFee execution fee
  function addLiquidity(
    address _liquidityProvider,
    ERC20 _tokenIn,
    uint256 _amountIn,
    uint256 _executionFee,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
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
      executeHLPOrder(_orderIndex, _tickPrices, _publishTimeDiffs, _minPublishTime);
    }
  }

  function executeHLPOrder(
    uint256 _endIndex,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 /* _minPublishTime */
  ) internal {
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);

    vm.startPrank(ORDER_EXECUTOR);
    liquidityHandler.executeOrder(
      _endIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );
    vm.stopPrank();
  }

  /// @notice Helper function to remove liquidity and execute order via handler
  /// @param _liquidityProvider liquidity provider address
  /// @param _tokenOut liquidity token to remove
  /// @param _amountIn HLP amount to remove
  /// @param _executionFee execution fee
  function removeLiquidity(
    address _liquidityProvider,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _executionFee,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    bool executeNow
  ) internal {
    vm.startPrank(_liquidityProvider);

    hlpV2.approve(address(liquidityHandler), _amountIn);
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
      executeHLPOrder(_orderIndex, _tickPrices, _publishTimeDiffs, _minPublishTime);
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

  /**
   * Cross Margin
   */
  /// @notice Helper function to deposit weth as collateral via handler
  /// @param _account Trader's address
  /// @param _subAccountId Trader's sub-account ID
  /// @param _collateralToken Collateral token to deposit
  /// @param _depositAmount amount to deposit
  function depositCollateral(
    address _account,
    uint8 _subAccountId,
    ERC20 _collateralToken,
    uint256 _depositAmount,
    bool _shouldWrap
  ) internal {
    vm.startPrank(_account);
    _collateralToken.approve(address(crossMarginHandler), _depositAmount);
    crossMarginHandler.depositCollateral{ value: _depositAmount }(
      _subAccountId,
      address(_collateralToken),
      _depositAmount,
      _shouldWrap
    );
    vm.stopPrank();
  }

  /// @notice Helper function to withdraw collateral via handler
  /// @param _account Trader's address
  /// @param _subAccountId Trader's sub-account ID
  /// @param _collateralToken Collateral token to withdraw
  /// @param _withdrawAmount amount to withdraw
  function withdrawCollateral(
    address _account,
    uint8 _subAccountId,
    ERC20 _collateralToken,
    uint256 _withdrawAmount,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 /* _minPublishTime */,
    uint256 _executionFee
  ) internal {
    vm.prank(_account);
    uint256 orderIndex = crossMarginHandler.createWithdrawCollateralOrder{ value: _executionFee }(
      _subAccountId,
      address(_collateralToken),
      _withdrawAmount,
      _executionFee,
      false
    );

    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    crossMarginHandler.executeOrder({
      _endIndex: orderIndex,
      _feeReceiver: payable(ALICE),
      _priceData: priceUpdateData,
      _publishTimeData: publishTimeUpdateData,
      _minPublishTime: block.timestamp,
      _encodedVaas: keccak256("someEncodedVaas")
    });
  }

  /**
   * Cross Margin
   */
  /// @notice Helper function to transfer collateral between subAccount via handler
  /// @param _account Trader's address
  /// @param _subAccountIdFrom Trader's sub-account to withdraw from
  /// @param _subAccountIdTo Trader's sub-account to transfer to
  /// @param _collateralToken Collateral token to deposit
  /// @param _depositAmount amount to deposit
  function transferCollateralSubAccount(
    address _account,
    uint8 _subAccountIdFrom,
    uint8 _subAccountIdTo,
    address _collateralToken,
    uint256 _depositAmount
  ) internal returns (uint256[] memory _orderIndexes) {
    vm.startPrank(_account);
    uint256[] memory orderIndexes = new uint256[](1);
    uint256 _orderIndex = ext01Handler.createExtOrder{ value: 0.1 * 1e9 }(
      IExt01Handler.CreateExtOrderParams({
        orderType: 2,
        executionFee: 0.1 * 1e9,
        mainAccount: _account,
        subAccountId: _subAccountIdFrom,
        data: abi.encode(_subAccountIdFrom, _subAccountIdTo, _collateralToken, _depositAmount)
      })
    );
    vm.stopPrank();
    orderIndexes[0] = _orderIndex;
    _orderIndexes = orderIndexes;
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
  /// @param _tickPrices Pyth price feed data, can be derived from Pyth client SDK compressed in the form of Uniswap's tick prices
  function marketBuy(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _buySizeE30,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    marketBuy(
      _account,
      _subAccountId,
      _marketIndex,
      _buySizeE30,
      _tpToken,
      _tickPrices,
      _publishTimeDiffs,
      _minPublishTime,
      ""
    );
  }

  function marketBuy(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _buySizeE30,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory /* signature */
  ) internal {
    vm.prank(_account);
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

    uint256 _orderIndex = limitTradeHandler.limitOrdersIndex(getSubAccount(_account, _subAccountId)) - 1;
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);

    // if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = _account;
    subAccountIds[0] = _subAccountId;
    orderIndexes[0] = _orderIndex;

    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
  }

  /// @notice Helper function to call MarketHandler sell
  /// @param _account Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account id.
  /// @param _marketIndex Market index.
  /// @param _sellSizeE30 Buying size in e30 format.
  /// @param _tpToken Take profit token
  /// @param _tickPrices Pyth price feed data, can be derived from Pyth client SDK compressed in the form of Uniswap's tick prices
  function marketSell(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _sellSizeE30,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    marketSell(
      _account,
      _subAccountId,
      _marketIndex,
      _sellSizeE30,
      _tpToken,
      _tickPrices,
      _publishTimeDiffs,
      _minPublishTime,
      ""
    );
  }

  function marketSell(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _sellSizeE30,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory /* signature */
  ) internal {
    vm.prank(_account);
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

    uint256 _orderIndex = limitTradeHandler.limitOrdersIndex(getSubAccount(_account, _subAccountId)) - 1;
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);

    // if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = _account;
    subAccountIds[0] = _subAccountId;
    orderIndexes[0] = _orderIndex;

    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
  }

  function createLimitTradeOrder(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
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
      _acceptablePrice,
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
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    executeLimitTradeOrder(
      _account,
      _subAccountId,
      _orderIndex,
      _feeReceiver,
      _tickPrices,
      _publishTimeDiffs,
      _minPublishTime,
      ""
    );
  }

  function executeLimitTradeOrder(
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    address payable _feeReceiver,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory signature
  ) internal {
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));

    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = _account;
    subAccountIds[0] = _subAccountId;
    orderIndexes[0] = _orderIndex;

    limitTradeHandler.executeOrders(
      accounts,
      subAccountIds,
      orderIndexes,
      _feeReceiver,
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
  }

  function liquidate(
    address _subAccount,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    liquidate(_subAccount, _tickPrices, _publishTimeDiffs, _minPublishTime, "");
  }

  function liquidate(
    address _subAccount,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory signature
  ) internal {
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));
    vm.prank(BOT);
    botHandler.liquidate(
      _subAccount,
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
  }

  function forceTakeMaxProfit(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    forceTakeMaxProfit(
      _account,
      _subAccountId,
      _marketIndex,
      _tpToken,
      _tickPrices,
      _publishTimeDiffs,
      _minPublishTime,
      ""
    );
  }

  function forceTakeMaxProfit(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory signature
  ) internal {
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));
    vm.prank(BOT);
    botHandler.forceTakeMaxProfit(
      _account,
      _subAccountId,
      _marketIndex,
      _tpToken,
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
  }

  function closeDelistedMarketPosition(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime
  ) internal {
    closeDelistedMarketPosition(
      _account,
      _subAccountId,
      _marketIndex,
      _tpToken,
      _tickPrices,
      _publishTimeDiffs,
      _minPublishTime,
      ""
    );
  }

  function closeDelistedMarketPosition(
    address _account,
    uint8 _subAccountId,
    uint256 _marketIndex,
    address _tpToken,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 _minPublishTime,
    string memory signature
  ) internal {
    bytes32[] memory priceUpdateData = pyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = pyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    if (isStringNotEmpty(signature)) vm.expectRevert(abi.encodeWithSignature(signature));
    vm.prank(BOT);
    botHandler.closeDelistedMarketPosition(
      _account,
      _subAccountId,
      _marketIndex,
      _tpToken,
      priceUpdateData,
      publishTimeUpdateData,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );
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
    uint8 _subAccountIndex,
    uint256 _marketIndex
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(getSubAccount(_primary, _subAccountIndex), _marketIndex));
  }

  function toggleMarket(uint256 _marketIndex) internal {
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(_marketIndex);
    _marketConfig.active = !_marketConfig.active;
    configStorage.setMarketConfig(_marketIndex, _marketConfig, false);
  }

  function isStringNotEmpty(string memory str) public pure returns (bool) {
    bytes memory strBytes = bytes(str);
    return strBytes.length > 0;
  }
}
