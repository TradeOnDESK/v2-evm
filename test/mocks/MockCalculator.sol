// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";

contract MockCalculator is ICalculator {
  mapping(address => int256) equitiesOf;
  mapping(address => uint256) imrOf;
  mapping(address => uint256) mmrOf;
  mapping(address => int256) unrealizedPnlOf;

  address public configStorage;
  address public perpStorage;
  address public vaultStorage;

  uint256 collateralValue;
  int256 freeCollateral;
  uint256 aum;
  uint256 hlpValue;
  uint256 nextBorrowingRate;
  int256 fundingFee;
  int256 fundingRate;
  int256 fundingRateLong;
  int256 fundingRateShort;
  int256 globalPnlE30;
  uint256 pendingBorrowingFeeE30;

  address public oracle;

  constructor(address _oracle) {
    oracle = _oracle;
  }

  // =========================================
  // | ---------- Setter ------------------- |
  // =========================================

  function setEquity(address _subAccount, int256 _mockEquity) external {
    equitiesOf[_subAccount] = _mockEquity;
  }

  function setIMR(address _subAccount, uint256 _mockImr) external {
    imrOf[_subAccount] = _mockImr;
  }

  function setMMR(address _subAccount, uint256 _mockMmr) external {
    mmrOf[_subAccount] = _mockMmr;
  }

  function setUnrealizedPnl(address _subAccount, int256 _mockUnrealizedPnl) external {
    unrealizedPnlOf[_subAccount] = _mockUnrealizedPnl;
  }

  function setAUM(uint256 _aum) external {
    aum = _aum;
  }

  function setFreeCollateral(int256 _mockFreeCollateral) external {
    freeCollateral = _mockFreeCollateral;
  }

  function setHLPValue(uint256 _mockHLPValue) external {
    hlpValue = _mockHLPValue;
  }

  function setFundingFee(int256 _fundingFee) external {
    fundingFee = _fundingFee;
  }

  function setFundingRate(int256 _fundingRate) external {
    fundingRate = _fundingRate;
  }

  function setFundingRateLong(int256 _fundingRateLong) external {
    fundingRateLong = _fundingRateLong;
  }

  function setFundingRateShort(int256 _fundingRateShort) external {
    fundingRateShort = _fundingRateShort;
  }

  function setGlobalPnlE30(int256 _globalPnlE30) external {
    globalPnlE30 = _globalPnlE30;
  }

  function setPendingBorrowingFeeE30(uint256 _pendingBorrowingFeeE30) external {
    pendingBorrowingFeeE30 = _pendingBorrowingFeeE30;
  }

  // =========================================
  // | ---------- Getter ------------------- |
  // =========================================

  function getEquity(address _subAccount, uint256 /* _price */, bytes32 /* _assetId */) external view returns (int256) {
    return equitiesOf[_subAccount];
  }

  function getEquityWithInjectedPrices(
    address _subAccount,
    bytes32[] memory /* _injectedAssetIds */,
    uint256[] memory /* _injectedPrices */
  ) external view returns (int256) {
    return equitiesOf[_subAccount];
  }

  // @todo - Add Description
  function getUnrealizedPnlAndFee(
    address _subAccount,
    uint256 /* _price */,
    bytes32 /* _assetId */
  ) public view returns (int256 _unrealizedPnlE30, int256 _unrealizedFeeE30) {
    return (unrealizedPnlOf[_subAccount], 0);
  }

  // @todo - Add Description
  /// @return imrValueE30 Total imr of trader's account.
  function getIMR(address _subAccount) external view returns (uint256) {
    return imrOf[_subAccount];
  }

  // @todo - Add Description
  /// @return mmrValueE30 Total mmr of trader's account
  function getMMR(address _subAccount) external view returns (uint256) {
    return mmrOf[_subAccount];
  }

  // =========================================
  // | ---------- Calculator --------------- |
  // =========================================

  function calculatePositionIMR(uint256, uint256) external pure returns (uint256) {
    return 0;
  }

  function calculatePositionMMR(uint256, uint256) external pure returns (uint256) {
    return 0;
  }

  function getGlobalPNLE30() external view returns (int256) {
    return globalPnlE30;
  }

  function getAUME30(bool /* isMaxPrice */) external view returns (uint256) {
    return aum;
  }

  function getHLPValueE30(bool /* isMaxPrice */) public view virtual returns (uint256) {
    return hlpValue;
  }

  function getHLPPrice(uint256 /* aum */, uint256 /* supply */) external pure returns (uint256) {
    // 1$
    return 1e30;
  }

  function getMintAmount(uint256 _aum, uint256 _totalSupply, uint256 _value) external pure returns (uint256) {
    return _aum == 0 ? _value / 1e12 : (_value * _totalSupply) / _aum / 1e12;
  }

  function convertTokenDecimals(
    uint256 _fromTokenDecimals,
    uint256 _toTokenDecimals,
    uint256 _amount
  ) external pure returns (uint256) {
    return (_amount * 10 ** _toTokenDecimals) / 10 ** _fromTokenDecimals;
  }

  function getAddLiquidityFeeBPS(
    address /*_token*/,
    uint256 /*_tokenValue*/,
    ConfigStorage /*_configStorage*/
  ) external pure returns (uint32) {
    return uint32(30);
  }

  function getRemoveLiquidityFeeBPS(
    address /*_tokenValueE30*/,
    uint256 /*_tokenValueE30*/,
    ConfigStorage /*_configStorage*/
  ) external pure returns (uint32) {
    return uint32(30);
  }

  function getFreeCollateral(
    address /*_subAccount*/,
    uint256 /*_price*/,
    bytes32 /*_assetId*/
  ) public view virtual returns (int256) {
    return freeCollateral;
  }

  function getNextBorrowingRate(uint8 /*_assetClassIndex*/, uint256 /*_hlpTVL*/) public view virtual returns (uint256) {
    return nextBorrowingRate;
  }

  function getTradingFee(int256 /*_size*/, uint256 /*_baseFeeRateBPS*/, uint256) public view virtual returns (uint256) {
    return 0;
  }

  function getFundingFee(
    int256 /*_size*/,
    int256 /*_currentFundingAccrued*/,
    int256 /*_lastFundingAccrued*/
  ) public view virtual returns (int256) {
    return fundingFee;
  }

  function getBorrowingFee(
    uint8 /*_assetClassIndex*/,
    uint256 /*_reservedValue*/,
    uint256 /*_entryBorrowingRate*/
  ) public view virtual returns (uint256 borrowingFee) {
    return borrowingFee;
  }

  function getFundingRateVelocity(uint256 /*marketIndex*/) public view virtual returns (int256) {
    return fundingRate;
  }

  function getSettlementFeeRate(
    address /* _token */,
    uint256 /* _liquidityUSDDelta */
  ) external pure returns (uint256) {
    // 0.5%
    return 5e15;
  }

  function getCollateralValue(
    address /*_subAccount*/,
    uint256 /*_limitPrice*/,
    bytes32 /*_assetId*/
  ) external view returns (uint256) {
    return collateralValue;
  }

  function setOracle(address /*_oracle*/) external {}

  function setVaultStorage(address /*_address*/) external {}

  function setConfigStorage(address /*_address*/) external {}

  function setPerpStorage(address /*_address*/) external {}

  function setTradeHelper(address /*_address*/) external {}

  function calculateMarketAveragePrice(
    int256 /* _marketPositionSize */,
    uint256 /* _marketAveragePrice */,
    int256 /* _sizeDelta */,
    uint256 /* _positionClosePrice */,
    uint256 /* _positionNextClosePrice */,
    int256 /* _positionRealizedPnl */
  ) public view virtual returns (uint256 _newAvaragePrice) {}

  function getDelta(
    IPerpStorage.Position memory position,
    uint256 _markPrice
  ) public view virtual returns (bool, uint256) {}

  function getDelta(
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) public view virtual returns (bool, uint256) {}

  function getDelta(
    address _subAccount,
    uint256 _size,
    bool _isLong,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp,
    uint256 _marketIndex
  ) public view virtual returns (bool, uint256) {}

  function getPositionNextAveragePrice(
    uint256 _size,
    bool _isLong,
    uint256 _sizeDelta,
    uint256 _markPrice,
    uint256 _averagePrice,
    uint256 _lastIncreaseTimestamp
  ) external pure returns (uint256) {}

  function getPendingBorrowingFeeE30() public view virtual returns (uint256) {
    return pendingBorrowingFeeE30;
  }

  function getGlobalMarketPnl(uint256 marketIndex, bool isLong) external view returns (int256) {}

  function proportionalElapsedInDay(uint256 _marketIndex) public view virtual returns (uint256 elapsed) {}
}
