// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// interfaces
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { OracleMiddleware } from "@hmx/oracles/OracleMiddleware.sol";
// libs
import { SqrtX96Codec } from "@hmx/libraries/SqrtX96Codec.sol";
import { TickMath } from "@hmx/libraries/TickMath.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";

contract OrderReader {
  IConfigStorage immutable configStorage;
  ILimitTradeHandler immutable limitTradeHandler;
  OracleMiddleware immutable oracleMiddleware;
  IPerpStorage immutable perpStorage;

  constructor(address _configStorage, address _perpStorage, address _oracleMiddleware, address _limitTradeHandler) {
    configStorage = IConfigStorage(_configStorage);
    perpStorage = IPerpStorage(_perpStorage);
    limitTradeHandler = ILimitTradeHandler(_limitTradeHandler);
    oracleMiddleware = OracleMiddleware(_oracleMiddleware);
  }

  struct ExecutableOrderVars {
    ILimitTradeHandler.LimitOrder[] orders;
    bool[] isInValidMarket;
    ILimitTradeHandler.LimitOrder[] executableOrders;
    IConfigStorage.MarketConfig[] marketConfigs;
    uint256[] prices;
    uint128 ordersCount;
    uint64 startIndex;
    uint64 endIndex;
  }

  /// @notice Get executable limit orders.
  /// @param _limit The maximum number of executable orders to retrieve.
  /// @param _offset The offset for fetching executable orders.
  /// @param _prices An array of prices corresponding to the market indices.
  /// @param _shouldInverts An array of boolean values indicating whether to invert prices for the markets.
  /// @return executableOrders An array of executable limit orders that meet the criteria.
  function getExecutableOrders(
    uint64 _limit,
    uint64 _offset,
    uint64[] memory _prices,
    bool[] memory _shouldInverts
  ) external view returns (ILimitTradeHandler.LimitOrder[] memory) {
    ExecutableOrderVars memory vars;
    // get active orders
    vars.orders = limitTradeHandler.getLimitActiveOrders(_limit, _offset);
    vars.ordersCount = uint128(limitTradeHandler.activeLimitOrdersCount());
    vars.startIndex = _offset;
    vars.endIndex = _offset + _limit;
    if (vars.startIndex > vars.ordersCount) return vars.executableOrders;
    if (vars.endIndex > vars.ordersCount) {
      vars.endIndex = uint64(vars.ordersCount);
    }
    // get merket configs
    vars.marketConfigs = configStorage.getMarketConfigs();
    uint256 marketLength = vars.marketConfigs.length;
    uint256 len = vars.marketConfigs.length;
    vars.isInValidMarket = new bool[](len);
    for (uint256 i; i < len; i++) {
      // check active merket
      if (!vars.marketConfigs[i].active) {
        vars.isInValidMarket[i] = true;
        continue;
      }
      // check merket status
      if (oracleMiddleware.marketStatus(vars.marketConfigs[i].assetId) != 2) {
        vars.isInValidMarket[i] = true;
        continue;
      }
    }

    len = _prices.length;
    vars.prices = new uint256[](len);
    for (uint256 i = 0; i < len; i++) {
      vars.prices[i] = _convertPrice(_prices[i], _shouldInverts[i]);
    }

    vars.executableOrders = new ILimitTradeHandler.LimitOrder[](vars.endIndex - vars.startIndex);
    ILimitTradeHandler.LimitOrder memory _order;
    address _subAccount;
    bytes32 _positionId;
    IPerpStorage.Position memory _position;
    IPerpStorage.Market memory _market;
    len = vars.orders.length;
    for (uint256 i; i < len; i++) {
      _order = vars.orders[i];
      _subAccount = _getSubAccount(_order.account, _order.subAccountId);
      _positionId = _getPositionId(_subAccount, _order.marketIndex);
      _position = perpStorage.getPositionById(_positionId);
      {
        if (_order.marketIndex >= marketLength) {
          continue;
        }
        if (vars.isInValidMarket[_order.marketIndex]) {
          continue;
        }
        // validate price
        if (
          !_validateExecutableOrder(_order.triggerPrice, _order.triggerAboveThreshold, vars.prices[_order.marketIndex])
        ) {
          continue;
        }
        // check Tp/Sl order
        bool isTpSlOrder = _isTpSlOrder(_order);
        if (isTpSlOrder) {
          // check position
          if (_isPositionClose(_position)) {
            continue;
          }
        }
        _market = perpStorage.getMarketByIndex(_order.marketIndex);
        if (!isTpSlOrder && !_isUnderMaxOI(_market, vars.marketConfigs[_order.marketIndex], _position, _order)) {
          continue;
        }

        if (
          _isUnderMinProfitDuration(
            _position,
            _market,
            vars.marketConfigs[_order.marketIndex],
            !isTpSlOrder ? _order.sizeDelta : -_position.positionSizeE30,
            vars.prices[_order.marketIndex]
          )
        ) {
          continue;
        }
      }
      vars.executableOrders[i] = _order;
    }

    return vars.executableOrders;
  }

  function _validateExecutableOrder(
    uint256 _triggerPrice,
    bool _triggerAboveThreshold,
    uint256 _price
  ) internal pure returns (bool) {
    return _triggerAboveThreshold ? _price > _triggerPrice : _price < _triggerPrice;
  }

  function _isTpSlOrder(ILimitTradeHandler.LimitOrder memory _order) internal pure returns (bool) {
    return _order.reduceOnly && (_order.sizeDelta == type(int256).max || _order.sizeDelta == type(int256).min);
  }

  function _isPositionClose(IPerpStorage.Position memory _position) internal pure returns (bool) {
    return _position.primaryAccount == address(0);
  }

  function _isUnderMinProfitDuration(
    IPerpStorage.Position memory _position,
    IPerpStorage.Market memory _market,
    IConfigStorage.MarketConfig memory _marketConfig,
    int256 _sizeDelta,
    uint256 _oraclePrice
  ) internal view returns (bool) {
    uint256 _minProfitDuration = configStorage.getStepMinProfitDuration(
      _position.marketIndex,
      _position.lastIncreaseSize
    );
    uint256 _markPrice = _calculateAdaptivePrice(
      _market,
      _marketConfig.fundingRate.maxSkewScaleUSD,
      _oraclePrice,
      _position.positionSizeE30,
      _sizeDelta
    );

    (bool _isProfit, ) = _getDelta(
      HMXLib.abs(_position.positionSizeE30),
      _position.positionSizeE30 > 0,
      _markPrice,
      _position.avgEntryPriceE30
    );

    if (!_isProfit) {
      return false;
    } else {
      return block.timestamp < _position.lastIncreaseTimestamp + _minProfitDuration;
    }
  }

  function _isUnderMaxOI(
    IPerpStorage.Market memory _market,
    IConfigStorage.MarketConfig memory _marketConfig,
    IPerpStorage.Position memory _position,
    ILimitTradeHandler.LimitOrder memory _order
  ) internal pure returns (bool) {
    bool _isLong = _position.positionSizeE30 > 0;
    if (_isLong) {
      return int256(_marketConfig.maxLongPositionSize) > int256(_market.longPositionSize) + _order.sizeDelta;
    } else {
      return int256(_marketConfig.maxShortPositionSize) > int256(_market.shortPositionSize) - _order.sizeDelta;
    }
  }

  function _getSubAccount(address _primary, uint8 _subAccountId) internal pure returns (address _subAccount) {
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }

  function _getPositionId(address _subAccount, uint256 _marketIndex) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_subAccount, _marketIndex));
  }

  function _convertPrice(uint64 _priceE8, bool _shouldInvert) internal pure returns (uint256) {
    uint160 _priceE18 = SqrtX96Codec.encode(uint(_priceE8) * 10 ** uint32(10));
    int24 _tick = TickMath.getTickAtSqrtRatio(_priceE18);
    uint160 _sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
    uint256 _spotPrice = SqrtX96Codec.decode(_sqrtPriceX96);
    uint256 _priceE30 = _spotPrice * 1e12;

    if (!_shouldInvert) return _priceE30;

    if (_priceE30 == 0) return 0;
    return 10 ** 60 / _priceE30;
  }

  function _calculateAdaptivePrice(
    IPerpStorage.Market memory _market,
    uint256 _maxSkewScale,
    uint256 _oraclePrice,
    int256 _positionSize,
    int256 _sizeDelta
  ) private pure returns (uint256 _nextClosePrice) {
    if (_maxSkewScale == 0) return _oraclePrice;

    // new position size    = position size + size delta
    // new market skew      = long position size - short position size + size delta
    // premium before       = new market skew / max scale skew
    // premium after        = (new market skew - new position size) / max scale skew
    // premium              = (premium after + premium after) / 2
    // next close price     = oracle price * (1 + premium)

    // Example:
    // Given
    //    - max scale       = 1000000 USD
    //    - market skew     = 2000 USD
    //    - price           = 100 USD
    //    - position size   = 1000 USD
    //    - decrease size   = 300 USD
    //    - remaining size  = 500 USD
    //    - entry price     = 100.05 USD
    //    - close price     = 100.15 USD
    //    - pnl             = 1000 * (100.15 - 100.05) / 100.05 = 0.999500249875062468765617191404 USD
    //    - realized pnl    = 300 * (100.15 - 100.05) / 100.05 = 0.299850074962518740629685157421 USD
    //    - unrealized pnl  = 0.999500249875062468765617191404 - 0.299850074962518740629685157421
    //                      = 0.699650174912543728135932033983
    // Then
    //    - premium before      = 2000 - 300 = 1700 / 1000000 = 0.0017
    //    - premium after       = 2000 - 1000 = 1000 / 1000000 = 0.001
    //    - new premium         = 0.0017 + 0.001 = 0.0027 / 2 = 0.00135
    //    - next close price    = 100 * (1 + 0.00135) = 100.135 USD

    int256 _newPositionSize = _positionSize + _sizeDelta;

    int256 _newMarketSkew = int256(_market.longPositionSize) - int256(_market.shortPositionSize) + _sizeDelta;

    int256 _premiumBefore = (_newMarketSkew * 1e30) / int256(_maxSkewScale);
    int256 _premiumAfter = ((_newMarketSkew - _newPositionSize) * 1e30) / int256(_maxSkewScale);

    int256 _premium = (_premiumBefore + _premiumAfter) / 2;

    if (_premium > 0) {
      return (_oraclePrice * (1e30 + uint256(_premium))) / 1e30;
    } else {
      return (_oraclePrice * (1e30 - uint256(-_premium))) / 1e30;
    }
  }

  function _getDelta(
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice
  ) internal pure returns (bool, uint256) {
    // Check for invalid input: averagePrice cannot be zero.
    if (_averagePrice == 0) return (false, 0);

    // Calculate the difference between the average price and the fixed price.
    uint256 _priceDelta;
    unchecked {
      _priceDelta = _averagePrice > _markPrice ? _averagePrice - _markPrice : _markPrice - _averagePrice;
    }

    // Calculate the delta, adjusted for the size of the order.
    uint256 _delta = (_size * _priceDelta) / _averagePrice;

    // Determine if the position is profitable or not based on the averagePrice and the mark price.
    bool _isProfit;
    if (_isLong) {
      _isProfit = _markPrice > _averagePrice;
    } else {
      _isProfit = _markPrice < _averagePrice;
    }

    // Return the values of isProfit and delta.
    return (_isProfit, _delta);
  }
}
