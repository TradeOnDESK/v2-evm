// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IVaultStorage {
  /**
   * Errors
   */
  error IVaultStorage_NotWhiteListed();
  error IVaultStorage_TraderTokenAlreadyExists();
  error IVaultStorage_TraderBalanceRemaining();
  error IVaultStorage_ZeroAddress();
  error IVaultStorage_HLPBalanceRemaining();
  error IVaultStorage_Forbidden();
  error IVaultStorage_TargetNotContract();
  error IVaultStorage_BadLen();
  error IVaultStorage_InvalidAddress();
  error IVaultStorage_InvalidAccounting();

  /**
   * Functions
   */
  function totalAmount(address _token) external returns (uint256);

  function lossDebt(address) external view returns (uint256);

  function tradingFeeDebt(address) external view returns (uint256);

  function borrowingFeeDebt(address) external view returns (uint256);

  function fundingFeeDebt(address) external view returns (uint256);

  function subTradingFeeDebt(address _trader, uint256 _tradingFeeDebt) external;

  function subBorrowingFeeDebt(address _trader, uint256 _borrowingFeeDebt) external;

  function subFundingFeeDebt(address _trader, uint256 _fundingFeeDebt) external;

  function subLossDebt(address _trader, uint256 _lossDebt) external;

  function convertFundingFeeReserveWithHLP(
    address _convertToken,
    address _targetToken,
    uint256 _convertAmount,
    uint256 _targetAmount
  ) external;

  function hlpLiquidityDebtUSDE30() external view returns (uint256);

  function traderBalances(address _trader, address _token) external view returns (uint256 amount);

  function getTraderTokens(address _trader) external view returns (address[] memory);

  function protocolFees(address _token) external view returns (uint256);

  function fundingFeeReserve(address _token) external view returns (uint256);

  function devFees(address _token) external view returns (uint256);

  function hlpLiquidity(address _token) external view returns (uint256);

  function hlpLiquidityOnHold(address _token) external view returns (uint256);

  function pullToken(address _token) external returns (uint256);

  function clearOnHold(address _token, uint256 _amount) external;

  function addFee(address _token, uint256 _amount) external;

  function addHLPLiquidity(address _token, uint256 _amount) external;

  function withdrawFee(address _token, uint256 _amount, address _receiver) external;

  function withdrawSurplusFromFundingFeeReserveToHLP(address _token, uint256 _fundingFeeAmount) external;

  function removeHLPLiquidity(address _token, uint256 _amount) external;

  function removeHLPLiquidityOnHold(address _token, uint256 _amount) external;

  function pushToken(address _token, address _to, uint256 _amount) external;

  function addFundingFee(address _token, uint256 _amount) external;

  function removeFundingFee(address _token, uint256 _amount) external;

  function addHlpLiquidityDebtUSDE30(uint256 _value) external;

  function removeHlpLiquidityDebtUSDE30(uint256 _value) external;

  function increaseTraderBalance(address _subAccount, address _token, uint256 _amount) external;

  function decreaseTraderBalance(address _subAccount, address _token, uint256 _amount) external;

  function payHlp(address _trader, address _token, uint256 _amount) external;

  function setServiceExecutors(address _executorAddress, bool _isServiceExecutor) external;

  function serviceExecutors(address _executor) external view returns (bool);

  function borrowFundingFeeFromHlpToTrader(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount,
    uint256 _fundingFeeValue
  ) external;

  function repayFundingFeeDebtFromTraderToHlp(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount,
    uint256 _fundingFeeValue
  ) external;

  function cook(address _token, address _target, bytes calldata _callData) external returns (bytes memory);

  function setStrategyAllowance(address _token, address _strategy, address _target) external;

  function setStrategyFunctionSigAllowance(address _token, address _strategy, bytes4 _target) external;

  function globalBorrowingFeeDebt() external view returns (uint256);

  function globalLossDebt() external view returns (uint256);
}
