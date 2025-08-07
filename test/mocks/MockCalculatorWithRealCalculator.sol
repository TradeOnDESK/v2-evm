// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { MockCalculator } from "./MockCalculator.sol";
import { Calculator } from "@hmx/contracts/Calculator.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";
import { console } from "forge-std/console.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";

contract MockCalculatorWithRealCalculator is MockCalculator {
  Calculator public c;
  mapping(bytes32 => bool) public actualFunction;
  ProxyAdmin proxyAdmin;

  constructor(
    address _proxyAdmin,
    address _oracle,
    address _vaultStorage,
    address _perpStorage,
    address _configStorage
  ) MockCalculator(_oracle) {
    c = Calculator(
      address(Deployer.deployCalculator(_proxyAdmin, _oracle, _vaultStorage, _perpStorage, _configStorage))
    );
  }

  function useActualFunction(bytes memory _funcName) external {
    actualFunction[keccak256(_funcName)] = true;
  }

  function getTradingFee(
    int256 _size,
    uint256 _baseFeeRateBPS,
    uint256 _marketIndex
  ) public view override returns (uint256) {
    if (actualFunction[keccak256("getTradingFee")]) {
      return c.getTradingFee(_size, _baseFeeRateBPS, _marketIndex);
    } else {
      return super.getTradingFee(_size, _baseFeeRateBPS, _marketIndex);
    }
  }

  function getFundingFee(
    int256 _size,
    int256 _currentFundingAccrued,
    int256 _lastFundingAccrued
  ) public view override returns (int256) {
    if (actualFunction[keccak256("getFundingFee")]) {
      return c.getFundingFee(_size, _currentFundingAccrued, _lastFundingAccrued);
    } else {
      return super.getFundingFee(_size, _currentFundingAccrued, _lastFundingAccrued);
    }
  }

  function getBorrowingFee(
    uint8 _assetClassIndex,
    uint256 _reservedValue,
    uint256 _entryBorrowingRate
  ) public view override returns (uint256 borrowingFee) {
    if (actualFunction[keccak256("getBorrowingFee")]) {
      return c.getBorrowingFee(_assetClassIndex, _reservedValue, _entryBorrowingRate);
    } else {
      return super.getBorrowingFee(_assetClassIndex, _reservedValue, _entryBorrowingRate);
    }
  }

  function getFundingRateVelocity(uint256 _marketIndex) public view virtual override returns (int256) {
    if (actualFunction[keccak256("getFundingRateVelocity")]) {
      return c.getFundingRateVelocity(_marketIndex);
    } else {
      return super.getFundingRateVelocity(_marketIndex);
    }
  }

  function getNextBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _hlpTVL
  ) public view override returns (uint256 _nextBorrowingRate) {
    if (actualFunction[keccak256("getNextBorrowingRate")]) {
      return c.getNextBorrowingRate(_assetClassIndex, _hlpTVL);
    } else {
      return super.getNextBorrowingRate(_assetClassIndex, _hlpTVL);
    }
  }

  function calculateMarketAveragePrice(
    int256 _marketPositionSize,
    uint256 _marketAveragePrice,
    int256 _sizeDelta,
    uint256 _positionClosePrice,
    uint256 _positionNextClosePrice,
    int256 _positionRealizedPnl
  ) public view override returns (uint256 _newAvaragePrice) {
    if (actualFunction[keccak256("calculateMarketAveragePrice")]) {
      return
        c.calculateMarketAveragePrice(
          _marketPositionSize,
          _marketAveragePrice,
          _sizeDelta,
          _positionClosePrice,
          _positionNextClosePrice,
          _positionRealizedPnl
        );
    } else {
      return
        super.calculateMarketAveragePrice(
          _marketPositionSize,
          _marketAveragePrice,
          _sizeDelta,
          _positionClosePrice,
          _positionNextClosePrice,
          _positionRealizedPnl
        );
    }
  }

  function getHLPValueE30(bool _isMaxPrice) public view override returns (uint256 _nextAveragePrice) {
    if (actualFunction[keccak256("getHLPValueE30")]) {
      return c.getHLPValueE30(_isMaxPrice);
    } else {
      return super.getHLPValueE30(_isMaxPrice);
    }
  }

  function getDelta(
    IPerpStorage.Position memory position,
    uint256 _markPrice
  ) public view override returns (bool, uint256) {
    if (actualFunction[keccak256("getDelta")]) {
      return c.getDelta(position, _markPrice);
    } else {
      return super.getDelta(position, _markPrice);
    }
  }

  function getDelta(
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) public view override returns (bool, uint256) {
    if (actualFunction[keccak256("getDelta")]) {
      return c.getDelta(_size, _isLong, _markPrice, _averagePrice, _lastIncreaseTimestamp, _marketIndex);
    } else {
      return super.getDelta(_size, _isLong, _markPrice, _averagePrice, _lastIncreaseTimestamp, _marketIndex);
    }
  }

  function getDelta(
    address _subAccount,
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) public view override returns (bool, uint256) {
    if (actualFunction[keccak256("getDelta")]) {
      return c.getDelta(_subAccount, _size, _isLong, _markPrice, _averagePrice, _lastIncreaseTimestamp, _marketIndex);
    } else {
      return
        super.getDelta(_subAccount, _size, _isLong, _markPrice, _averagePrice, _lastIncreaseTimestamp, _marketIndex);
    }
  }

  function getPendingBorrowingFeeE30() public view override returns (uint256) {
    if (actualFunction[keccak256("getPendingBorrowingFeeE30")]) {
      return c.getPendingBorrowingFeeE30();
    } else {
      return super.getPendingBorrowingFeeE30();
    }
  }

  function proportionalElapsedInDay(uint256 _marketIndex) public view override returns (uint256 elapsed) {
    if (actualFunction[keccak256("proportionalElapsedInDay")]) {
      return c.proportionalElapsedInDay(_marketIndex);
    } else {
      return super.proportionalElapsedInDay(_marketIndex);
    }
  }

  function _abs(int256 x) private pure returns (uint256) {
    return uint256(x >= 0 ? x : -x);
  }
}
