// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { StdAssertions } from "forge-std/StdAssertions.sol";

import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";

import { BaseIntTest_SetWhitelist } from "@hmx-test/integration/08_BaseIntTest_SetWhitelist.i.sol";

contract BaseIntTest_Assertions is BaseIntTest_SetWhitelist, StdAssertions {
  uint256 constant MAX_DIFF = 0.002 ether; // 0.1 %

  // Token Balances

  function assertTokenBalanceOf(address _account, address _token, uint256 _balance, string memory _str) internal {
    assertApproxEqRel(
      ERC20(_token).balanceOf(address(_account)),
      _balance,
      MAX_DIFF,
      string.concat(_str, "Trader's balance is not matched")
    );
  }

  function assertTokenBalanceOf(address _account, address _token, uint256 _balance) internal {
    assertTokenBalanceOf(_account, _token, _balance, "");
  }

  // HLP
  function assertHLPTotalSupply(uint256 _totalSupply, string memory _str) internal {
    assertApproxEqRel(
      hlpV2.totalSupply(),
      _totalSupply,
      MAX_DIFF,
      string.concat(_str, "HLP Total supply is not matched")
    );
  }

  function assertHLPTotalSupply(uint256 _totalSupply) internal {
    assertHLPTotalSupply(_totalSupply, "");
  }

  // Vault Storage

  function assertHLPDebt(uint256 _hlpDebt, string memory _str) internal {
    assertApproxEqRel(
      vaultStorage.hlpLiquidityDebtUSDE30(),
      _hlpDebt,
      MAX_DIFF,
      string.concat(_str, "HLP liquidity debt is not matched")
    );
  }

  function assertHLPDebt(uint256 _hlpDebt) internal {
    assertHLPDebt(_hlpDebt, "");
  }

  function assertHLPLiquidity(address _token, uint256 _liquidity, string memory _str) internal {
    assertApproxEqRel(
      vaultStorage.hlpLiquidity(_token),
      _liquidity,
      MAX_DIFF,
      string.concat(_str, "HLP token liquidity is not matched")
    );
  }

  function assertHLPLiquidity(address _token, uint256 _liquidity) internal {
    assertHLPLiquidity(_token, _liquidity, "");
  }

  function assertTVL(uint256 _tvl, bool _isMaxPrice, string memory _str) internal {
    assertApproxEqRel(
      calculator.getHLPValueE30(_isMaxPrice),
      _tvl,
      MAX_DIFF,
      string.concat(_str, "TVL is not matched")
    );
  }

  function assertTVL(uint256 _tvl, bool _isMaxPrice) internal {
    assertTVL(_tvl, _isMaxPrice, "");
  }

  function assertVaultTokenBalance(address _token, uint256 _balance, string memory _str) internal {
    assertEq(
      vaultStorage.totalAmount(_token),
      _balance,
      string.concat(_str, "Vault's Total amount of token is not matched")
    );
    assertEq(
      ERC20(_token).balanceOf(address(vaultStorage)),
      _balance,
      string.concat(_str, "Vault's token balance is not matched")
    );
  }

  function assertVaultTokenBalance(address _token, uint256 _balance) internal {
    assertVaultTokenBalance(_token, _balance, "");
  }

  function assertFundingFeeReserve(address _token, uint256 _fundingFeeReserve, string memory _str) internal {
    assertApproxEqRel(
      vaultStorage.fundingFeeReserve(_token),
      _fundingFeeReserve,
      MAX_DIFF,
      string.concat(_str, "Vault's Funding fee is not matched")
    );
  }

  function assertFundingFeeReserve(address _token, uint256 _fundingFeeReserve) internal {
    assertFundingFeeReserve(_token, _fundingFeeReserve, "");
  }

  function assertVaultsFees(
    address _token,
    uint256 _fee,
    uint256 _devFee,
    uint256 _fundingFeeReserve,
    string memory _str
  ) internal {
    assertApproxEqRel(
      vaultStorage.protocolFees(_token),
      _fee,
      MAX_DIFF,
      string.concat(_str, "Vault's Fee is not matched")
    );
    assertApproxEqRel(
      vaultStorage.devFees(_token),
      _devFee,
      MAX_DIFF,
      string.concat(_str, "Vault's Dev fee is not matched")
    );
    assertApproxEqRel(
      vaultStorage.fundingFeeReserve(_token),
      _fundingFeeReserve,
      MAX_DIFF,
      string.concat(_str, "Vault's Funding fee is not matched")
    );
  }

  function assertVaultsFees(address _token, uint256 _fee, uint256 _devFee, uint256 _fundingFee) internal {
    assertVaultsFees(_token, _fee, _devFee, _fundingFee, "");
  }

  function assertSubAccountTokenBalance(
    address _subAccount,
    address _token,
    bool _shouldExists,
    uint256 _balance,
    string memory _str
  ) internal {
    assertApproxEqRel(
      vaultStorage.traderBalances(_subAccount, _token),
      _balance,
      MAX_DIFF,
      string.concat(_str, "Trader's balance is not matched")
    );

    address[] memory _tokenAddresses = vaultStorage.getTraderTokens(_subAccount);
    uint256 _len = _tokenAddresses.length;
    bool _found = false;
    // Check token should exists in sub account's token
    for (uint256 _i; _i < _len; ) {
      if (_tokenAddresses[_i] == _token) {
        _found = true;
        break;
      }

      unchecked {
        ++_i;
      }
    }
    // normally if found token
    assertEq(
      _found,
      _shouldExists,
      string.concat(_str, _shouldExists ? "Token should exists" : "Token should not exists")
    );
  }

  function assertSubAccountTokenBalance(
    address _subAccount,
    address _token,
    bool _shouldExists,
    uint256 _balance
  ) internal {
    assertSubAccountTokenBalance(_subAccount, _token, _shouldExists, _balance, "");
  }

  // check all trader's token and balance
  function assertSubAccountTokensBalances(
    address _subAccount,
    address[] calldata _tokens,
    uint256[] calldata _balances,
    string memory _str
  ) internal {
    uint256 _len = _tokens.length;
    for (uint256 _i; _i < _len; ) {
      assertEq(
        vaultStorage.traderBalances(_subAccount, _tokens[_i]),
        _balances[_i],
        string.concat(vm.toString(_i), "Trader's balance")
      );

      unchecked {
        ++_i;
      }
    }

    assertEq(
      vaultStorage.getTraderTokens(_subAccount).length,
      _tokens.length,
      string.concat(_str, "Trader's token list length is not matched")
    );
  }

  function assertSubAccountTokensBalances(
    address _subAccount,
    address[] calldata _tokens,
    uint256[] calldata _balances
  ) internal {
    assertSubAccountTokensBalances(_subAccount, _tokens, _balances, "");
  }

  // Perp Storage

  function assertPositionInfoOf(
    address _subAccount,
    uint256 _marketIndex,
    int256 _positionSize,
    uint256 _avgPrice,
    uint256 _reserveValue,
    int256 _realizedPnl,
    uint256 _entryBorrowingRate,
    int256 _lastFundingAccrued,
    string memory _str
  ) internal {
    // shhh compiler
    _lastFundingAccrued;

    bytes32 _positionId = keccak256(abi.encodePacked(_subAccount, _marketIndex));
    IPerpStorage.Position memory _position = perpStorage.getPositionById(_positionId);

    assertApproxEqRel(
      _position.positionSizeE30,
      _positionSize,
      MAX_DIFF,
      string.concat(_str, "Position's size is not matched")
    );
    assertApproxEqRel(
      _position.avgEntryPriceE30,
      _avgPrice,
      MAX_DIFF,
      string.concat(_str, "Position's average price is not matched")
    );
    assertApproxEqRel(
      _position.reserveValueE30,
      _reserveValue,
      MAX_DIFF,
      string.concat(_str, "Position's reserve value is not matched")
    );
    assertApproxEqRel(
      _position.realizedPnl,
      _realizedPnl,
      MAX_DIFF,
      string.concat(_str, "Position's realized pnl is not matched")
    );
    assertApproxEqRel(
      _position.entryBorrowingRate,
      _entryBorrowingRate,
      MAX_DIFF,
      string.concat(_str, "Position's entry borrowing rate is not matched")
    );
    // assertApproxEqRel(
    //   _position.lastFundingAccrued,
    //   _lastFundingAccrued,
    //   MAX_DIFF,
    //   string.concat(_str, "Position's entry funding rate is not matched")
    // );
  }

  function assertPositionInfoOf(
    address _subAccount,
    uint256 _marketIndex,
    int256 _positionSize,
    uint256 _avgPrice,
    uint256 _reserveValue,
    int256 _realizedPnl,
    uint256 _entryBorrowingRate,
    int256 _lastFundingAccrued
  ) internal {
    assertPositionInfoOf(
      _subAccount,
      _marketIndex,
      _positionSize,
      _avgPrice,
      _reserveValue,
      _realizedPnl,
      _entryBorrowingRate,
      _lastFundingAccrued,
      ""
    );
  }

  function assertEntryFundingRate(
    address _subAccount,
    uint256 _marketIndex,
    int256 _lastFundingAccrued,
    string memory _str
  ) internal {
    bytes32 _positionId = keccak256(abi.encodePacked(_subAccount, _marketIndex));
    IPerpStorage.Position memory _position = perpStorage.getPositionById(_positionId);

    assertEq(
      _position.lastFundingAccrued,
      _lastFundingAccrued,
      string.concat(_str, "Position's entry funding rate is not matched")
    );
  }

  function assertMarketAccumFundingFee(
    uint256 _marketIndex,
    int256 _accumFundingLong,
    int256 _accumFundingShort,
    string memory _str
  ) internal {
    IPerpStorage.Market memory _market = perpStorage.getMarketByIndex(_marketIndex);

    assertEq(_market.accumFundingLong, _accumFundingLong, string.concat(_str, "Market's Accum funding fee long"));
    assertEq(_market.accumFundingShort, _accumFundingShort, string.concat(_str, "Market's Accum funding fee short"));
  }

  function assertNumberOfPosition(address _subAccount, uint256 _numberOfPosition, string memory _str) internal {
    assertEq(
      perpStorage.getNumberOfSubAccountPosition(_subAccount),
      _numberOfPosition,
      string.concat(_str, "Number of position")
    );
  }

  function assertNumberOfPosition(address _subAccount, uint256 _numberOfPosition) internal {
    assertEq(perpStorage.getNumberOfSubAccountPosition(_subAccount), _numberOfPosition, "");
  }

  function assertMarketFundingRate(
    uint256 _marketIndex,
    int256 _currentFundingRate,
    uint256 _lastFundingTime,
    string memory _str
  ) internal {
    IPerpStorage.Market memory _market = perpStorage.getMarketByIndex(_marketIndex);

    assertEq(_market.currentFundingRate, _currentFundingRate, string.concat(_str, "Market's Funding rate"));
    assertEq(_market.lastFundingTime, _lastFundingTime, string.concat(_str, "Market's Last funding time"));
  }

  function assertMarketFundingRate(
    uint256 _marketIndex,
    int256 _currentFundingRate,
    uint256 _lastFundingTime
  ) internal {
    assertMarketFundingRate(_marketIndex, _currentFundingRate, _lastFundingTime, "");
  }

  function assertMarketLongPosition(
    uint256 _marketIndex,
    uint256 _positionSize,
    uint256 _avgPrice,
    string memory _str
  ) internal {
    // shhh compiler
    _avgPrice;

    IPerpStorage.Market memory _market = perpStorage.getMarketByIndex(_marketIndex);

    assertApproxEqRel(
      _market.longPositionSize,
      _positionSize,
      MAX_DIFF,
      string.concat(_str, "Market's Long position size")
    );
  }

  function assertMarketLongPosition(uint256 _marketIndex, uint256 _positionSize, uint256 _avgPrice) internal {
    assertMarketLongPosition(_marketIndex, _positionSize, _avgPrice, "");
  }

  function assertMarketShortPosition(
    uint256 _marketIndex,
    uint256 _positionSize,
    uint256 _avgPrice,
    string memory _str
  ) internal {
    // shhh compiler
    _avgPrice;

    IPerpStorage.Market memory _market = perpStorage.getMarketByIndex(_marketIndex);

    assertApproxEqRel(
      _market.shortPositionSize,
      _positionSize,
      MAX_DIFF,
      string.concat(_str, "Market's Short position size")
    );
  }

  function assertMarketShortPosition(uint256 _marketIndex, uint256 _positionSize, uint256 _avgPrice) internal {
    assertMarketShortPosition(_marketIndex, _positionSize, _avgPrice, "");
  }

  function assertAssetClassReserve(uint8 _assetClassIndex, uint256 _reserved, string memory _str) internal {
    IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_assetClassIndex);
    assertEq(_assetClass.reserveValueE30, _reserved, string.concat(_str, "Asset class's Reserve value"));
  }

  function assertAssetClassReserve(uint8 _assetClassIndex, uint256 _reserved) internal {
    assertAssetClassReserve(_assetClassIndex, _reserved, "");
  }

  function assertGlobalReserve(uint256 _reserved, string memory _str) internal {
    IPerpStorage.GlobalState memory _globalState = perpStorage.getGlobalState();
    assertEq(_globalState.reserveValueE30, _reserved, string.concat(_str, "Global's Reserve value"));
  }

  function assertGlobalReserve(uint256 _reserved) internal {
    assertGlobalReserve(_reserved, "");
  }

  function assertAssetClassSumBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _sumBorrowingRate,
    uint256 _lastBorrowingTime,
    string memory _str
  ) internal {
    IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_assetClassIndex);
    assertApproxEqRel(
      _assetClass.sumBorrowingRate,
      _sumBorrowingRate,
      MAX_DIFF,
      string.concat(_str, "Asset class's Sum of Borrowing rate")
    );

    assertEq(
      _assetClass.lastBorrowingTime,
      _lastBorrowingTime,
      string.concat(_str, "Asset class's Last borrowing time")
    );
  }

  function assertAssetClassSumBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _sumBorrowingRate,
    uint256 _lastBorrowingTime
  ) internal {
    assertAssetClassSumBorrowingRate(_assetClassIndex, _sumBorrowingRate, _lastBorrowingTime, "");
  }

  // todo - remove
  function assertAssetClassState(
    uint8 _assetClassIndex,
    uint256 _reserved,
    uint256 _sumBorrowingRate,
    uint256 _lastBorrowingTime,
    string memory _str
  ) internal {
    IPerpStorage.AssetClass memory _assetClass = perpStorage.getAssetClassByIndex(_assetClassIndex);
    assertEq(_assetClass.reserveValueE30, _reserved, string.concat(_str, "Asset class's Reserve value"));

    assertEq(
      _assetClass.sumBorrowingRate,
      _sumBorrowingRate,
      string.concat(_str, "Asset class's Sum of Borrowing rate")
    );

    assertEq(
      _assetClass.lastBorrowingTime,
      _lastBorrowingTime,
      string.concat(_str, "Asset class's Last borrowing time")
    );
  }

  // todo - remove
  function assertAssetClassState(
    uint8 _assetClassIndex,
    uint256 _reserved,
    uint256 _sumBorrowingRate,
    uint256 _lastBorrowingTime
  ) internal {
    assertAssetClassState(_assetClassIndex, _reserved, _sumBorrowingRate, _lastBorrowingTime, "");
  }

  // Calculator
  function assertSubAccountStatus(address _subAccount, uint256 _imr, uint256 _mmr, string memory _str) internal {
    assertEq(calculator.getIMR(_subAccount), _imr, string.concat(_str, "IMR is not matched"));
    assertEq(calculator.getMMR(_subAccount), _mmr, string.concat(_str, "MMR is not matched"));
  }

  function assertSubAccountStatus(address _subAccount, uint256 _imr, uint256 _mmr) internal {
    assertSubAccountStatus(_subAccount, _imr, _mmr, "");
  }
}
