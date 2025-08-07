// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { ABDKMath64x64 } from "@abdk/ABDKMath64x64.sol";
import { IEcoPythCalldataBuilder3 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder3.sol";
import { ICIXPriceAdapter } from "@hmx/oracles/interfaces/ICIXPriceAdapter.sol";

/// @dev Customized Index Pyth Adapter - Index price will be calculated using geometric mean according to weight config
contract CIXPriceAdapter is Ownable, ICIXPriceAdapter {
  using ABDKMath64x64 for int128;

  // constant
  int128 private immutable _E8_PRECISION_64X64 = ABDKMath64x64.fromUInt(1e8);

  // errors
  error CIXPriceAdapter_MissingPriceFromBuildData();
  error CIXPriceAdapter_BadParams();
  error CIXPriceAdapter_BadWeightSum();
  error CIXPriceAdapter_COverDiff();

  // state variables
  ICIXPriceAdapter.CIXConfig public config;
  uint32 public maxCDiffBps = 1000; // 10%

  // events
  event LogSetConfig(uint256 _cE8, bytes32[] _pythPriceIds, uint256[] _weightsE8, bool[] _usdQuoteds);
  event LogSetMaxCDiffBps(uint256 _oldMaxCDiffBps, uint256 _newMaxCDiffBps);
  event LogSetPyth(address _oldPyth, address _newPyth);

  function _accumulateWeightedPrice(
    int128 _accum,
    uint256 _priceE8,
    uint256 _weightE8,
    bool _usdQuoted
  ) private view returns (int128) {
    int128 _price = _convertE8To64x64(_priceE8);
    int128 _weight = _convertE8To64x64(_weightE8);
    if (_usdQuoted) _weight = _weight.neg();

    return _accum.mul(pow(_price, _weight));
  }

  function _convertE8To64x64(uint256 _n) private view returns (int128 _output) {
    _output = ABDKMath64x64.fromUInt(_n).div(_E8_PRECISION_64X64);
    return _output;
  }

  function _convert64x64ToE8(int128 _n) private view returns (uint128 _output) {
    _output = _n.mul(_E8_PRECISION_64X64).toUInt();
    return _output;
  }

  function _isOverMaxDiff(uint256 _a, uint256 _b, uint32 _maxDiffBps) private pure returns (bool) {
    if (_a * 10000 > _b * uint32(_maxDiffBps)) {
      return true;
    }
    if (_a * uint32(_maxDiffBps) < _b * 10000) {
      return true;
    }
    return false;
  }

  /**
   * Getter
   */

  /// Calculate geometric average price according to the formula
  /// price = c * (price1 ^ +-weight1) * (price2 ^ +-weight2) * ... * (priceN ^ +-weightN)
  function getPrice(
    IEcoPythCalldataBuilder3.BuildData[] calldata _buildDatas
  ) external view returns (uint256 _priceE18) {
    // 1. Declare _accum as c
    int128 _accum = _convertE8To64x64(config.cE8);

    // 2. Loop through config.
    //    Reduce the parameter with geometric average calculation.
    uint256 _len = config.assetIds.length;
    for (uint256 i = 0; i < _len; ) {
      // Get price from Pyth
      uint256 _priceE8 = _getPriceE8ByAssetId(config.assetIds[i], _buildDatas);

      // Accumulate the _accum with (priceN ^ +-weightN)
      _accum = _accumulateWeightedPrice(_accum, _priceE8, config.weightsE8[i], config.usdQuoteds[i]);

      unchecked {
        ++i;
      }
    }

    // 3. Convert the final result to uint256 in e18 basis
    _priceE18 = _convert64x64ToE8(_accum) * 1e10;
  }

  function getPrice(uint256[] memory priceE8s) external view returns (uint256 _priceE18) {
    // 1. Declare _accum as c
    int128 _accum = _convertE8To64x64(config.cE8);

    // 2. Loop through input prices
    //    Reduce the parameter with geometric average calculation.
    uint256 _len = priceE8s.length;
    for (uint256 i = 0; i < _len; ) {
      // Get price from Pyth
      uint256 _priceE8 = priceE8s[i];

      // Accumulate the _accum with (priceN ^ +-weightN)
      _accum = _accumulateWeightedPrice(_accum, _priceE8, config.weightsE8[i], config.usdQuoteds[i]);

      unchecked {
        ++i;
      }
    }

    // 3. Convert the final result to uint256 in e18 basis
    _priceE18 = _convert64x64ToE8(_accum) * 1e10;
  }

  function _getPriceE8ByAssetId(
    bytes32 _assetId,
    IEcoPythCalldataBuilder3.BuildData[] memory _buildDatas
  ) private pure returns (uint256 _priceE8) {
    uint256 _len = _buildDatas.length;
    for (uint256 i = 0; i < _len; ) {
      if (_assetId == _buildDatas[i].assetId) return uint256(int256(_buildDatas[i].priceE8));

      unchecked {
        ++i;
      }
    }

    if (_priceE8 == 0) revert CIXPriceAdapter_MissingPriceFromBuildData();
  }

  function getConfig() external view returns (ICIXPriceAdapter.CIXConfig memory _config) {
    return config;
  }

  /**
   * Setter
   */

  /// @notice Set the Pyth price id for the given asset.
  /// @param _cE8 A magic constant. Need to be recalculate every time the weight is changed.
  /// @param _assetIds An array asset id defined by HMX. This array index is relative to weightsE8.
  /// @param _weightsE8 An array of weights of certain asset in e8 basis. This should be relative to _pythPriceIds.
  function setConfig(
    uint256 _cE8,
    bytes32[] memory _assetIds,
    uint256[] memory _weightsE8,
    bool[] memory _usdQuoteds
  ) external onlyOwner {
    // 1. Validate params

    uint256 _len = _assetIds.length;
    // Validate length
    {
      if (_len != _weightsE8.length || _len != _usdQuoteds.length) revert CIXPriceAdapter_BadParams();
      if (_cE8 == 0) revert CIXPriceAdapter_BadParams();
    }

    // Validate weight and price id
    {
      uint256 _weightSum;
      for (uint256 i = 0; i < _len; ) {
        // Accum weight sum
        _weightSum += _weightsE8[i];

        unchecked {
          ++i;
        }
      }

      if (_weightSum != 1e8) revert CIXPriceAdapter_BadWeightSum();
    }

    // Validate c deviation
    {
      // Skip this check if c haven't been defined before
      if (config.cE8 != 0) {
        if (_isOverMaxDiff(config.cE8, _cE8, maxCDiffBps)) revert CIXPriceAdapter_COverDiff();
      }
    }

    // 2. Assign config to storage
    config.cE8 = _cE8;
    config.assetIds = _assetIds;
    config.weightsE8 = _weightsE8;
    config.usdQuoteds = _usdQuoteds;

    emit LogSetConfig(_cE8, _assetIds, _weightsE8, _usdQuoteds);
  }

  /// @notice Set maxCDiffBps.
  /// @param _maxCDiffBps New value. Valid value is 0 - 10000.
  function setMaxCDiffBps(uint32 _maxCDiffBps) external onlyOwner {
    if (_maxCDiffBps > 10000) revert CIXPriceAdapter_BadParams();

    emit LogSetMaxCDiffBps(maxCDiffBps, _maxCDiffBps);
    maxCDiffBps = _maxCDiffBps;
  }

  function pow(int128 x, int128 y) internal pure returns (int128) {
    require(x >= 0, "Negative base not allowed");
    if (x == 0) {
      require(y > 0, "0^0 is undefined");
      return 0;
    }
    return ABDKMath64x64.exp_2(ABDKMath64x64.mul(ABDKMath64x64.log_2(x), y));
  }
}
