// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// base
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol";

// contracts
import { OracleMiddleware } from "@hmx/oracles/OracleMiddleware.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";
import { FullMath } from "@hmx/libraries/FullMath.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { TradeHelper } from "@hmx/helpers/TradeHelper.sol";

// Interfaces
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

contract Calculator is OwnableUpgradeable, ICalculator {
  using SafeCastUpgradeable for int256;
  using SafeCastUpgradeable for uint256;
  using FullMath for uint256;

  uint32 internal constant BPS = 1e4;
  uint64 internal constant ETH_PRECISION = 1e18;
  uint64 internal constant RATE_PRECISION = 1e18;

  /**
   * Events
   */
  event LogSetOracle(address indexed oldOracle, address indexed newOracle);
  event LogSetVaultStorage(address indexed oldVaultStorage, address indexed vaultStorage);
  event LogSetConfigStorage(address indexed oldConfigStorage, address indexed configStorage);
  event LogSetPerpStorage(address indexed oldPerpStorage, address indexed perpStorage);
  event LogSetTradeHelper(address indexed oldTradeHelper, address indexed tradeHelper);

  /**
   * States
   */
  address public oracle;
  address public vaultStorage;
  address public configStorage;
  address public perpStorage;
  address public tradeHelper;

  function initialize(
    address _oracle,
    address _vaultStorage,
    address _perpStorage,
    address _configStorage
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    if (
      _oracle == address(0) || _vaultStorage == address(0) || _perpStorage == address(0) || _configStorage == address(0)
    ) revert ICalculator_InvalidAddress();

    // Sanity check
    PerpStorage(_perpStorage).getGlobalState();
    VaultStorage(_vaultStorage).hlpLiquidityDebtUSDE30();
    ConfigStorage(_configStorage).getLiquidityConfig();

    oracle = _oracle;
    vaultStorage = _vaultStorage;
    configStorage = _configStorage;
    perpStorage = _perpStorage;
  }

  /// @notice getAUME30
  /// @param _isMaxPrice Use Max or Min Price
  /// @return aum HLP Value in E30 format
  function getAUME30(bool _isMaxPrice) external view returns (uint256 aum) {
    // SLOAD
    VaultStorage _vaultStorage = VaultStorage(vaultStorage);

    // hlpAUM = value of all asset + pnlShort + pnlLong + pendingBorrowingFee + fundingFeeDebt
    uint256 pendingBorrowingFeeE30 = _getPendingBorrowingFeeE30();
    uint256 borrowingFeeDebt = _vaultStorage.globalBorrowingFeeDebt();
    int256 pnlE30 = _getGlobalPNLE30();

    uint256 lossDebt = _vaultStorage.globalLossDebt();
    aum =
      _getHLPValueE30(_isMaxPrice) +
      pendingBorrowingFeeE30 +
      borrowingFeeDebt +
      lossDebt +
      _vaultStorage.hlpLiquidityDebtUSDE30();
    if (pnlE30 < 0) {
      uint256 _pnl = uint256(-pnlE30);
      if (aum < _pnl) return 0;
      aum -= _pnl;
    } else {
      aum += uint256(pnlE30);
    }
  }

  function getGlobalPNLE30() external view returns (int256) {
    return _getGlobalPNLE30();
  }

  /// @notice getPendingBorrowingFeeE30 This function calculates the total pending borrowing fee from all asset classes.
  /// @return total pending borrowing fee in e30 format
  function getPendingBorrowingFeeE30() external view returns (uint256) {
    return _getPendingBorrowingFeeE30();
  }

  /// @notice _getPendingBorrowingFeeE30 This function calculates the total pending borrowing fee from all asset classes.
  /// @return total pending borrowing fee in e30 format
  function _getPendingBorrowingFeeE30() internal view returns (uint256) {
    // SLOAD
    PerpStorage _perpStorage = PerpStorage(perpStorage);
    uint256 _len = ConfigStorage(configStorage).getAssetClassConfigsLength();

    // Get the HLP TVL.
    uint256 _hlpTVL = _getHLPValueE30(false);
    uint256 _pendingBorrowingFee; // sum from each asset class
    for (uint256 i; i < _len; ) {
      PerpStorage.AssetClass memory _assetClassState = _perpStorage.getAssetClassByIndex(i);

      uint256 _borrowingFeeE30 = (_getNextBorrowingRate(uint8(i), _hlpTVL) * _assetClassState.reserveValueE30) /
        RATE_PRECISION;

      // Formula:
      // pendingBorrowingFee = (sumBorrowingFeeE30 - sumSettledBorrowingFeeE30) + latestBorrowingFee
      if (_assetClassState.sumBorrowingFeeE30 > _assetClassState.sumSettledBorrowingFeeE30) {
        _pendingBorrowingFee +=
          (_assetClassState.sumBorrowingFeeE30 - _assetClassState.sumSettledBorrowingFeeE30) +
          _borrowingFeeE30;
      } else {
        if (_assetClassState.sumSettledBorrowingFeeE30 - _assetClassState.sumBorrowingFeeE30 > 1e30) {
          revert ICalculator_InvalidBorrowingFee();
        }
        _pendingBorrowingFee += _borrowingFeeE30;
      }

      unchecked {
        ++i;
      }
    }

    return _pendingBorrowingFee;
  }

  /// @notice GetHLPValue in E30
  /// @param _isMaxPrice Use Max or Min Price
  /// @return HLP Value
  function getHLPValueE30(bool _isMaxPrice) external view returns (uint256) {
    return _getHLPValueE30(_isMaxPrice);
  }

  /// @notice GetHLPValue in E30
  /// @param _isMaxPrice Use Max or Min Price
  /// @return assetValue HLP Value
  function _getHLPValueE30(bool _isMaxPrice) internal view returns (uint256 assetValue) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    bytes32[] memory _hlpAssetIds = _configStorage.getHlpAssetIds();
    uint256 _len = _hlpAssetIds.length;

    unchecked {
      for (uint256 i; i < _len; ++i) {
        assetValue += _getHLPUnderlyingAssetValueE30(_hlpAssetIds[i], _configStorage, _isMaxPrice);
      }
    }
  }

  /// @notice Get HLP underlying asset value in E30
  /// @param _underlyingAssetId the underlying asset id, the one we want to find the value
  /// @param _configStorage config storage
  /// @param _isMaxPrice Use Max or Min Price
  /// @return value HLP Value
  function _getHLPUnderlyingAssetValueE30(
    bytes32 _underlyingAssetId,
    ConfigStorage _configStorage,
    bool _isMaxPrice
  ) internal view returns (uint256 value) {
    VaultStorage _vs = VaultStorage(vaultStorage);
    ConfigStorage.AssetConfig memory _assetConfig = _configStorage.getAssetConfig(_underlyingAssetId);

    uint256 _totalAssets = _vs.hlpLiquidity(_assetConfig.tokenAddress) +
      _vs.hlpLiquidityOnHold(_assetConfig.tokenAddress) -
      _vs.getPendingRewardDebt(_assetConfig.tokenAddress);
    if (_totalAssets == 0) return 0;

    (uint256 _priceE30, ) = OracleMiddleware(oracle).unsafeGetLatestPrice(_underlyingAssetId, _isMaxPrice);

    value = (_totalAssets * _priceE30) / (10 ** _assetConfig.decimals);
  }

  /// @notice getHLPPrice in e18 format
  /// @param _aum aum in HLP
  /// @param _hlpSupply Total Supply of HLP token
  /// @return HLP Price in e18
  function getHLPPrice(uint256 _aum, uint256 _hlpSupply) external pure returns (uint256) {
    if (_hlpSupply == 0) return 0;
    return _aum / _hlpSupply;
  }

  /// @dev Computes the global market PnL in E30 format by iterating through all the markets.
  /// @return The total PnL in E30 format, which is the sum of long and short positions' PnLs.
  function _getGlobalPNLE30() internal view returns (int256) {
    // SLOAD
    ConfigStorage _configStorage = ConfigStorage(configStorage);
    PerpStorage _perpStorage = PerpStorage(perpStorage);
    OracleMiddleware _oracle = OracleMiddleware(oracle);

    int256 totalPnlLong = 0;
    int256 totalPnlShort = 0;
    uint256 _len = _configStorage.getMarketConfigsLength();

    for (uint256 i = 0; i < _len; ) {
      ConfigStorage.MarketConfig memory _marketConfig = _configStorage.getMarketConfigByIndex(i);
      PerpStorage.Market memory _market = _perpStorage.getMarketByIndex(i);

      int256 _pnlLongE30 = 0;
      int256 _pnlShortE30 = 0;
      (uint256 priceE30, ) = _oracle.unsafeGetLatestPrice(_marketConfig.assetId, false);

      if (_market.longPositionSize > 0) {
        _pnlLongE30 = _getGlobalMarketPnl(
          priceE30,
          (int(_market.longPositionSize) - int(_market.shortPositionSize)),
          _marketConfig.fundingRate.maxSkewScaleUSD,
          int(_market.longAccumSE),
          _market.longAccumS2E,
          _market.longPositionSize,
          true
        );
      }
      if (_market.shortPositionSize > 0) {
        _pnlShortE30 = _getGlobalMarketPnl(
          priceE30,
          (int(_market.longPositionSize) - int(_market.shortPositionSize)),
          _marketConfig.fundingRate.maxSkewScaleUSD,
          int(_market.shortAccumSE),
          _market.shortAccumS2E,
          _market.shortPositionSize,
          false
        );
      }

      unchecked {
        ++i;
        totalPnlLong += _pnlLongE30;
        totalPnlShort += _pnlShortE30;
      }
    }

    return totalPnlLong + totalPnlShort;
  }

  /// @notice getMintAmount in e18 format
  /// @param _aumE30 aum in HLP E30
  /// @param _totalSupply HLP total supply
  /// @param _value value in USD e30
  /// @return mintAmount in e18 format
  function getMintAmount(uint256 _aumE30, uint256 _totalSupply, uint256 _value) external pure returns (uint256) {
    return _aumE30 == 0 ? _value / 1e12 : (_value * _totalSupply) / _aumE30;
  }

  function convertTokenDecimals(
    uint256 fromTokenDecimals,
    uint256 toTokenDecimals,
    uint256 amount
  ) external pure returns (uint256) {
    return (amount * 10 ** toTokenDecimals) / 10 ** fromTokenDecimals;
  }

  function getAddLiquidityFeeBPS(
    address _token,
    uint256 _tokenValueE30,
    ConfigStorage _configStorage
  ) external view returns (uint32) {
    if (!_configStorage.getLiquidityConfig().dynamicFeeEnabled) {
      return _configStorage.getLiquidityConfig().depositFeeRateBPS;
    }

    return
      _getFeeBPS(
        _tokenValueE30,
        _getHLPUnderlyingAssetValueE30(_configStorage.tokenAssetIds(_token), _configStorage, false),
        _getHLPValueE30(false),
        _configStorage.getLiquidityConfig(),
        _configStorage.getAssetHlpTokenConfigByToken(_token),
        LiquidityDirection.ADD
      );
  }

  function getRemoveLiquidityFeeBPS(
    address _token,
    uint256 _tokenValueE30,
    ConfigStorage _configStorage
  ) external view returns (uint32) {
    if (!_configStorage.getLiquidityConfig().dynamicFeeEnabled) {
      return _configStorage.getLiquidityConfig().withdrawFeeRateBPS;
    }

    return
      _getFeeBPS(
        _tokenValueE30,
        _getHLPUnderlyingAssetValueE30(_configStorage.tokenAssetIds(_token), _configStorage, true),
        _getHLPValueE30(true),
        _configStorage.getLiquidityConfig(),
        _configStorage.getAssetHlpTokenConfigByToken(_token),
        LiquidityDirection.REMOVE
      );
  }

  function _getFeeBPS(
    uint256 _value, //e30
    uint256 _liquidityUSD, //e30
    uint256 _totalLiquidityUSD, //e30
    ConfigStorage.LiquidityConfig memory _liquidityConfig,
    ConfigStorage.HLPTokenConfig memory _hlpTokenConfig,
    LiquidityDirection direction
  ) internal pure returns (uint32) {
    uint32 _feeBPS = direction == LiquidityDirection.ADD
      ? _liquidityConfig.depositFeeRateBPS
      : _liquidityConfig.withdrawFeeRateBPS;
    uint32 _taxBPS = _liquidityConfig.taxFeeRateBPS;
    uint256 _totalTokenWeight = _liquidityConfig.hlpTotalTokenWeight;

    uint256 startValue = _liquidityUSD;
    uint256 nextValue = startValue + _value;
    if (direction == LiquidityDirection.REMOVE) nextValue = _value > startValue ? 0 : startValue - _value;

    uint256 targetValue = _getTargetValue(_totalLiquidityUSD, _hlpTokenConfig.targetWeight, _totalTokenWeight);

    if (targetValue == 0) return _feeBPS;

    uint256 startTargetDiff = startValue > targetValue ? startValue - targetValue : targetValue - startValue;
    uint256 nextTargetDiff = nextValue > targetValue ? nextValue - targetValue : targetValue - nextValue;

    // nextValue moves closer to the targetValue -> positive case;
    // Should apply rebate.
    if (nextTargetDiff < startTargetDiff) {
      uint32 rebateBPS = uint32((_taxBPS * startTargetDiff) / targetValue);
      return rebateBPS > _feeBPS ? 0 : _feeBPS - rebateBPS;
    }

    // _nextWeight represented 18 precision
    uint256 _nextWeight = (nextValue * ETH_PRECISION) / (_totalLiquidityUSD + _value);
    uint256 withdrawalWeightDiff = _hlpTokenConfig.targetWeight > _hlpTokenConfig.maxWeightDiff
      ? _hlpTokenConfig.targetWeight - _hlpTokenConfig.maxWeightDiff
      : 0;
    if (
      _nextWeight > _hlpTokenConfig.targetWeight + _hlpTokenConfig.maxWeightDiff || _nextWeight < withdrawalWeightDiff
    ) {
      revert ICalculator_PoolImbalance();
    }

    // If not then -> negative impact to the pool.
    // Should apply tax.
    uint256 midDiff = (startTargetDiff + nextTargetDiff) / 2;
    if (midDiff > targetValue) {
      midDiff = targetValue;
    }
    _taxBPS = uint32((_taxBPS * midDiff) / targetValue);

    return uint32(_feeBPS + _taxBPS);
  }

  /// @notice get settlement fee rate
  /// @param _token - token
  /// @param _liquidityUsdDelta - withdrawal amount
  /// @return _settlementFeeRate in e18 format
  function getSettlementFeeRate(
    address _token,
    uint256 _liquidityUsdDelta
  ) external view returns (uint256 _settlementFeeRate) {
    // SLOAD
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    // usd debt
    uint256 _tokenLiquidityUsd = _getHLPUnderlyingAssetValueE30(
      _configStorage.tokenAssetIds(_token),
      _configStorage,
      false
    );
    if (_tokenLiquidityUsd == 0) return 0;

    // total usd debt

    uint256 _totalLiquidityUsd = _getHLPValueE30(false);
    ConfigStorage.LiquidityConfig memory _liquidityConfig = _configStorage.getLiquidityConfig();

    // target value = total usd debt * target weight ratio (targe weigh / total weight);

    uint256 _targetUsd = (_totalLiquidityUsd * _configStorage.getAssetHlpTokenConfigByToken(_token).targetWeight) /
      _liquidityConfig.hlpTotalTokenWeight;

    if (_targetUsd == 0) return 0;

    // next value
    uint256 _nextUsd = _tokenLiquidityUsd - _liquidityUsdDelta;

    // current target diff
    uint256 _currentTargetDiff;
    uint256 _nextTargetDiff;
    unchecked {
      _currentTargetDiff = _tokenLiquidityUsd > _targetUsd
        ? _tokenLiquidityUsd - _targetUsd
        : _targetUsd - _tokenLiquidityUsd;
      // next target diff
      _nextTargetDiff = _nextUsd > _targetUsd ? _nextUsd - _targetUsd : _targetUsd - _nextUsd;
    }

    if (_nextTargetDiff < _currentTargetDiff) return 0;

    // settlement fee rate = (next target diff + current target diff / 2) * base tax fee / target usd
    return
      (((_nextTargetDiff + _currentTargetDiff) / 2) * _liquidityConfig.taxFeeRateBPS * ETH_PRECISION) /
      _targetUsd /
      BPS;
  }

  /// @notice Get target value of a token in HLP according to its target weight
  /// @param totalLiquidityUSD total liquidity USD of the whole HLP
  /// @param tokenWeight the token weight of this token
  /// @param totalTokenWeight the total token weight of HLP
  function _getTargetValue(
    uint256 totalLiquidityUSD, //e30
    uint256 tokenWeight, //e18
    uint256 totalTokenWeight // 1e18
  ) internal pure returns (uint256) {
    if (totalLiquidityUSD == 0) return 0;

    return (totalLiquidityUSD * tokenWeight) / totalTokenWeight;
  }

  /**
   * Setter functions
   */

  /// @notice Set new Oracle contract address.
  /// @param _oracle New Oracle contract address.
  function setOracle(address _oracle) external onlyOwner {
    if (_oracle == address(0)) revert ICalculator_InvalidAddress();
    OracleMiddleware(_oracle).isUpdater(address(this));
    emit LogSetOracle(oracle, _oracle);
    oracle = _oracle;
  }

  /// @notice Set new VaultStorage contract address.
  /// @param _vaultStorage New VaultStorage contract address.
  function setVaultStorage(address _vaultStorage) external onlyOwner {
    if (_vaultStorage == address(0)) revert ICalculator_InvalidAddress();
    VaultStorage(_vaultStorage).hlpLiquidityDebtUSDE30();
    emit LogSetVaultStorage(vaultStorage, _vaultStorage);
    vaultStorage = _vaultStorage;
  }

  /// @notice Set new ConfigStorage contract address.
  /// @param _configStorage New ConfigStorage contract address.
  function setConfigStorage(address _configStorage) external onlyOwner {
    if (_configStorage == address(0)) revert ICalculator_InvalidAddress();
    ConfigStorage(_configStorage).getLiquidityConfig();
    emit LogSetConfigStorage(configStorage, _configStorage);
    configStorage = _configStorage;
  }

  /// @notice Set new PerpStorage contract address.
  /// @param _perpStorage New PerpStorage contract address.
  function setPerpStorage(address _perpStorage) external onlyOwner {
    if (_perpStorage == address(0)) revert ICalculator_InvalidAddress();
    PerpStorage(_perpStorage).getGlobalState();
    emit LogSetPerpStorage(perpStorage, _perpStorage);
    perpStorage = _perpStorage;
  }

  function setTradeHelper(address _tradeHelper) external onlyOwner {
    if (_tradeHelper == address(0)) revert ICalculator_InvalidAddress();
    TradeHelper(_tradeHelper).maxAdaptiveFeeBps();
    emit LogSetTradeHelper(_tradeHelper, tradeHelper);
    tradeHelper = _tradeHelper;
  }

  /// @notice Calculate for value on trader's account including Equity, IMR and MMR.
  /// @dev Equity = Sum(collateral tokens' Values) + Sum(unrealized PnL) - Unrealized Borrowing Fee - Unrealized Funding Fee
  /// @param _subAccount Trader account's address.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _equityValueE30 Total equity of trader's account.
  function getEquity(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (int256 _equityValueE30) {
    return _getEquity(_subAccount, _limitPriceE30, _limitAssetId, new bytes32[](0), new uint256[](0));
  }

  /// @notice Calculate equity value of a given account. Same as above but allow injected price.
  /// @dev This function is supposed to be used in view function only.
  /// @param _subAccount Trader's account address
  /// @param _injectedAssetIds AssetIds to be used for price ref.
  /// @param _injectedPrices Prices to be used for calculate equity
  function getEquityWithInjectedPrices(
    address _subAccount,
    bytes32[] memory _injectedAssetIds,
    uint256[] memory _injectedPrices
  ) external view returns (int256 _equityValueE30) {
    if (_injectedAssetIds.length != _injectedPrices.length) revert ICalculator_InvalidArray();
    return _getEquity(_subAccount, 0, 0, _injectedAssetIds, _injectedPrices);
  }

  /// @notice Perform the actual equity calculation.
  /// @param _subAccount The trader's account addresss to be calculate.
  /// @param _limitPriceE30 Price to be overwritten for a specific assetId.
  /// @param _limitAssetId Asset Id that its price will need to be overwritten.
  /// @param _injectedAssetIds AssetIds to be used for price ref.
  /// @param _injectedPrices Prices to be used for calculate equity
  function _getEquity(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId,
    bytes32[] memory _injectedAssetIds,
    uint256[] memory _injectedPrices
  ) internal view returns (int256 _equityValueE30) {
    VaultStorage _vaultStorage = VaultStorage(vaultStorage);

    // Calculate collateral tokens' value on trader's sub account
    uint256 _collateralValueE30 = _getCollateralValue(
      _subAccount,
      _limitPriceE30,
      _limitAssetId,
      _injectedAssetIds,
      _injectedPrices
    );

    // Calculate unrealized PnL and unrealized fee
    (int256 _unrealizedPnlValueE30, int256 _unrealizedFeeValueE30) = _getUnrealizedPnlAndFee(
      _subAccount,
      _limitPriceE30,
      _limitAssetId,
      _injectedAssetIds,
      _injectedPrices
    );

    // Calculate equity
    _equityValueE30 += int256(_collateralValueE30);
    _equityValueE30 += _unrealizedPnlValueE30;
    _equityValueE30 -= _unrealizedFeeValueE30;

    _equityValueE30 -= int256(_vaultStorage.tradingFeeDebt(_subAccount));
    _equityValueE30 -= int256(_vaultStorage.borrowingFeeDebt(_subAccount));
    _equityValueE30 -= int256(_vaultStorage.fundingFeeDebt(_subAccount));
    _equityValueE30 -= int256(_vaultStorage.lossDebt(_subAccount));

    return _equityValueE30;
  }

  struct GetUnrealizedPnlAndFee {
    ConfigStorage configStorage;
    PerpStorage perpStorage;
    OracleMiddleware oracle;
    PerpStorage.Position position;
    uint256 absSize;
    bool isLong;
    uint256 priceE30;
    bool isProfit;
    uint256 delta;
  }

  struct GetCollateralValue {
    VaultStorage vaultStorage;
    ConfigStorage configStorage;
    OracleMiddleware oracle;
    uint8 decimals;
    uint256 amount;
    uint256 priceE30;
    bytes32 tokenAssetId;
    uint32 collateralFactorBPS;
    address[] traderTokens;
  }

  /// @notice Calculate unrealized PnL from trader's sub account.
  /// @dev This unrealized pnl deducted by collateral factor.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _unrealizedPnlE30 PnL value after deducted by collateral factor.
  function getUnrealizedPnlAndFee(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (int256 _unrealizedPnlE30, int256 _unrealizedFeeE30) {
    return _getUnrealizedPnlAndFee(_subAccount, _limitPriceE30, _limitAssetId, new bytes32[](0), new uint256[](0));
  }

  function _getUnrealizedPnlAndFee(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId,
    bytes32[] memory _injectedAssetIds,
    uint256[] memory _injectedPrices
  ) internal view returns (int256 _unrealizedPnlE30, int256 _unrealizedFeeE30) {
    GetUnrealizedPnlAndFee memory _var;
    // SLOADs
    _var.configStorage = ConfigStorage(configStorage);
    _var.perpStorage = PerpStorage(perpStorage);
    _var.oracle = OracleMiddleware(oracle);

    // Get all trader's opening positions
    PerpStorage.Position[] memory _positions = _var.perpStorage.getPositionBySubAccount(_subAccount);

    ConfigStorage.MarketConfig memory _marketConfig;
    PerpStorage.Market memory _market;
    uint256 pnlFactorBps = _var.configStorage.pnlFactorBPS();
    uint256 liquidationFee = _var.configStorage.getLiquidationConfig().liquidationFeeUSDE30;

    uint256 _len = _positions.length;
    // Loop through all trader's positions
    for (uint256 i; i < _len; ) {
      _var.position = _positions[i];
      _var.absSize = HMXLib.abs(_var.position.positionSizeE30);
      _var.isLong = _var.position.positionSizeE30 > 0;

      // Get market config according to opening position
      _marketConfig = _var.configStorage.getMarketConfigByIndex(_var.position.marketIndex);
      _market = _var.perpStorage.getMarketByIndex(_var.position.marketIndex);

      if (_injectedAssetIds.length > 0) {
        _var.priceE30 = _getPriceFromInjectedData(_marketConfig.assetId, _injectedAssetIds, _injectedPrices);
        (_var.priceE30, ) = _var.oracle.unsafeGetLatestAdaptivePrice(
          _marketConfig.assetId,
          !_var.isLong, // if current position is SHORT position, then we use max price
          (int(_market.longPositionSize) - int(_market.shortPositionSize)),
          -_var.position.positionSizeE30,
          _marketConfig.fundingRate.maxSkewScaleUSD,
          _var.priceE30
        );

        if (_var.priceE30 == 0) revert ICalculator_InvalidPrice();
      } else {
        // Check to overwrite price
        if (_limitAssetId == _marketConfig.assetId && _limitPriceE30 != 0) {
          _var.priceE30 = _limitPriceE30;
        } else {
          (_var.priceE30, ) = _var.oracle.getLatestAdaptivePrice(
            _marketConfig.assetId,
            !_var.isLong, // if current position is SHORT position, then we use max price
            (int(_market.longPositionSize) - int(_market.shortPositionSize)),
            -_var.position.positionSizeE30,
            _marketConfig.fundingRate.maxSkewScaleUSD,
            0
          );
        }
      }

      {
        // Calculate pnl
        GetDeltaVars2 memory gdVars;
        gdVars.subAccount = HMXLib.getSubAccount(_var.position.primaryAccount, _var.position.subAccountId);
        gdVars.size = _var.absSize;
        gdVars.isLong = _var.isLong;
        gdVars.markPrice = _var.priceE30;
        gdVars.averagePrice = _var.position.avgEntryPriceE30;
        gdVars.lastIncreaseTimestamp = _var.position.lastIncreaseTimestamp;
        gdVars.marketIndex = _var.position.marketIndex;
        gdVars.useMinProfitDuration = false;
        (_var.isProfit, _var.delta) = _getDelta(gdVars);

        if (_var.isProfit) {
          if (_var.delta >= _var.position.reserveValueE30) {
            _var.delta = _var.position.reserveValueE30;
          }
          _unrealizedPnlE30 += int256(_var.delta);
        } else {
          _unrealizedPnlE30 -= int256(_var.delta);
        }
      }

      {
        {
          // Calculate borrowing fee
          uint256 _hlpTVL = _getHLPValueE30(false);
          PerpStorage.AssetClass memory _assetClass = _var.perpStorage.getAssetClassByIndex(_marketConfig.assetClass);
          uint256 _nextBorrowingRate = _getNextBorrowingRate(_marketConfig.assetClass, _hlpTVL);
          _unrealizedFeeE30 += int256(
            _getBorrowingFee(
              _var.position.reserveValueE30,
              _assetClass.sumBorrowingRate + _nextBorrowingRate,
              _var.position.entryBorrowingRate
            )
          );
        }
        {
          // Calculate funding fee
          int256 _proportionalElapsedInDay = int256(proportionalElapsedInDay(_var.position.marketIndex));
          int256 nextFundingRate = _market.currentFundingRate +
            ((_getFundingRateVelocity(_var.position.marketIndex) * _proportionalElapsedInDay) / 1e18);
          int256 lastFundingAccrued = _var.position.lastFundingAccrued;
          int256 currentFundingAccrued = _market.fundingAccrued +
            ((_market.currentFundingRate + nextFundingRate) * _proportionalElapsedInDay) /
            2 /
            1e18;
          _unrealizedFeeE30 += getFundingFee(_var.position.positionSizeE30, currentFundingAccrued, lastFundingAccrued);
        }
        // Calculate trading fee
        _unrealizedFeeE30 += int256(
          _getTradingFee(
            -_var.position.positionSizeE30,
            _marketConfig.decreasePositionFeeRateBPS,
            _var.position.marketIndex
          )
        );
      }

      unchecked {
        ++i;
      }
    }

    if (_len != 0) {
      // Calculate liquidation fee
      _unrealizedFeeE30 += int256(liquidationFee);
    }

    if (_unrealizedPnlE30 > 0) {
      _unrealizedPnlE30 = ((pnlFactorBps * _unrealizedPnlE30.toUint256()) / BPS).toInt256();
    }

    return (_unrealizedPnlE30, _unrealizedFeeE30);
  }

  /// @notice Calculate collateral tokens to value from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _collateralValueE30
  function getCollateralValue(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (uint256 _collateralValueE30) {
    return _getCollateralValue(_subAccount, _limitPriceE30, _limitAssetId, new bytes32[](0), new uint256[](0));
  }

  function _getCollateralValue(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId,
    bytes32[] memory _injectedAssetIds,
    uint256[] memory _injectedPrices
  ) internal view returns (uint256 _collateralValueE30) {
    GetCollateralValue memory _var;

    // SLOADs
    _var.vaultStorage = VaultStorage(vaultStorage);
    _var.configStorage = ConfigStorage(configStorage);
    _var.oracle = OracleMiddleware(oracle);

    // Get list of current depositing tokens on trader's account
    _var.traderTokens = _var.vaultStorage.getTraderTokens(_subAccount);

    // Loop through list of current depositing tokens
    uint256 traderTokenLen = _var.traderTokens.length;
    for (uint256 i; i < traderTokenLen; ) {
      address _token = _var.traderTokens[i];
      ConfigStorage.CollateralTokenConfig memory _collateralTokenConfig = _var.configStorage.getCollateralTokenConfigs(
        _token
      );

      // Get token decimals from ConfigStorage
      _var.decimals = _var.configStorage.getAssetConfigByToken(_token).decimals;

      // Get collateralFactor from ConfigStorage
      _var.collateralFactorBPS = _collateralTokenConfig.collateralFactorBPS;

      // Get current collateral token balance of trader's account
      _var.amount = _var.vaultStorage.traderBalances(_subAccount, _token);

      // Get price from oracle
      _var.tokenAssetId = _var.configStorage.tokenAssetIds(_token);

      if (_injectedAssetIds.length > 0) {
        _var.priceE30 = _getPriceFromInjectedData(_var.tokenAssetId, _injectedAssetIds, _injectedPrices);
        if (_var.priceE30 == 0) revert ICalculator_InvalidPrice();
      } else {
        // Get token asset id from ConfigStorage
        if (_var.tokenAssetId == _limitAssetId && _limitPriceE30 != 0) {
          _var.priceE30 = _limitPriceE30;
        } else {
          (_var.priceE30, ) = _var.oracle.getLatestPrice(
            _var.tokenAssetId,
            false // @note Collateral value always use Min price
          );
        }
      }
      // Calculate accumulative value of collateral tokens
      // collateral value = (collateral amount * price) * collateralFactorBPS
      // collateralFactor 1e4 = 100%
      _collateralValueE30 += (_var.amount * _var.priceE30 * _var.collateralFactorBPS) / ((10 ** _var.decimals) * BPS);

      unchecked {
        ++i;
      }
    }

    return _collateralValueE30;
  }

  /// @notice Calculate Initial Margin Requirement from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @return _imrValueE30 Total imr of trader's account.
  function getIMR(address _subAccount) external view returns (uint256 _imrValueE30) {
    return _getIMR(_subAccount);
  }

  function _getIMR(address _subAccount) internal view returns (uint256 _imrValueE30) {
    // Get all trader's opening positions
    PerpStorage.Position[] memory _traderPositions = PerpStorage(perpStorage).getPositionBySubAccount(_subAccount);
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    // Loop through all trader's positions
    uint256 len = _traderPositions.length;
    for (uint256 i; i < len; ) {
      PerpStorage.Position memory _position = _traderPositions[i];

      uint256 _size;
      if (_position.positionSizeE30 < 0) {
        _size = uint(_position.positionSizeE30 * -1);
      } else {
        _size = uint(_position.positionSizeE30);
      }

      // Calculate IMR on position
      _imrValueE30 += _calculatePositionIMR(_size, _position.marketIndex, _configStorage);

      unchecked {
        ++i;
      }
    }

    return _imrValueE30;
  }

  /// @notice Calculate Maintenance Margin Value from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @return _mmrValueE30 Total mmr of trader's account
  function getMMR(address _subAccount) external view returns (uint256 _mmrValueE30) {
    return _getMMR(_subAccount);
  }

  function _getMMR(address _subAccount) internal view returns (uint256 _mmrValueE30) {
    // Get all trader's opening positions
    PerpStorage.Position[] memory _traderPositions = PerpStorage(perpStorage).getPositionBySubAccount(_subAccount);
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    // Loop through all trader's positions
    for (uint256 i; i < _traderPositions.length; ) {
      PerpStorage.Position memory _position = _traderPositions[i];

      uint256 _size;
      if (_position.positionSizeE30 < 0) {
        _size = uint(_position.positionSizeE30 * -1);
      } else {
        _size = uint(_position.positionSizeE30);
      }

      // Calculate MMR on position
      _mmrValueE30 += _calculatePositionMMR(_size, _position.marketIndex, _configStorage);

      unchecked {
        ++i;
      }
    }

    return _mmrValueE30;
  }

  /// @notice Calculate for Initial Margin Requirement from position size.
  /// @param _positionSizeE30 Size of position.
  /// @param _marketIndex Market Index from opening position.
  /// @return _imrE30 The IMR amount required on position size, 30 decimals.
  function calculatePositionIMR(
    uint256 _positionSizeE30,
    uint256 _marketIndex
  ) external view returns (uint256 _imrE30) {
    return _calculatePositionIMR(_positionSizeE30, _marketIndex, ConfigStorage(configStorage));
  }

  function _calculatePositionIMR(
    uint256 _positionSizeE30,
    uint256 _marketIndex,
    ConfigStorage _configStorage
  ) internal view returns (uint256 _imrE30) {
    // Get market config according to position
    ConfigStorage.MarketConfig memory _marketConfig = _configStorage.getMarketConfigByIndex(_marketIndex);
    _imrE30 = (_positionSizeE30 * _marketConfig.initialMarginFractionBPS) / BPS;
    return _imrE30;
  }

  /// @notice Calculate for Maintenance Margin Requirement from position size.
  /// @param _positionSizeE30 Size of position.
  /// @param _marketIndex Market Index from opening position.
  /// @return _mmrE30 The MMR amount required on position size, 30 decimals.
  function calculatePositionMMR(
    uint256 _positionSizeE30,
    uint256 _marketIndex
  ) external view returns (uint256 _mmrE30) {
    return _calculatePositionMMR(_positionSizeE30, _marketIndex, ConfigStorage(configStorage));
  }

  function _calculatePositionMMR(
    uint256 _positionSizeE30,
    uint256 _marketIndex,
    ConfigStorage _configStorage
  ) internal view returns (uint256 _mmrE30) {
    // Get market config according to position
    ConfigStorage.MarketConfig memory _marketConfig = _configStorage.getMarketConfigByIndex(_marketIndex);
    _mmrE30 = (_positionSizeE30 * _marketConfig.maintenanceMarginFractionBPS) / BPS;
    return _mmrE30;
  }

  /// @notice This function returns the amount of free collateral available to a given sub-account
  /// @param _subAccount The address of the sub-account
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _freeCollateral The amount of free collateral available to the sub-account
  function getFreeCollateral(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (int256 _freeCollateral) {
    int256 equity = _getEquity(_subAccount, _limitPriceE30, _limitAssetId, new bytes32[](0), new uint256[](0));
    uint256 imr = _getIMR(_subAccount);
    _freeCollateral = equity - int256(imr);
    return _freeCollateral;
  }

  /// @notice Calculate next market average price
  /// @param _marketPositionSize - market's (long | short) position size
  /// @param _marketAveragePrice - market's average price
  /// @param _sizeDelta - position's size delta
  //                    - increase (long +, short -)
  //                    - decrease (long -, short +)
  /// @param _positionClosePrice - position's close price
  /// @param _positionNextClosePrice - position's close price after updated
  /// @param _positionRealizedPnl - position's realized PNL (profit +, loss -)
  function calculateMarketAveragePrice(
    int256 _marketPositionSize,
    uint256 _marketAveragePrice,
    int256 _sizeDelta,
    uint256 _positionClosePrice,
    uint256 _positionNextClosePrice,
    int256 _positionRealizedPnl
  ) external pure returns (uint256 _newAvaragePrice) {
    if (_marketAveragePrice == 0) return 0;
    // pnl calculation, LONG  -- position size * ((close price - average price) / average price)
    //                  SHORT -- position size * ((average price - close price) / average price)
    // example:
    // LONG  -- 1000 * ((105 - 100) / 100) = 50 (profit)
    //       -- 1000 * ((95 - 100) / 100) = -50 (loss)
    // SHORT -- -1000 * ((100 - 95) / 100) = -50 (profit)
    //       -- -1000 * ((100 - 105) / 100) = 50 (loss)
    bool isLong = _marketPositionSize > 0;
    int256 _marketPnl;
    if (isLong) {
      _marketPnl =
        (_marketPositionSize * (int256(_positionClosePrice) - int256(_marketAveragePrice))) /
        int256(_marketAveragePrice);
    } else {
      _marketPnl =
        (_marketPositionSize * (int256(_marketAveragePrice) - int256(_positionClosePrice))) /
        int256(_marketAveragePrice);
    }

    // unrealized pnl = market pnl - position realized pnl
    // example:
    // LONG  -- market pnl = 100,   realized position pnl = 50    then market unrealized pnl = 100 - 50     = 50  [profit]
    //       -- market pnl = -100,  realized position pnl = -50   then market unrealized pnl = -100 - (-50) = -50 [loss]

    // SHORT -- market pnl = -100,  realized position pnl = -50   then market unrealized pnl = -100 - (-50) = -50 [profit]
    //       -- market pnl = 100,   realized position pnl = 50    then market unrealized pnl = 100 - 50     = 50  [loss]
    int256 _unrealizedPnl = _marketPnl - _positionRealizedPnl;

    // | action         | market position | size delta |
    // | increase long  | +               | +          |
    // | decrease long  | +               | -          |
    // | increase short | -               | -          |
    // | decrease short | -               | +          |
    // then _marketPositionSize + _sizeDelta will work fine
    int256 _newMarketPositionSize = _marketPositionSize + _sizeDelta;
    int256 _divisor = isLong ? _newMarketPositionSize + _unrealizedPnl : _newMarketPositionSize - _unrealizedPnl;

    if (_newMarketPositionSize == 0) return 0;

    // for long, new market position size and divisor are positive number
    // and short, new market position size and divisor are negative number, then - / - would be +
    // note: abs unrealized pnl should not be greater then new position size, if calculation go wrong it's fine to revert
    return uint256((int256(_positionNextClosePrice) * _newMarketPositionSize) / _divisor);
  }

  function getFundingRateVelocity(uint256 _marketIndex) external view returns (int256 fundingRate) {
    return _getFundingRateVelocity(_marketIndex);
  }

  function proportionalElapsedInDay(uint256 _marketIndex) public view returns (uint256 elapsed) {
    PerpStorage.Market memory globalMarket = PerpStorage(perpStorage).getMarketByIndex(_marketIndex);
    return ((block.timestamp - globalMarket.lastFundingTime) * 1e18) / 1 days;
  }

  /// @notice Calculate the funding rate velocity
  /// @param _marketIndex Market Index.
  /// @return fundingRateVelocity which is the result of u = vt to get how fast the funding rate would change
  function _getFundingRateVelocity(uint256 _marketIndex) internal view returns (int256 fundingRateVelocity) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);
    GetFundingRateVar memory vars;
    ConfigStorage.MarketConfig memory marketConfig = _configStorage.getMarketConfigByIndex(_marketIndex);
    PerpStorage.Market memory globalMarket = PerpStorage(perpStorage).getMarketByIndex(_marketIndex);
    if (marketConfig.fundingRate.maxFundingRate == 0 || marketConfig.fundingRate.maxSkewScaleUSD == 0) return 0;
    vars.marketSkewUSDE30 = int(globalMarket.longPositionSize) - int(globalMarket.shortPositionSize);

    // The result of this fundingRateVelocity Formula will be in the range of [-maxFundingRate, maxFundingRate]
    vars.ratio =
      (vars.marketSkewUSDE30 * int(marketConfig.fundingRate.maxFundingRate)) /
      int(marketConfig.fundingRate.maxSkewScaleUSD);
    return
      vars.ratio > 0
        ? HMXLib.min(vars.ratio, int(marketConfig.fundingRate.maxFundingRate))
        : HMXLib.max(vars.ratio, -int(marketConfig.fundingRate.maxFundingRate));
  }

  /**
   * Funding Rate
   */
  function getFundingFee(
    int256 _size,
    int256 _currentFundingAccrued,
    int256 _lastFundingAccrued
  ) public pure returns (int256 fundingFee) {
    int256 _fundingAccrued = _currentFundingAccrued - _lastFundingAccrued;
    // positive funding fee = trader pay funding fee
    // negative funding fee = trader receive funding fee
    return (_size * _fundingAccrued) / int64(RATE_PRECISION);
  }

  /// @notice Calculates the borrowing fee for a given asset class based on the reserved value, entry borrowing rate, and current sum borrowing rate of the asset class.
  /// @param _assetClassIndex The index of the asset class for which to calculate the borrowing fee.
  /// @param _reservedValue The reserved value of the asset class.
  /// @param _entryBorrowingRate The entry borrowing rate of the asset class.
  /// @return borrowingFee The calculated borrowing fee for the asset class.
  function getBorrowingFee(
    uint8 _assetClassIndex,
    uint256 _reservedValue,
    uint256 _entryBorrowingRate
  ) external view returns (uint256 borrowingFee) {
    // Get the global asset class.
    PerpStorage.AssetClass memory _assetClassState = PerpStorage(perpStorage).getAssetClassByIndex(_assetClassIndex);
    // // Calculate borrowing fee.
    return _getBorrowingFee(_reservedValue, _assetClassState.sumBorrowingRate, _entryBorrowingRate);
  }

  function _getBorrowingFee(
    uint256 _reservedValue,
    uint256 _sumBorrowingRate,
    uint256 _entryBorrowingRate
  ) internal pure returns (uint256 borrowingFee) {
    // Calculate borrowing rate.
    uint256 _borrowingRate = _sumBorrowingRate - _entryBorrowingRate;
    // Calculate the borrowing fee based on reserved value, borrowing rate.
    return (_reservedValue * _borrowingRate) / RATE_PRECISION;
  }

  function getNextBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _hlpTVL
  ) external view returns (uint256 _nextBorrowingRate) {
    return _getNextBorrowingRate(_assetClassIndex, _hlpTVL);
  }

  /// @notice This function takes an asset class index as input and returns the next borrowing rate for that asset class.
  /// @param _assetClassIndex The index of the asset class.
  /// @param _hlpTVL value in hlp
  /// @return _nextBorrowingRate The next borrowing rate for the asset class.
  function _getNextBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _hlpTVL
  ) internal view returns (uint256 _nextBorrowingRate) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    // Get the trading config, asset class config, and global asset class for the given asset class index.
    ConfigStorage.TradingConfig memory _tradingConfig = _configStorage.getTradingConfig();
    ConfigStorage.AssetClassConfig memory _assetClassConfig = _configStorage.getAssetClassConfigByIndex(
      _assetClassIndex
    );
    PerpStorage.AssetClass memory _assetClassState = PerpStorage(perpStorage).getAssetClassByIndex(_assetClassIndex);
    // If block.timestamp not pass the next funding time, return 0.
    if (_assetClassState.lastBorrowingTime + _tradingConfig.fundingInterval > block.timestamp) return 0;

    // If HLP TVL is 0, return 0.
    if (_hlpTVL == 0) return 0;

    // Calculate the number of funding intervals that have passed since the last borrowing time.
    uint256 intervals = (block.timestamp - _assetClassState.lastBorrowingTime) / _tradingConfig.fundingInterval;

    // Calculate the next borrowing rate based on the asset class config, global asset class reserve value, and intervals.
    return (_assetClassConfig.baseBorrowingRate * _assetClassState.reserveValueE30 * intervals) / _hlpTVL;
  }

  function getTradingFee(
    int256 _size,
    uint256 _baseFeeRateBPS,
    uint256 _marketIndex
  ) external view returns (uint256 tradingFee) {
    return _getTradingFee(_size, _baseFeeRateBPS, _marketIndex);
  }

  function _getTradingFee(
    int256 _size,
    uint256 _baseFeeRateBPS,
    uint256 _marketIndex
  ) internal view returns (uint256 tradingFee) {
    TradeHelper th = TradeHelper(tradeHelper);
    bool _isAdaptiveFee = ConfigStorage(configStorage).isAdaptiveFeeEnabledByMarketIndex(_marketIndex);
    IPerpStorage.Market memory market = PerpStorage(perpStorage).getMarketByIndex(_marketIndex);
    int256 skew = int256(market.longPositionSize) - int256(market.shortPositionSize);
    uint256 takerFeeE8 = ConfigStorage(configStorage).takerFeeE8ByMarketIndex(_marketIndex);
    uint256 makerFeeE8 = ConfigStorage(configStorage).makerFeeE8ByMarketIndex(_marketIndex);
    uint256 absSizeDelta = HMXLib.abs(_size);
    if (takerFeeE8 > 0 || makerFeeE8 > 0) {
      // If _sizeDelta and _skew are in the same direction
      // (multiply them together; if they have the same sign, the result will be positive.)
      if (_size * skew > 0) {
        // _skew will be larger, we will charge takerFee only
        // Calculate the trading fee

        if (_isAdaptiveFee) {
          takerFeeE8 = th.getAdaptiveFeeE8(_size, _marketIndex, takerFeeE8);
        }
        tradingFee = (absSizeDelta * takerFeeE8) / 1e8;
      } else {
        // If _sizeDelta will flip _skew, then both taker fee and maker fee will be charged.
        if (absSizeDelta > HMXLib.abs(skew)) {
          // Collect makerFee first on the part equal to current market skew
          if (_isAdaptiveFee) {
            makerFeeE8 = th.getAdaptiveFeeE8(_size, _marketIndex, makerFeeE8);
          }
          tradingFee = (HMXLib.abs(skew) * makerFeeE8) / 1e8;

          // Then collect takerFee from the part that make marketSkew worse
          if (_isAdaptiveFee) {
            takerFeeE8 = th.getAdaptiveFeeE8(_size, _marketIndex, takerFeeE8);
          }
          tradingFee += (HMXLib.abs(_size + skew) * takerFeeE8) / 1e8;
        } else {
          // if _size does not flip _skew, it makes _skew better
          // we collect makerFee only
          if (_isAdaptiveFee) {
            makerFeeE8 = th.getAdaptiveFeeE8(_size, _marketIndex, makerFeeE8);
          }
          tradingFee = (absSizeDelta * makerFeeE8) / 1e8;
        }
      }
    } else {
      // If taker and maker fee is not set, use legacy trading fee
      if (_isAdaptiveFee) {
        _baseFeeRateBPS = th.getAdaptiveFeeBps(_size, _marketIndex, uint32(_baseFeeRateBPS));
      }

      tradingFee = (absSizeDelta * _baseFeeRateBPS) / BPS;
    }
  }

  struct GetDeltaVars {
    uint256 priceDelta;
    uint256 delta;
    bool isProfit;
    bool isLong;
    uint256 minProfitDuration;
    PerpStorage.Market market;
    ConfigStorage.MarketConfig marketConfig;
  }

  function getDelta(IPerpStorage.Position memory position, uint256 _markPrice) public view returns (bool, uint256) {
    GetDeltaVars memory vars;
    // Check for invalid input: averagePrice cannot be zero.
    if (position.avgEntryPriceE30 == 0) return (false, 0);

    // Calculate the difference between the average price and the fixed price.
    vars.priceDelta;
    unchecked {
      vars.priceDelta = position.avgEntryPriceE30 > _markPrice
        ? position.avgEntryPriceE30 - _markPrice
        : _markPrice - position.avgEntryPriceE30;
    }

    // Calculate the delta, adjusted for the size of the order.
    vars.delta = (HMXLib.abs(position.positionSizeE30) * vars.priceDelta) / position.avgEntryPriceE30;

    // Determine if the position is profitable or not based on the averagePrice and the mark price.
    vars.isProfit;
    vars.isLong = position.positionSizeE30 > 0;
    if (vars.isLong) {
      vars.isProfit = _markPrice > position.avgEntryPriceE30;
    } else {
      vars.isProfit = _markPrice < position.avgEntryPriceE30;
    }

    // In case of profit, we need to check the current timestamp against minProfitDuration
    // in order to prevent front-run attack, or price manipulation.
    // Check `isProfit` first, to save SLOAD in loss case.
    if (vars.isProfit) {
      vars.minProfitDuration = ConfigStorage(configStorage).getStepMinProfitDuration(
        position.marketIndex,
        position.lastIncreaseSize
      );
      if (block.timestamp < position.lastIncreaseTimestamp + vars.minProfitDuration) {
        vars.market = PerpStorage(perpStorage).getMarketByIndex(position.marketIndex);
        vars.marketConfig = ConfigStorage(configStorage).getMarketConfigByIndex(position.marketIndex);
        OracleMiddleware(oracle).getLatestAdaptivePrice(
          vars.marketConfig.assetId,
          vars.isLong, // if current position is SHORT position, then we use max price
          (int(vars.market.longPositionSize) - int(vars.market.shortPositionSize)),
          -position.positionSizeE30,
          vars.marketConfig.fundingRate.maxSkewScaleUSD,
          0
        );
        return (vars.isProfit, 0);
      }
    }

    // Return the values of isProfit and delta.
    return (vars.isProfit, vars.delta);
  }

  function getDelta(
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) external view returns (bool, uint256) {
    GetDeltaVars2 memory vars;
    vars.size = _size;
    vars.isLong = _isLong;
    vars.markPrice = _markPrice;
    vars.averagePrice = _averagePrice;
    vars.lastIncreaseTimestamp = _lastIncreaseTimestamp;
    vars.marketIndex = _marketIndex;
    vars.useMinProfitDuration = false;

    return _getDelta(vars);
  }

  function getDelta(
    address _subAccount,
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) external view returns (bool, uint256) {
    GetDeltaVars2 memory vars;
    vars.subAccount = _subAccount;
    vars.size = _size;
    vars.isLong = _isLong;
    vars.markPrice = _markPrice;
    vars.averagePrice = _averagePrice;
    vars.lastIncreaseTimestamp = _lastIncreaseTimestamp;
    vars.marketIndex = _marketIndex;
    vars.useMinProfitDuration = true;

    return _getDelta(vars);
  }

  /// @notice Calculates the delta between average price and mark price, based on the size of position and whether the position is profitable.
  /// @param _size The size of the position.
  /// @param _isLong position direction
  /// @param _markPrice current market price
  /// @param _averagePrice The average price of the position.
  /// @return isProfit A boolean value indicating whether the position is profitable or not.
  /// @return delta The Profit between the average price and the fixed price, adjusted for the size of the order.
  struct GetDeltaVars2 {
    address subAccount;
    uint256 size;
    bool isLong;
    uint256 markPrice;
    uint256 averagePrice;
    uint256 lastIncreaseTimestamp;
    uint256 marketIndex;
    bool useMinProfitDuration;
    uint256 priceDelta;
    uint256 delta;
    bool isProfit;
  }

  function _getDelta(GetDeltaVars2 memory vars) internal view returns (bool, uint256) {
    // Check for invalid input: averagePrice cannot be zero.
    if (vars.averagePrice == 0) return (false, 0);

    // Calculate the difference between the average price and the fixed price.
    vars.priceDelta;
    unchecked {
      vars.priceDelta = vars.averagePrice > vars.markPrice
        ? vars.averagePrice - vars.markPrice
        : vars.markPrice - vars.averagePrice;
    }

    // Calculate the delta, adjusted for the size of the order.
    vars.delta = (vars.size * vars.priceDelta) / vars.averagePrice;

    // Determine if the position is profitable or not based on the averagePrice and the mark price.
    vars.isProfit;
    if (vars.isLong) {
      vars.isProfit = vars.markPrice > vars.averagePrice;
    } else {
      vars.isProfit = vars.markPrice < vars.averagePrice;
    }

    // In case of profit, we need to check the current timestamp against minProfitDuration
    // in order to prevent front-run attack, or price manipulation.
    // Check `isProfit` first, to save SLOAD in loss case.
    if (vars.isProfit && vars.useMinProfitDuration) {
      bytes32 positionId = HMXLib.getPositionId(vars.subAccount, vars.marketIndex);
      IPerpStorage.Position memory position = PerpStorage(perpStorage).getPositionById(positionId);
      uint256 minProfitDuration = ConfigStorage(configStorage).getStepMinProfitDuration(
        vars.marketIndex,
        position.lastIncreaseSize
      );
      if (block.timestamp < vars.lastIncreaseTimestamp + minProfitDuration) {
        return (vars.isProfit, 0);
      }
    }

    // Return the values of isProfit and delta.
    return (vars.isProfit, vars.delta);
  }

  function _getGlobalMarketPnl(
    uint256 price,
    int256 skew,
    uint256 maxSkew,
    int256 sumSE, // SUM(positionSize / entryPrice)
    uint256 sumS2E, // SUM(positionSize^2 / entryPrice)
    uint256 sumSize, // longSize or shortSize
    bool isLong
  ) internal pure returns (int256) {
    sumSE = isLong ? -sumSE : sumSE;
    int256 pnlFromPositions = (price.toInt256() * sumSE) / 1e30;
    int256 pnlFromSkew = ((((price.toInt256() * skew) / (maxSkew.toInt256())) * sumSE) / 1e30);
    uint256 pnlFromVolatility = price.mulDiv(sumS2E, 2 * maxSkew);
    int256 pnlFromDirection = isLong ? -(sumSize.toInt256()) : sumSize.toInt256();
    int256 result = pnlFromPositions + pnlFromSkew + pnlFromVolatility.toInt256() - pnlFromDirection;
    return result;
  }

  function _getPriceFromInjectedData(
    bytes32 _tokenAssetId,
    bytes32[] memory _injectedAssetIds,
    uint256[] memory _injectedPrices
  ) internal pure returns (uint256 _priceE30) {
    uint256 injectedAssetIdLen = _injectedAssetIds.length;
    for (uint256 i; i < injectedAssetIdLen; ) {
      if (_injectedAssetIds[i] == _tokenAssetId) {
        _priceE30 = _injectedPrices[i];
        // stop inside looping after found price
        break;
      }
      unchecked {
        ++i;
      }
    }
    return _priceE30;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
