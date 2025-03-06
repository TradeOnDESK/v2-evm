// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// deps
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";

// interfaces
import { IEcoPythCalldataBuilder3 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder3.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";

// libs
import { SqrtX96Codec } from "@hmx/libraries/SqrtX96Codec.sol";
import { PythLib } from "@hmx/libraries/PythLib.sol";
import { TickMath } from "@hmx/libraries/TickMath.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { OnChainPriceLens } from "@hmx/oracles/OnChainPriceLens.sol";
import { CalcPriceLens } from "@hmx/oracles/CalcPriceLens.sol";
import { IPriceAdapter } from "@hmx/oracles/interfaces/IPriceAdapter.sol";
import { ICalcPriceAdapter } from "@hmx/oracles/interfaces/ICalcPriceAdapter.sol";
import { ArbSys } from "@hmx/interfaces/arbitrum/ArbSys.sol";

contract UnsafeEcoPythCalldataBuilder3 is IEcoPythCalldataBuilder3 {
  address constant ARBSYS_ADDR = address(0x0000000000000000000000000000000000000064);
  IEcoPyth public ecoPyth;
  OnChainPriceLens public ocLens;
  CalcPriceLens public cLens;
  bool private l2BlockNumber;

  error BadOrder(uint256 index, bytes32 assetId);

  constructor(IEcoPyth ecoPyth_, OnChainPriceLens ocLens_, CalcPriceLens cLens_, bool l2BlockNumber_) {
    ecoPyth = ecoPyth_;
    ocLens = ocLens_;
    cLens = cLens_;
    l2BlockNumber = l2BlockNumber_;
  }

  function isOverMaxDiff(bytes32 _assetId, int64 _price, uint32 _maxDiffBps) internal view returns (bool) {
    return false;
  }

  function validateAssetOrder(BuildData[] calldata _data) internal view {
    uint _dataLength = _data.length;
    bytes32[] memory assetIds = ecoPyth.getAssetIds();

    // +1 here because assetIds[0] is blank
    // check that the buildData should have more assets than ecoPyth's assetIds
    // it can be less to support adding new assetIds operation
    require(_dataLength + 1 <= assetIds.length, "BAD_LENGTH");

    for (uint _i = 0; _i < _dataLength; ) {
      // +1 here because assetIds[0] is blank
      if (_data[_i].assetId != assetIds[_i + 1]) {
        revert BadOrder(_i, _data[_i].assetId);
      }
      unchecked {
        ++_i;
      }
    }
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
    validateAssetOrder(_data);
    uint _dataLength = _data.length;

    // 1. Validation
    _minPublishTime = type(uint256).max;
    for (uint _i = 0; _i < _dataLength; ) {
      // Check if price vs last price on EcoPyth is not over max diff
      address ocPriceAdapter = address(ocLens.priceAdapterById(_data[_i].assetId));
      address cPriceAdapter = address(cLens.priceAdapterById(_data[_i].assetId));
      if (ocPriceAdapter == address(0) && cPriceAdapter == address(0)) {
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

    // 2. Build ticks and publish time diffs
    int24[] memory _ticks = new int24[](_dataLength);
    uint24[] memory _publishTimeDiffs = new uint24[](_dataLength);
    for (uint _i = 0; _i < _dataLength; ) {
      IPriceAdapter ocPriceAdapter = ocLens.priceAdapterById(_data[_i].assetId);
      ICalcPriceAdapter cPriceAdapter = cLens.priceAdapterById(_data[_i].assetId);

      if (address(ocPriceAdapter) != address(0)) {
        // Use OnChainPriceLens, then make tick
        uint256 priceE18 = ocPriceAdapter.getPrice();
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(priceE18));
      } else if (address(cPriceAdapter) != address(0)) {
        // Use CIXPriceLens, then make tick
        uint256 priceE18 = cPriceAdapter.getPrice(_data);
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(priceE18));
      } else {
        // Make tick right away
        _ticks[_i] = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(PythLib.convertToUint(_data[_i].priceE8, -8, 18)));
      }

      _publishTimeDiffs[_i] = uint24(_data[_i].publishTime - _minPublishTime);

      unchecked {
        ++_i;
      }
    }

    // 3. Build the priceUpdateCalldata
    _priceUpdateCalldata = ecoPyth.buildPriceUpdateData(_ticks);

    // 4. Build the publishTimeUpdateCalldata
    _publishTimeUpdateCalldata = ecoPyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    if (l2BlockNumber) {
      blockNumber = ArbSys(ARBSYS_ADDR).arbBlockNumber();
    } else {
      blockNumber = block.number;
    }
  }

  function buildAsPrices(BuildData[] calldata _data) external view returns (uint256[] memory priceE8s) {
    validateAssetOrder(_data);
    uint _dataLength = _data.length;
    priceE8s = new uint256[](_dataLength);

    // 2. Build ticks and publish time diffs
    for (uint _i = 0; _i < _dataLength; ) {
      IPriceAdapter ocPriceAdapter = ocLens.priceAdapterById(_data[_i].assetId);
      ICalcPriceAdapter cPriceAdapter = cLens.priceAdapterById(_data[_i].assetId);

      if (address(ocPriceAdapter) != address(0)) {
        // Use OnChainPriceLens, then make tick
        uint256 priceE18 = ocPriceAdapter.getPrice();
        priceE8s[_i] = priceE18 / 1e10;
      } else if (address(cPriceAdapter) != address(0)) {
        // Use CIXPriceLens, then make tick
        uint256 priceE18 = cPriceAdapter.getPrice(_data);
        priceE8s[_i] = priceE18 / 1e10;
      } else {
        // Make tick right away
        priceE8s[_i] = _priceE18TickPriceE8(PythLib.convertToUint(_data[_i].priceE8, -8, 18));
      }

      unchecked {
        ++_i;
      }
    }
  }

  function _priceE18TickPriceE8(uint256 priceE18) internal pure returns (uint256) {
    int24 _tick = TickMath.getTickAtSqrtRatio(SqrtX96Codec.encode(priceE18));
    uint160 _sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
    return (uint256(_sqrtPriceX96) * (uint256(_sqrtPriceX96)) * (1e8)) >> (96 * 2);
  }
}
