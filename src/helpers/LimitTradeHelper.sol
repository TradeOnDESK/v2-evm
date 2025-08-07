// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";

contract LimitTradeHelper is Ownable {
  error LimitTradeHelper_MaxTradeSize();
  error LimitTradeHelper_MaxPositionSize();

  event LogSetLimit(uint256 _marketIndex, uint256 _positionSizeLimitOf, uint256 _tradeSizeLimitOf);

  ConfigStorage public configStorage;
  PerpStorage public perpStorage;

  mapping(uint256 marketIndex => uint256 sizeLimit) public positionSizeLimitOf;
  mapping(uint256 marketIndex => uint256 sizeLimit) public tradeSizeLimitOf;

  constructor(address _configStorage, address _perpStorage) {
    configStorage = ConfigStorage(_configStorage);
    perpStorage = PerpStorage(_perpStorage);
  }

  function validate(
    address mainAccount,
    uint8 subAccountId,
    uint256 marketIndex,
    bool reduceOnly,
    int256 sizeDelta,
    bool isRevert
  ) external view returns (bool) {
    address _subAccount = HMXLib.getSubAccount(mainAccount, subAccountId);
    int256 _positionSizeE30 = perpStorage
      .getPositionById(HMXLib.getPositionId(_subAccount, marketIndex))
      .positionSizeE30;

    // Check trade size limit as per market
    if (tradeSizeLimitOf[marketIndex] > 0 && !reduceOnly && HMXLib.abs(sizeDelta) > tradeSizeLimitOf[marketIndex]) {
      if (isRevert) revert LimitTradeHelper_MaxTradeSize();
      else return false;
    }

    // Check position size limit as per market
    if (
      positionSizeLimitOf[marketIndex] > 0 &&
      !reduceOnly &&
      HMXLib.abs(_positionSizeE30 + sizeDelta) > positionSizeLimitOf[marketIndex]
    ) {
      if (isRevert) revert LimitTradeHelper_MaxPositionSize();
      else return false;
    }

    return true;
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
}
