// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// interfaces
import { IPerpStorage } from "./interfaces/IPerpStorage.sol";

/// @title PerpStorage
/// @notice storage contract to keep core feature state
contract PerpStorage is OwnableUpgradeable, ReentrancyGuardUpgradeable, IPerpStorage {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;
  /**
   * Modifiers
   */
  modifier onlyWhitelistedExecutor() {
    if (!serviceExecutors[msg.sender]) revert IPerpStorage_NotWhiteListed();
    _;
  }

  /**
   * States
   */
  GlobalState public globalState; // global state that accumulative value from all markets

  mapping(bytes32 => Position) public positions;
  mapping(address => bytes32[]) public subAccountPositionIds;
  mapping(address => uint256) public subAccountBorrowingFee;
  mapping(uint256 => Market) public markets;
  mapping(uint256 => AssetClass) public assetClasses;
  mapping(address => bool) public serviceExecutors;

  EnumerableSet.Bytes32Set private activePositionIds;
  EnumerableSet.AddressSet private activeSubAccounts;

  mapping(uint256 marketIndex => mapping(uint256 timestamp => uint256 buyVolume)) public epochVolumeBuy;
  mapping(uint256 marketIndex => mapping(uint256 timestamp => uint256 sellVolume)) public epochVolumeSell;
  uint256 public movingWindowLength;
  uint256 public movingWindowInterval;

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
  }

  /**
   * Getters
   */
  /// @notice Get all positions with a specific trader's sub-account
  /// @param _subAccount The address of the trader whose positions to retrieve
  /// @return _subAccountPositions An array of Position objects representing the trader's positions
  function getPositionBySubAccount(address _subAccount) external view returns (Position[] memory _subAccountPositions) {
    bytes32[] memory _positionIds = subAccountPositionIds[_subAccount];
    uint256 _len = _positionIds.length;

    if (_len == 0) return _subAccountPositions;

    _subAccountPositions = new Position[](_positionIds.length);

    for (uint256 _i; _i < _len; ) {
      _subAccountPositions[_i] = (positions[_positionIds[_i]]);

      unchecked {
        ++_i;
      }
    }

    return _subAccountPositions;
  }

  function getPositionIds(address _subAccount) external view returns (bytes32[] memory _positionIds) {
    return subAccountPositionIds[_subAccount];
  }

  function getPositionById(bytes32 _positionId) external view returns (Position memory) {
    return positions[_positionId];
  }

  function getNumberOfSubAccountPosition(address _subAccount) external view returns (uint256) {
    return subAccountPositionIds[_subAccount].length;
  }

  function getMarketByIndex(uint256 _marketIndex) external view returns (Market memory) {
    return markets[_marketIndex];
  }

  function getAssetClassByIndex(uint256 _assetClassIndex) external view returns (AssetClass memory) {
    return assetClasses[_assetClassIndex];
  }

  function getGlobalState() external view returns (GlobalState memory) {
    return globalState;
  }

  function getActivePositionIds(uint256 _limit, uint256 _offset) external view returns (bytes32[] memory _ids) {
    uint256 _len = activePositionIds.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _ids;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _ids = new bytes32[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      _ids[i - _offset] = activePositionIds.at(i);
      unchecked {
        ++i;
      }
    }

    return _ids;
  }

  function getActivePositions(uint256 _limit, uint256 _offset) external view returns (Position[] memory _positions) {
    uint256 _len = activePositionIds.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _positions;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _positions = new Position[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      _positions[i - _offset] = positions[activePositionIds.at(i)];
      unchecked {
        ++i;
      }
    }

    return _positions;
  }

  function getActiveSubAccounts(uint256 _limit, uint256 _offset) external view returns (address[] memory _subAccounts) {
    uint256 _len = activeSubAccounts.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _subAccounts;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _subAccounts = new address[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      _subAccounts[i - _offset] = activeSubAccounts.at(i);
      unchecked {
        ++i;
      }
    }

    return _subAccounts;
  }

  /**
   * Setters
   */
  function setServiceExecutors(address _executorAddress, bool _isServiceExecutor) external onlyOwner nonReentrant {
    _setServiceExecutor(_executorAddress, _isServiceExecutor);
  }

  function setServiceExecutorBatch(
    address[] calldata _executorAddresses,
    bool[] calldata _isServiceExecutors
  ) external onlyOwner nonReentrant {
    if (_executorAddresses.length != _isServiceExecutors.length) revert IPerpStorage_BadLen();
    for (uint256 i = 0; i < _executorAddresses.length; ) {
      _setServiceExecutor(_executorAddresses[i], _isServiceExecutors[i]);
      unchecked {
        ++i;
      }
    }
  }

  function setMovingWindowConfig(uint256 length, uint256 interval) external onlyOwner {
    emit LogSetMovingWindowConfig(length, interval);
    movingWindowLength = length;
    movingWindowInterval = interval;
  }

  function setFundingRate(
    uint256[] calldata _marketIndexes,
    int256[] calldata _fundingRates
  ) external onlyOwner nonReentrant {
    if (_marketIndexes.length != _fundingRates.length) revert IPerpStorage_BadArrayLength();

    for (uint256 i = 0; i < _marketIndexes.length; ) {
      uint256 marketIndex = _marketIndexes[i];
      int256 fundingRate = _fundingRates[i];

      markets[marketIndex].currentFundingRate = fundingRate;
      markets[marketIndex].lastFundingTime = block.timestamp;

      emit LogSetFundingRate(marketIndex, fundingRate);

      unchecked {
        ++i;
      }
    }
  }

  function _setServiceExecutor(address _executorAddress, bool _isServiceExecutor) internal {
    serviceExecutors[_executorAddress] = _isServiceExecutor;
    emit LogSetServiceExecutor(_executorAddress, _isServiceExecutor);
  }

  function savePosition(
    address _subAccount,
    bytes32 _positionId,
    Position calldata position
  ) external nonReentrant onlyWhitelistedExecutor {
    IPerpStorage.Position memory _position = positions[_positionId];
    // register new position for trader's sub-account
    if (_position.positionSizeE30 == 0) {
      subAccountPositionIds[_subAccount].push(_positionId);
      activePositionIds.add(_positionId);
      activeSubAccounts.add(_subAccount);
    }
    positions[_positionId] = position;
  }

  /// @notice Resets the position associated with the given position ID.
  /// @param _subAccount The sub account of the position.
  /// @param _positionId The ID of the position to be reset.
  function removePositionFromSubAccount(address _subAccount, bytes32 _positionId) external onlyWhitelistedExecutor {
    bytes32[] storage _positionIds = subAccountPositionIds[_subAccount];
    uint256 _len = _positionIds.length;
    for (uint256 _i; _i < _len; ) {
      if (_positionIds[_i] == _positionId) {
        _positionIds[_i] = _positionIds[_len - 1];
        _positionIds.pop();
        delete positions[_positionId];
        activePositionIds.remove(_positionId);

        break;
      }

      unchecked {
        ++_i;
      }
    }

    // Clear out active sub account if all position's gone
    if (_positionIds.length == 0) {
      activeSubAccounts.remove(_subAccount);
    }
  }

  function updateGlobalLongMarketById(
    uint256 _marketIndex,
    uint256 _newPositionSize,
    uint256 _newAccumSE,
    uint256 _newAccumS2E
  ) external onlyWhitelistedExecutor {
    markets[_marketIndex].longPositionSize = _newPositionSize;
    markets[_marketIndex].longAccumSE = _newAccumSE;
    markets[_marketIndex].longAccumS2E = _newAccumS2E;
  }

  function updateGlobalShortMarketById(
    uint256 _marketIndex,
    uint256 _newPositionSize,
    uint256 _newAccumSE,
    uint256 _newAccumS2E
  ) external onlyWhitelistedExecutor {
    markets[_marketIndex].shortPositionSize = _newPositionSize;
    markets[_marketIndex].shortAccumSE = _newAccumSE;
    markets[_marketIndex].shortAccumS2E = _newAccumS2E;
  }

  function updateGlobalState(GlobalState calldata _newGlobalState) external onlyWhitelistedExecutor {
    globalState = _newGlobalState;
  }

  function updateAssetClass(
    uint8 _assetClassIndex,
    AssetClass calldata _newAssetClass
  ) external onlyWhitelistedExecutor {
    assetClasses[_assetClassIndex] = _newAssetClass;
  }

  function updateMarket(uint256 _marketIndex, Market calldata _market) external onlyWhitelistedExecutor {
    markets[_marketIndex] = _market;
  }

  function decreaseReserved(uint8 _assetClassIndex, uint256 _reserve) external onlyWhitelistedExecutor {
    globalState.reserveValueE30 -= _reserve;
    assetClasses[_assetClassIndex].reserveValueE30 -= _reserve;
  }

  function increasePositionSize(uint256 _marketIndex, bool _isLong, uint256 _size) external onlyWhitelistedExecutor {
    if (_isLong) {
      markets[_marketIndex].longPositionSize += _size;
    } else {
      markets[_marketIndex].shortPositionSize += _size;
    }
  }

  function decreasePositionSize(uint256 _marketIndex, bool _isLong, uint256 _size) external onlyWhitelistedExecutor {
    if (_isLong) {
      markets[_marketIndex].longPositionSize -= _size;
    } else {
      markets[_marketIndex].shortPositionSize -= _size;
    }
  }

  function increaseEpochVolume(bool isBuy, uint256 marketIndex, uint256 absSizeDelta) external onlyWhitelistedExecutor {
    uint256 epochTimestamp = _getCurrentEpochVolumeTimestamp();

    if (isBuy) {
      epochVolumeBuy[marketIndex][epochTimestamp] += absSizeDelta;
    } else {
      epochVolumeSell[marketIndex][epochTimestamp] += absSizeDelta;
    }
  }

  function getEpochVolume(bool isBuy, uint256 marketIndex) external view returns (uint256 epochVolume) {
    uint256 epochTimestamp = _getCurrentEpochVolumeTimestamp();

    if (isBuy) {
      for (uint256 i; i < movingWindowLength; i++) {
        epochVolume += epochVolumeBuy[marketIndex][epochTimestamp];
        epochTimestamp -= movingWindowInterval;
      }
    } else {
      for (uint256 i; i < movingWindowLength; i++) {
        epochVolume += epochVolumeSell[marketIndex][epochTimestamp];
        epochTimestamp -= movingWindowInterval;
      }
    }
  }

  function _getCurrentEpochVolumeTimestamp() internal view returns (uint256 epochTimestamp) {
    return movingWindowInterval > 0 ? (block.timestamp / movingWindowInterval) * movingWindowInterval : block.timestamp;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
