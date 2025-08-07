// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { SafeCast } from "@openzeppelin-4.8.1/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { FullMath } from "@hmx/libraries/FullMath.sol";

library SqrtX96Codec {
  using SafeCast for uint256;

  uint8 internal constant RESOLUTION = 96;
  uint256 internal constant Q96 = 0x1000000000000000000000000;

  function encode(uint256 _priceE18) internal pure returns (uint160 _sqrtX96) {
    uint256 _sqrt = FixedPointMathLib.sqrt(_priceE18);
    return ((_sqrt * Q96) / 1e9).toUint160();
  }

  function decode(uint160 _sqrtX96) internal pure returns (uint256 _priceE18) {
    return FullMath.mulDiv(uint256(_sqrtX96) * 1e18, _sqrtX96, Q96 ** 2);
  }
}
