// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ABDKMath64x64 } from "@abdk/ABDKMath64x64.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";

contract AdaptiveFeeCalculator is Ownable {
  using ABDKMath64x64 for int128;

  uint256 public k1; // in BPS
  uint256 public k2; // in BPS

  // Errors
  error AdaptiveFeeCalculator_BadBase();
  error AdaptiveFeeCalculator_ZeroPowZero();

  int128 RATE_PRECISION_64x64 = ABDKMath64x64.fromUInt(1e8);
  int128 BPS_PRECISION_64x64 = ABDKMath64x64.fromUInt(1e4);
  uint256 BPS = 10000;

  constructor(uint256 _k1, uint256 _k2) Ownable() {
    k1 = _k1;
    k2 = _k2;
  }

  function getAdaptiveFeeBps(
    uint256 sizeDelta,
    uint256 epochVolume,
    uint256 orderbookDepth,
    uint256 coeffVariant,
    uint256 baseFeeBps,
    uint256 maxFeeBps
  ) external view returns (uint32 feeBps) {
    // Normalize the formula for easier coding
    // y = min(baseFeeBps + (((sizeDelta + (epochVolume * k1))/liquidityDepth)^g * k2), maxFeeBps)
    // y = min(baseFeeBps + ((A^g) * k2), maxFeeBps)
    // y = min(baseFeeBps + B * k2), maxFeeBps)
    // Sell = bid
    // Buy = ask

    int128 x = _convertE8To64x64(sizeDelta + ((epochVolume * k1) / BPS));
    int128 d = _convertE8To64x64(orderbookDepth);
    int128 A = x.div(d);

    int128 g = findG(_convertE8To64x64(coeffVariant));
    int128 B = pow(A, g);
    int128 y = _convertBPSTo64x64(baseFeeBps).add(B.mul(_convertBPSTo64x64(k2)));
    return uint32(HMXLib.min(ABDKMath64x64.toUInt(ABDKMath64x64.mul(y, BPS_PRECISION_64x64)), maxFeeBps));
  }

  function getAdaptiveFeeE8(
    uint256 sizeDelta,
    uint256 epochVolume,
    uint256 orderbookDepth,
    uint256 coeffVariant,
    uint256 baseFeeE8,
    uint256 maxFeeE8
  ) external view returns (uint256 feeBps) {
    // Normalize the formula for easier coding
    // y = min(baseFeeBps + (((sizeDelta + (epochVolume * k1))/liquidityDepth)^g * k2), maxFeeBps)
    // y = min(baseFeeBps + ((A^g) * k2), maxFeeBps)
    // y = min(baseFeeBps + B * k2), maxFeeBps)
    // Sell = bid
    // Buy = ask

    int128 x = _convertE8To64x64(sizeDelta + ((epochVolume * k1) / BPS));
    int128 d = _convertE8To64x64(orderbookDepth);
    int128 A = x.div(d);

    int128 g = findG(_convertE8To64x64(coeffVariant));
    int128 B = pow(A, g);
    int128 y = _convertE8To64x64(baseFeeE8).add(B.mul(_convertBPSTo64x64(k2)));
    return uint256(HMXLib.min(ABDKMath64x64.toUInt(ABDKMath64x64.mul(y, RATE_PRECISION_64x64)), maxFeeE8));
  }

  function findG(int128 c) public pure returns (int128 g) {
    // g = 2^(2 - min(1, c))
    int128 min = HMXLib.minInt128(ABDKMath64x64.fromUInt(1), c);
    int128 expo = ABDKMath64x64.fromUInt(2).sub(min);
    g = ABDKMath64x64.exp_2(expo);
  }

  function _convertE8To64x64(uint256 input) internal view returns (int128 output) {
    output = ABDKMath64x64.fromUInt(input).div(RATE_PRECISION_64x64);
  }

  function _convertBPSTo64x64(uint256 input) internal view returns (int128 output) {
    output = ABDKMath64x64.fromUInt(input).div(BPS_PRECISION_64x64);
  }

  function setParams(uint256 _k1, uint256 _k2) external onlyOwner {
    k1 = _k1;
    k2 = _k2;
  }

  function pow(int128 x, int128 y) internal pure returns (int128) {
    if (x < 0) {
      revert AdaptiveFeeCalculator_BadBase();
    }
    if (x == 0) {
      if (y <= 0) {
        revert AdaptiveFeeCalculator_ZeroPowZero();
      }
      return 0;
    }
    return ABDKMath64x64.exp_2(ABDKMath64x64.mul(ABDKMath64x64.log_2(x), y));
  }
}
