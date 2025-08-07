// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { StdAssertions } from "forge-std/StdAssertions.sol";

import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

/// @title Trade Tester
/// @notice This Tester help to check state after user interact with LimitTradeHandler / TradeService
contract TradeTester is StdAssertions {
  /**
   * States
   */
  IVaultStorage vaultStorage;
  IPerpStorage perpStorage;

  address limitTradeHandler;

  address[] interestTokens;

  constructor(
    IVaultStorage _vaultStorage,
    IPerpStorage _perpStorage,
    address _limitTradeHandler,
    address[] memory _interestTokens
  ) {
    vaultStorage = _vaultStorage;
    perpStorage = _perpStorage;
    limitTradeHandler = _limitTradeHandler;

    interestTokens = _interestTokens;
  }

  struct PositionExpectedData {
    bytes32 positionId;
    uint256 avgEntryPriceE30;
    uint256 reserveValueE30;
    uint256 lastIncreaseTimestamp;
    int256 positionSizeE30;
    int256 realizedPnl;
  }

  struct MarketExpectedData {
    uint256 marketIndex;
    uint256 lastFundingTime;
    uint256 longPositionSize;
    uint256 shortPositionSize;
    uint256 shortOpenInterest;
    int256 accumFundingLong;
    int256 accumFundingShort;
    int256 currentFundingRate;
  }

  struct GlobalStateExpectedData {
    uint256 reserveValueE30;
    int256 accumFundingLong;
    int256 accumFundingShort;
  }

  struct AssetClassExpectedData {
    uint256 reserveValueE30;
    uint256 sumBorrowingRate;
    uint256 lastBorrowingTime;
    uint8 assetClassId;
  }

  struct PerpStorageExpectedData {
    int256 subAccountFee;
  }

  struct VaultStorageExpectedData {
    uint256 hlpLiquidityDebtUSDE30;
    mapping(address => uint256) hlpLiquidity;
    mapping(address => uint256) fees;
    mapping(address => uint256) fundingFee;
    mapping(address => uint256) devFees;
    mapping(address => uint256) traderBalances;
  }

  /// @notice Assert function when Trader increase position
  /// @dev This function will check
  ///     - Position
  ///       - Last increase timestamp
  ///     - Market
  ///     - PerpStorage
  ///     - VaultStorage
  function assertAfterIncrease(
    address _subAccount,
    PositionExpectedData memory _positionExpectedData,
    MarketExpectedData memory _marketExpectedData,
    AssetClassExpectedData memory _assetClassExpectedData,
    GlobalStateExpectedData memory _globalStateExpectedData,
    PerpStorageExpectedData memory _perpStorageExpectedData,
    VaultStorageExpectedData storage _vaultStorageExpectedData
  ) internal {
    // Check position info
    IPerpStorage.Position memory _position = _assertPosition(
      _positionExpectedData,
      _marketExpectedData,
      _assetClassExpectedData
    );

    // This assert only increase position
    assertEq(_position.lastIncreaseTimestamp, block.timestamp, "Last increase timestamp");

    // Check market
    _assertMarket(_marketExpectedData);

    // Check perp storage
    _assertPerpStorage(_subAccount, _perpStorageExpectedData, _assetClassExpectedData, _globalStateExpectedData);
    _assertVaultStorage(_subAccount, _vaultStorageExpectedData);
  }

  /// @notice Assert function when Trader decrease position
  /// @dev This function will check
  ///     - Position
  ///       - Realized PnL
  ///     - Market
  ///     - PerpStorage
  ///     - VaultStorage
  function assertAfterDecrease(
    address _subAccount,
    PositionExpectedData memory _positionExpectedData,
    MarketExpectedData memory _marketExpectedData,
    AssetClassExpectedData memory _assetClassExpectedData,
    GlobalStateExpectedData memory _globalStateExpectedData,
    PerpStorageExpectedData memory _perpStorageExpectedData,
    VaultStorageExpectedData storage _vaultStorageExpectedData
  ) internal {
    // Check position info
    IPerpStorage.Position memory _position = _assertPosition(
      _positionExpectedData,
      _marketExpectedData,
      _assetClassExpectedData
    );

    // This assert only increase position
    assertEq(_position.realizedPnl, _positionExpectedData.realizedPnl, "Last increase timestamp");

    // Check market
    _assertMarket(_marketExpectedData);
    _assertPerpStorage(_subAccount, _perpStorageExpectedData, _assetClassExpectedData, _globalStateExpectedData);
    _assertVaultStorage(_subAccount, _vaultStorageExpectedData);
  }

  /// @notice Assert position info
  /// @dev This function will check
  ///       - Average entry price
  ///       - Reserve value
  ///       - Position size
  ///       - Entry Borrowing rate - global asset class sum borrowing rate
  ///       - Entry funding rate - global market current funding rate
  function _assertPosition(
    PositionExpectedData memory _positionExpectedData,
    MarketExpectedData memory _marketExpectedData,
    AssetClassExpectedData memory _assetClassExpectedData
  ) internal returns (IPerpStorage.Position memory _position) {
    _position = perpStorage.getPositionById(_positionExpectedData.positionId);

    assertEq(_position.positionSizeE30, _positionExpectedData.positionSizeE30, "Position size");
    assertEq(_position.avgEntryPriceE30, _positionExpectedData.avgEntryPriceE30, "Position Average Price");
    assertEq(_position.reserveValueE30, _positionExpectedData.reserveValueE30, "Position Reserve");

    assertEq(_position.entryBorrowingRate, _assetClassExpectedData.sumBorrowingRate, "Entry Borrowing rate");
    assertEq(_position.lastFundingAccrued, _marketExpectedData.currentFundingRate, "Entry Funding rate");
  }

  /// @notice Assert Market
  /// @dev This function will check
  ///       - Last funding time
  ///       - Current funding rate
  ///       - Long Position size
  ///       - Long average price
  ///       - Short Position size
  ///       - Short average price
  function _assertMarket(MarketExpectedData memory _marketExpectedData) internal {
    IPerpStorage.Market memory _market = perpStorage.getMarketByIndex(_marketExpectedData.marketIndex);

    assertEq(_market.longPositionSize, _marketExpectedData.longPositionSize, "Long Position size");

    assertEq(_market.shortPositionSize, _marketExpectedData.shortPositionSize, "Short Position size");

    assertEq(_market.currentFundingRate, _marketExpectedData.currentFundingRate, "Current Funding Rate");
    assertEq(_market.lastFundingTime, _marketExpectedData.lastFundingTime, "Last Funding Time");
  }

  /// @notice Assert PerpStorage
  /// @dev This function will check
  ///       - Sub-account fee
  ///       - Asset class
  ///         - Last borrowing time
  ///         - Borrowing Rate Summation
  ///         - Reserve Value
  ///       - Global state
  ///         - Reserve value
  function _assertPerpStorage(
    address /* _subAccount */,
    PerpStorageExpectedData memory /* _perpStorageExpectedData */,
    AssetClassExpectedData memory _assetClassExpectedData,
    GlobalStateExpectedData memory _globalStateExpectedData
  ) internal {
    IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_assetClassExpectedData.assetClassId);
    IPerpStorage.GlobalState memory _globalState = perpStorage.getGlobalState();

    // Check global asset class
    assertEq(_assetClass.reserveValueE30, _assetClassExpectedData.reserveValueE30, "Global Asset Reserve");
    assertEq(_assetClass.sumBorrowingRate, _assetClassExpectedData.sumBorrowingRate, "Global Asset Borrowing Rate");
    assertEq(
      _assetClass.lastBorrowingTime,
      _assetClassExpectedData.lastBorrowingTime,
      "Global Asset Last Borrowing time"
    );

    // Check global reserve
    assertEq(_globalState.reserveValueE30, _globalStateExpectedData.reserveValueE30, "Global Reserve");
  }

  /// @notice Assert Vault info
  /// @dev This function will check
  ///       - Trader balance
  ///       - Dev fee
  ///       - Funding Fee
  ///       - Fee
  ///       - HLP Liquidity
  ///       - HLP Liquidity Debt value
  function _assertVaultStorage(address _subAccount, VaultStorageExpectedData storage _expectedData) internal {
    assertEq(vaultStorage.hlpLiquidityDebtUSDE30(), _expectedData.hlpLiquidityDebtUSDE30);

    uint256 _len = interestTokens.length;
    address _token;
    for (uint256 _i; _i < _len; ) {
      _token = interestTokens[_i];

      assertEq(vaultStorage.hlpLiquidity(_token), _expectedData.hlpLiquidity[_token], "HLP Liquidity");
      assertEq(vaultStorage.protocolFees(_token), _expectedData.fees[_token], "Protocol Fee");
      assertEq(vaultStorage.fundingFeeReserve(_token), _expectedData.fundingFee[_token], "Funding Fee");
      assertEq(vaultStorage.devFees(_token), _expectedData.devFees[_token], "Dev Fee");
      assertEq(
        vaultStorage.traderBalances(_subAccount, _token),
        _expectedData.traderBalances[_token],
        "Trader balance"
      );

      unchecked {
        ++_i;
      }
    }
  }
}
