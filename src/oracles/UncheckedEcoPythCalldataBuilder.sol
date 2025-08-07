// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

// USED IN TEST ONLY, NOT FOR PRODUCTION USE

pragma solidity 0.8.18;

// deps
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";

// interfaces
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";

// libs
import { SqrtX96Codec } from "@hmx/libraries/SqrtX96Codec.sol";
import { PythLib } from "@hmx/libraries/PythLib.sol";
import { TickMath } from "@hmx/libraries/TickMath.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";

/// @title UnsafeEcoPythCalldataBuilder
/// @dev This contract is used when listing new markets only.
/// @dev It will skip certain checks to allow listing new markets.
contract UncheckedEcoPythCalldataBuilder is IEcoPythCalldataBuilder {
  bytes32 internal constant GLP_ASSET_ID = 0x474c500000000000000000000000000000000000000000000000000000000000;

  IEcoPyth public ecoPyth;
  IERC20 public sGlp;
  IGmxGlpManager public glpManager;

  event LogSetMaxGlpPriceDiff(uint32 _prevMaxGlpPriceDiff, uint32 _newMaxGlpPriceDiff);

  constructor(IEcoPyth ecoPyth_, IGmxGlpManager glpManager_, IERC20 sGlp_) {
    ecoPyth = ecoPyth_;
    sGlp = sGlp_;
    glpManager = glpManager_;
  }

  function isOverMaxDiff(bytes32, int64, uint32) internal pure returns (bool) {
    // never check max diff
    return false;
  }

  function build(
    BuildData[] calldata _data
  )
    external
    view
    returns (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    )
  {
    _minPublishTime = type(uint256).max;
    for (uint _i = 0; _i < _data.length; ) {
      // Check if price vs last price on EcoPyth is not over max diff
      if (_data[_i].assetId != GLP_ASSET_ID) {
        // If not GLP, then check the diff.
        // GLP no need to check diff due to the price will be query from GlpManager.
        require(!isOverMaxDiff(_data[_i].assetId, _data[_i].priceE8, _data[_i].maxDiffBps), "OVER_DIFF");
      }

      // Find the minimum publish time
      if (_data[_i].publishTime < _minPublishTime) {
        _minPublishTime = _data[_i].publishTime;
      }
      unchecked {
        ++_i;
      }
    }

    // Build ticks and publish time diffs
    int24[] memory _ticks = new int24[](_data.length);
    uint24[] memory _publishTimeDiffs = new uint24[](_data.length);
    for (uint _i = 0; _i < _data.length; ) {
      // Build the price update calldata
      if (_data[_i].assetId != GLP_ASSET_ID) {
        // If data is not GLP, then make tick rightaway.
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(PythLib.convertToUint(_data[_i].priceE8, -8, 18)));
      } else {
        // If data is GLP, then replace price with the price of GLP on-chain.
        uint256 _midAum = (glpManager.getAum(true) + glpManager.getAum(false)) / 2e12;
        uint256 _glpPrice = (1e18 * _midAum) / sGlp.totalSupply();
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(_glpPrice));
      }
      _publishTimeDiffs[_i] = uint24(_data[_i].publishTime - _minPublishTime);

      unchecked {
        ++_i;
      }
    }

    // Build the priceUpdateCalldata
    _priceUpdateCalldata = ecoPyth.buildPriceUpdateData(_ticks);
    // Build the publishTimeUpdateCalldata
    _publishTimeUpdateCalldata = ecoPyth.buildPublishTimeUpdateData(_publishTimeDiffs);
  }
}
