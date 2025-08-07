// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// deps
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";

// interfaces
import { IEcoPythCalldataBuilder2 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder2.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";

// libs
import { SqrtX96Codec } from "@hmx/libraries/SqrtX96Codec.sol";
import { PythLib } from "@hmx/libraries/PythLib.sol";
import { TickMath } from "@hmx/libraries/TickMath.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { OnChainPriceLens } from "@hmx/oracles/OnChainPriceLens.sol";
import { IPriceAdapter } from "@hmx/oracles/interfaces/IPriceAdapter.sol";
import { ArbSys } from "@hmx/interfaces/arbitrum/ArbSys.sol";

contract UnsafeEcoPythCalldataBuilder2 is IEcoPythCalldataBuilder2 {
  address constant ARBSYS_ADDR = address(0x0000000000000000000000000000000000000064);
  IEcoPyth public ecoPyth;
  OnChainPriceLens public lens;
  bool private l2BlockNumber;

  constructor(IEcoPyth ecoPyth_, OnChainPriceLens lens_, bool l2BlockNumber_) {
    ecoPyth = ecoPyth_;
    lens = lens_;
    l2BlockNumber = l2BlockNumber_;
  }

  function isOverMaxDiff(bytes32 _assetId, int64 _price, uint32 _maxDiffBps) internal view returns (bool) {
    int64 _latestPrice = 0;
    // If cannot get price from EcoPyth, then assume the price is 1e8.
    // Cases where EcoPyth cannot return price:
    // - New assets that are not listed on EcoPyth yet.
    // - New assets that over previous array length
    try ecoPyth.getPriceUnsafe(_assetId) returns (PythStructs.Price memory _ecoPythPrice) {
      // If price is exactly 1e8, then assume the price is not available.
      _latestPrice = _ecoPythPrice.price == 1e8 ? _price : _ecoPythPrice.price;
    } catch {
      _latestPrice = _price;
    }
    if (_latestPrice * 10000 > _price * int32(_maxDiffBps)) {
      return true;
    }
    if (_latestPrice * int32(_maxDiffBps) < _price * 10000) {
      return true;
    }
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
      bytes32[] memory _publishTimeUpdateCalldata,
      uint256 blockNumber
    )
  {
    _minPublishTime = type(uint256).max;
    for (uint _i = 0; _i < _data.length; ) {
      // Check if price vs last price on EcoPyth is not over max diff
      address priceAdapter = address(lens.priceAdapterById(_data[_i].assetId));
      if (priceAdapter == address(0)) {
        // If this is an off-chain price, then check the diff.
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
      IPriceAdapter priceAdapter = lens.priceAdapterById(_data[_i].assetId);
      if (address(priceAdapter) == address(0)) {
        // If data is not GLP, then make tick rightaway.
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(PythLib.convertToUint(_data[_i].priceE8, -8, 18)));
      } else {
        // If price adapter is available, retrieve the price on-chain from price adapter.
        uint256 priceE18 = priceAdapter.getPrice();
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(priceE18));
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
    if (l2BlockNumber) {
      blockNumber = ArbSys(ARBSYS_ADDR).arbBlockNumber();
    } else {
      blockNumber = block.number;
    }
  }
}
