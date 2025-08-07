// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";
import { OracleMiddleware } from "@hmx/oracles/OracleMiddleware.sol";
import { IntentHandler } from "@hmx/handlers/IntentHandler.sol";
import { TradeService } from "@hmx/services/TradeService.sol";
import { ITradeOrderHelper } from "@hmx/helpers/interfaces/ITradeOrderHelper.sol";
import { IIntentHandler } from "@hmx/handlers/interfaces/IIntentHandler.sol";

contract TradeOrderHelper is Ownable, ITradeOrderHelper {
  ConfigStorage public configStorage;
  PerpStorage public perpStorage;
  OracleMiddleware public oracle;
  TradeService public tradeService;
  address public whitelistedCaller;

  mapping(uint256 marketIndex => uint256 sizeLimit) public positionSizeLimitOf;
  mapping(uint256 marketIndex => uint256 sizeLimit) public tradeSizeLimitOf;

  constructor(address _configStorage, address _perpStorage, address _oracle, address _tradeService) {
    configStorage = ConfigStorage(_configStorage);
    perpStorage = PerpStorage(_perpStorage);
    oracle = OracleMiddleware(_oracle);
    tradeService = TradeService(_tradeService);
  }

  modifier onlyWhitelistedCaller() {
    if (msg.sender != whitelistedCaller) revert TradeOrderHelper_NotWhiteListed();
    _;
  }

  function preValidate(
    address mainAccount,
    uint8 subAccountId,
    uint256 marketIndex,
    bool reduceOnly,
    int256 sizeDelta,
    uint256 expiryTimestamp
  ) external view returns (bool isSuccess, ResponseCode code) {
    if (expiryTimestamp < block.timestamp) {
      return (false, ResponseCode.OrderStale);
    }

    address _subAccount = HMXLib.getSubAccount(mainAccount, subAccountId);
    int256 _positionSizeE30 = perpStorage
      .getPositionById(HMXLib.getPositionId(_subAccount, marketIndex))
      .positionSizeE30;

    // Check trade size limit as per market
    if (tradeSizeLimitOf[marketIndex] > 0 && !reduceOnly && HMXLib.abs(sizeDelta) > tradeSizeLimitOf[marketIndex]) {
      return (false, ResponseCode.MaxTradeSize);
    }

    // Check position size limit as per market
    if (
      positionSizeLimitOf[marketIndex] > 0 &&
      !reduceOnly &&
      HMXLib.abs(_positionSizeE30 + sizeDelta) > positionSizeLimitOf[marketIndex]
    ) {
      return (false, ResponseCode.MaxPositionSize);
    }

    return (true, ResponseCode.Success);
  }

  function _validate(
    address /*mainAccount*/,
    uint8 /*subAccountId*/,
    uint256 marketIndex,
    bool /*reduceOnly*/,
    int256 sizeDelta,
    bool triggerAboveThreshold,
    uint256 triggerPrice,
    uint256 acceptablePrice,
    uint256 /*expiryTimestamp*/
  ) internal view returns (uint256 _oraclePrice, uint256 _executedPrice) {
    ValidatePositionOrderPriceVars memory vars;

    // SLOADs
    // Get price from Pyth
    vars.marketConfig = configStorage.getMarketConfigByIndex(marketIndex);
    vars.globalMarket = perpStorage.getMarketByIndex(marketIndex);

    // Validate trigger price with oracle price
    (vars.oraclePrice, ) = oracle.getLatestPrice(vars.marketConfig.assetId, true);
    vars.isPriceValid = triggerAboveThreshold ? vars.oraclePrice > triggerPrice : vars.oraclePrice < triggerPrice;

    if (!vars.isPriceValid) revert TradeOrderHelper_InvalidPriceForExecution();

    // Validate acceptable price with adaptive price
    (vars.adaptivePrice, , vars.marketStatus) = oracle.getLatestAdaptivePriceWithMarketStatus(
      vars.marketConfig.assetId,
      false,
      (int(vars.globalMarket.longPositionSize) - int(vars.globalMarket.shortPositionSize)),
      sizeDelta,
      vars.marketConfig.fundingRate.maxSkewScaleUSD,
      0
    );

    // Validate market status
    if (vars.marketStatus != 2) revert TradeOrderHelper_MarketIsClosed();

    // Validate price is executable
    bool isBuy = sizeDelta > 0;
    vars.isPriceValid = isBuy ? vars.adaptivePrice < acceptablePrice : vars.adaptivePrice > acceptablePrice;

    if (!vars.isPriceValid) revert TradeOrderHelper_PriceSlippage();

    return (vars.oraclePrice, vars.adaptivePrice);
  }

  function execute(
    IIntentHandler.ExecuteTradeOrderVars memory vars
  ) external onlyWhitelistedCaller returns (uint256 _oraclePrice, uint256 _executedPrice, bool _isFullClose) {
    // Retrieve existing position
    vars.positionId = HMXLib.getPositionId(
      HMXLib.getSubAccount(vars.order.account, vars.order.subAccountId),
      vars.order.marketIndex
    );
    PerpStorage.Position memory _existingPosition = PerpStorage(tradeService.perpStorage()).getPositionById(
      vars.positionId
    );

    vars.positionIsLong = _existingPosition.positionSizeE30 > 0;
    vars.isNewPosition = _existingPosition.positionSizeE30 == 0;

    // Check if the order is TP/SL, then make the sizeDelta = -positionSize
    int256 revisedSizeDelta = vars.order.sizeDelta;
    bool isDecreasePosition = !vars.isNewPosition &&
      ((vars.positionIsLong && vars.order.sizeDelta < 0) || (!vars.positionIsLong && vars.order.sizeDelta > 0));
    if (
      isDecreasePosition &&
      vars.order.reduceOnly &&
      HMXLib.abs(vars.order.sizeDelta) > HMXLib.abs(_existingPosition.positionSizeE30)
    ) {
      if (vars.order.sizeDelta > 0) {
        revisedSizeDelta = int256(HMXLib.abs(_existingPosition.positionSizeE30));
      } else {
        revisedSizeDelta = -int256(HMXLib.abs(_existingPosition.positionSizeE30));
      }
    }

    (_oraclePrice, _executedPrice) = _validate(
      vars.order.account,
      vars.order.subAccountId,
      vars.order.marketIndex,
      vars.order.reduceOnly,
      revisedSizeDelta,
      vars.order.triggerAboveThreshold,
      vars.order.triggerPrice,
      vars.order.acceptablePrice,
      vars.order.expiryTimestamp
    );

    // Execute the order
    if (vars.order.reduceOnly) {
      bool isDecreaseShort = (revisedSizeDelta > 0 && _existingPosition.positionSizeE30 < 0);
      bool isDecreaseLong = (revisedSizeDelta < 0 && _existingPosition.positionSizeE30 > 0);
      bool isClosePosition = !vars.isNewPosition && (isDecreaseShort || isDecreaseLong);
      if (isClosePosition) {
        tradeService.decreasePosition({
          _account: vars.order.account,
          _subAccountId: vars.order.subAccountId,
          _marketIndex: vars.order.marketIndex,
          _positionSizeE30ToDecrease: HMXLib.min(
            HMXLib.abs(revisedSizeDelta),
            HMXLib.abs(_existingPosition.positionSizeE30)
          ),
          _tpToken: vars.order.tpToken,
          _limitPriceE30: 0
        });
      } else {
        // Do nothing if the size delta is wrong for reduce-only
      }
    } else {
      if (revisedSizeDelta > 0) {
        // BUY
        if (vars.isNewPosition || vars.positionIsLong) {
          // New position and Long position
          // just increase position when BUY
          tradeService.increasePosition({
            _primaryAccount: vars.order.account,
            _subAccountId: vars.order.subAccountId,
            _marketIndex: vars.order.marketIndex,
            _sizeDelta: revisedSizeDelta,
            _limitPriceE30: 0
          });
        } else {
          bool _flipSide = revisedSizeDelta > (-_existingPosition.positionSizeE30);
          if (_flipSide) {
            // Flip the position
            // Fully close Short position
            tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(-_existingPosition.positionSizeE30),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: 0
            });
            // Flip it to Long position
            tradeService.increasePosition({
              _primaryAccount: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _sizeDelta: revisedSizeDelta + _existingPosition.positionSizeE30,
              _limitPriceE30: 0
            });
          } else {
            // Not flip
            tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(revisedSizeDelta),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: 0
            });
          }
        }
      } else if (revisedSizeDelta < 0) {
        // SELL
        if (vars.isNewPosition || !vars.positionIsLong) {
          // New position and Short position
          // just increase position when SELL
          tradeService.increasePosition({
            _primaryAccount: vars.order.account,
            _subAccountId: vars.order.subAccountId,
            _marketIndex: vars.order.marketIndex,
            _sizeDelta: revisedSizeDelta,
            _limitPriceE30: 0
          });
        } else if (vars.positionIsLong) {
          bool _flipSide = (-revisedSizeDelta) > _existingPosition.positionSizeE30;
          if (_flipSide) {
            // Flip the position
            // Fully close Long position
            tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(_existingPosition.positionSizeE30),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: 0
            });
            // Flip it to Short position
            tradeService.increasePosition({
              _primaryAccount: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _sizeDelta: revisedSizeDelta + _existingPosition.positionSizeE30,
              _limitPriceE30: 0
            });
          } else {
            // Not flip
            tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(-revisedSizeDelta),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: 0
            });
          }
        }
      }
    }

    _existingPosition = PerpStorage(tradeService.perpStorage()).getPositionById(vars.positionId);
    _isFullClose = _existingPosition.positionSizeE30 == 0;
  }

  function setLimit(
    uint256[] calldata _marketIndexes,
    uint256[] calldata _positionSizeLimits,
    uint256[] calldata _tradeSizeLimits
  ) external onlyOwner {
    require(
      _marketIndexes.length == _positionSizeLimits.length && _positionSizeLimits.length == _tradeSizeLimits.length,
      "length not match"
    );
    uint256 _len = _marketIndexes.length;
    for (uint256 i = 0; i < _len; ) {
      positionSizeLimitOf[_marketIndexes[i]] = _positionSizeLimits[i];
      tradeSizeLimitOf[_marketIndexes[i]] = _tradeSizeLimits[i];

      emit LogSetLimit(_marketIndexes[i], _positionSizeLimits[i], _tradeSizeLimits[i]);

      unchecked {
        ++i;
      }
    }
  }

  function setWhitelistedCaller(address _whitelistedCaller) external onlyOwner {
    emit LogSetWhitelistedCaller(whitelistedCaller, _whitelistedCaller);
    whitelistedCaller = _whitelistedCaller;
  }
}
