// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

contract MockPerpStorage {
  mapping(address => IPerpStorage.Position[]) public positions;
  mapping(uint256 => IPerpStorage.Market) public markets;

  mapping(uint256 => IPerpStorage.AssetClass) public assetClasses;

  mapping(bytes32 => IPerpStorage.Position) public positionById;

  IPerpStorage.GlobalState public globalState; // global state that accumulative value from all markets

  /**
   * Getter
   */

  function getGlobalState() external view returns (IPerpStorage.GlobalState memory) {
    return globalState;
  }

  function getPositionBySubAccount(
    address _subAccount
  ) external view returns (IPerpStorage.Position[] memory traderPositions) {
    return positions[_subAccount];
  }

  function getAssetClassByIndex(uint256 _assetClassIndex) external view returns (IPerpStorage.AssetClass memory) {
    return assetClasses[_assetClassIndex];
  }

  function getPositionById(bytes32 _positionId) external view returns (IPerpStorage.Position memory) {
    return positionById[_positionId];
  }

  function _getPositionId(address _account, uint256 _marketIndex) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_account, _marketIndex));
  }

  function getMarketByIndex(uint256 _marketIndex) external view returns (IPerpStorage.Market memory) {
    return markets[_marketIndex];
  }

  /**
   * Setter
   */

  function setPositionBySubAccount(address _subAccount, IPerpStorage.Position memory _position) external {
    positions[_subAccount].push(_position);
    positionById[_getPositionId(_subAccount, _position.marketIndex)] = _position;
  }

  // @todo - update funding rate
  function updateGlobalLongMarketById(
    uint256 _marketIndex,
    uint256 _newPositionSize,
    int256 _newAccumFundingLong,
    int256 _currentFundingRate
  ) external {
    markets[_marketIndex].longPositionSize = _newPositionSize;
    markets[_marketIndex].accumFundingLong = _newAccumFundingLong;
    markets[_marketIndex].currentFundingRate = _currentFundingRate;
  }

  // @todo - update funding rate
  function updateGlobalShortMarketById(
    uint256 _marketIndex,
    uint256 _newPositionSize,
    int256 _newAccumFundingShort,
    int256 _currentFundingRate
  ) external {
    markets[_marketIndex].shortPositionSize = _newPositionSize;
    markets[_marketIndex].accumFundingShort = _newAccumFundingShort;
    markets[_marketIndex].currentFundingRate = _currentFundingRate;
  }

  function updateAssetClass(uint256 _assetClassIndex, IPerpStorage.AssetClass memory _newAssetClass) external {
    assetClasses[_assetClassIndex] = _newAssetClass;
  }

  function updateGlobalCounterTradeStates(
    uint256 _marketIndex,
    uint256 longPositionSize,
    uint256 longAccumSE,
    uint256 longAccumS2E,
    uint256 shortPositionSize,
    uint256 shortAccumSE,
    uint256 shortAccumS2E
  ) external {
    markets[_marketIndex].longPositionSize = longPositionSize;
    markets[_marketIndex].longAccumSE = longAccumSE;
    markets[_marketIndex].longAccumS2E = longAccumS2E;
    markets[_marketIndex].shortPositionSize = shortPositionSize;
    markets[_marketIndex].shortAccumSE = shortAccumSE;
    markets[_marketIndex].shortAccumS2E = shortAccumS2E;
  }

  function lastIncreaseSizeByPositionId(bytes32 positionId) external view returns (uint256 tradeSize) {}
}
