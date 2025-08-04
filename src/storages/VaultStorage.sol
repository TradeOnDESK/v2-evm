// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

// interfaces
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/AddressUpgradeable.sol";
import { IVaultStorage } from "./interfaces/IVaultStorage.sol";

/// @title VaultStorage
/// @notice storage contract to do accounting for token, and also hold physical tokens
contract VaultStorage is OwnableUpgradeable, ReentrancyGuardUpgradeable, IVaultStorage {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;

  /**
   * Events
   */
  event LogSetTraderBalance(address indexed trader, address token, uint balance);
  event LogSetServiceExecutor(address indexed executorAddress, bool isServiceExecutor);
  event LogSetStrategyAllowance(address indexed token, address strategy, address prevTarget, address newTarget);
  event LogSetStrategyFunctionSigAllowance(
    address indexed token,
    address strategy,
    bytes4 prevFunctionSig,
    bytes4 newFunctionSig
  );
  event LogAddDevFee(address indexed token, uint256 devFeeAmount);
  event LogClearOnHold(
    address indexed token,
    uint256 clearAmount,
    uint256 prevTotalAmount,
    uint256 nextTotalAmount,
    uint256 prevOnHoldAmount,
    uint256 nextOnHoldAmount
  );
  event LogFeed(address indexed token, uint256 feedAmount, uint256 rewardRate, uint256 rewardRateExpiredAt);

  /**
   * States
   */
  mapping(address => uint256) public totalAmount; //token => tokenAmount
  mapping(address => uint256) public hlpLiquidity; // token => HLPTokenAmount
  mapping(address => uint256) public protocolFees; // protocol fee in token unit

  uint256 public hlpLiquidityDebtUSDE30; // USD debt accounting when fundingFee is not enough to repay to trader
  mapping(address => uint256) public fundingFeeReserve; // sum of realized funding fee amount

  mapping(address => uint256) public devFees;

  mapping(address => uint256) public tradingFeeDebt;
  mapping(address => uint256) public borrowingFeeDebt;
  mapping(address => uint256) public fundingFeeDebt;
  mapping(address => uint256) public lossDebt;

  uint256 public globalTradingFeeDebt;
  uint256 public globalBorrowingFeeDebt;
  uint256 public globalFundingFeeDebt;
  uint256 public globalLossDebt;

  // trader address (with sub-account) => token => amount
  mapping(address => mapping(address => uint256)) public traderBalances;
  // mapping(address => address[]) public traderTokens;
  mapping(address => address[]) public traderTokens;
  // mapping(token => strategy => target)
  mapping(address => mapping(address => address)) public strategyAllowances;
  // mapping(service executor address => allow)
  mapping(address => bool) public serviceExecutors;
  // mapping(token => strategy => target => isAllow?)
  mapping(address token => mapping(address strategy => bytes4 functionSig)) public strategyFunctionSigAllowances;
  // this mapping keeps track of hlpLiquidity that is on hold while being under rebalancing operation
  mapping(address token => uint256 amount) public hlpLiquidityOnHold;
  uint256 public rewardRate;
  uint256 public rewardRateExpiredAt;

  /**
   * Modifiers
   */
  modifier onlyWhitelistedExecutor() {
    if (!serviceExecutors[msg.sender]) revert IVaultStorage_NotWhiteListed();
    _;
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
  }

  /**
   * Core Functions
   */

  function validateAddTraderToken(address _trader, address _token) external view {
    _validateAddTraderToken(_trader, _token);
  }

  function validateRemoveTraderToken(address _trader, address _token) external view {
    _validateRemoveTraderToken(_trader, _token);
  }

  /**
   * Getters
   */

  function getTraderTokens(address _subAccount) external view returns (address[] memory) {
    return traderTokens[_subAccount];
  }

  /**
   * ERC20 interaction functions
   */

  function pullToken(address _token) external nonReentrant onlyWhitelistedExecutor returns (uint256) {
    return _pullToken(_token);
  }

  function _pullToken(address _token) internal returns (uint256) {
    uint256 prevBalance = totalAmount[_token];
    uint256 nextBalance = IERC20Upgradeable(_token).balanceOf(address(this)) + hlpLiquidityOnHold[_token];

    totalAmount[_token] = nextBalance;

    return nextBalance - prevBalance;
  }

  /// @notice Clear on hold amount
  /// @param _token The token to clear on hold amount
  /// @param _amount The amount to clear on hold amount
  function clearOnHold(address _token, uint256 _amount) external nonReentrant onlyWhitelistedExecutor {
    emit LogClearOnHold(
      _token,
      _amount,
      totalAmount[_token],
      totalAmount[_token] -= _amount,
      hlpLiquidityOnHold[_token],
      hlpLiquidityOnHold[_token] -= _amount
    );
  }

  function pushToken(address _token, address _to, uint256 _amount) external nonReentrant onlyWhitelistedExecutor {
    _pushToken(_token, _to, _amount);
  }

  function _pushToken(address _token, address _to, uint256 _amount) internal {
    IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    totalAmount[_token] = IERC20Upgradeable(_token).balanceOf(address(this)) + hlpLiquidityOnHold[_token];
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
    if (_executorAddresses.length != _isServiceExecutors.length) revert IVaultStorage_BadLen();
    for (uint256 i = 0; i < _executorAddresses.length; ) {
      _setServiceExecutor(_executorAddresses[i], _isServiceExecutors[i]);
      unchecked {
        ++i;
      }
    }
  }

  function _setServiceExecutor(address _executorAddress, bool _isServiceExecutor) internal {
    if (!_executorAddress.isContract()) revert IVaultStorage_InvalidAddress();
    serviceExecutors[_executorAddress] = _isServiceExecutor;
    emit LogSetServiceExecutor(_executorAddress, _isServiceExecutor);
  }

  function addFee(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    protocolFees[_token] += _amount;
  }

  function addDevFee(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    devFees[_token] += _amount;
    emit LogAddDevFee(_token, _amount);
  }

  function addFundingFee(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    fundingFeeReserve[_token] += _amount;
  }

  function removeFundingFee(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    fundingFeeReserve[_token] -= _amount;
  }

  function addHlpLiquidityDebtUSDE30(uint256 _value) external onlyWhitelistedExecutor {
    hlpLiquidityDebtUSDE30 += _value;
  }

  function removeHlpLiquidityDebtUSDE30(uint256 _value) external onlyWhitelistedExecutor {
    hlpLiquidityDebtUSDE30 -= _value;
  }

  function addHLPLiquidity(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    hlpLiquidity[_token] += _amount;
  }

  function withdrawFee(address _token, uint256 _amount, address _receiver) external onlyWhitelistedExecutor {
    if (_receiver == address(0)) revert IVaultStorage_ZeroAddress();
    protocolFees[_token] -= _amount;
    _pushToken(_token, _receiver, _amount);
  }

  function withdrawDevFee(address _token, uint256 _amount, address _receiver) external onlyOwner {
    if (_receiver == address(0)) revert IVaultStorage_ZeroAddress();
    devFees[_token] -= _amount;
    _pushToken(_token, _receiver, _amount);
  }

  function removeHLPLiquidity(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    if (hlpLiquidity[_token] < _amount) revert IVaultStorage_HLPBalanceRemaining();
    hlpLiquidity[_token] -= _amount;
  }

  function removeHLPLiquidityOnHold(address _token, uint256 _amount) external onlyWhitelistedExecutor {
    if (hlpLiquidity[_token] < _amount) revert IVaultStorage_HLPBalanceRemaining();
    hlpLiquidityOnHold[_token] += _amount;
    hlpLiquidity[_token] -= _amount;
  }

  /// @notice increase sub-account collateral
  /// @param _subAccount - sub account
  /// @param _token - collateral token to increase
  /// @param _amount - amount to increase
  function increaseTraderBalance(
    address _subAccount,
    address _token,
    uint256 _amount
  ) external onlyWhitelistedExecutor {
    _increaseTraderBalance(_subAccount, _token, _amount);
  }

  /// @notice decrease sub-account collateral
  /// @param _subAccount - sub account
  /// @param _token - collateral token to increase
  /// @param _amount - amount to decrease
  function decreaseTraderBalance(
    address _subAccount,
    address _token,
    uint256 _amount
  ) external onlyWhitelistedExecutor {
    _deductTraderBalance(_subAccount, _token, _amount);
  }

  /// @notice Pays the HLP for providing liquidity with the specified token and amount.
  /// @param _trader The address of the trader paying the HLP.
  /// @param _token The address of the token being used to pay the HLP.
  /// @param _amount The amount of the token being used to pay the HLP.
  function payHlp(address _trader, address _token, uint256 _amount) external onlyWhitelistedExecutor {
    // Increase the HLP's liquidity for the specified token
    hlpLiquidity[_token] += _amount;

    // Decrease the trader's balance for the specified token
    _deductTraderBalance(_trader, _token, _amount);
  }

  function transfer(address _token, address _from, address _to, uint256 _amount) external onlyWhitelistedExecutor {
    _deductTraderBalance(_from, _token, _amount);
    _increaseTraderBalance(_to, _token, _amount);
  }

  function payTradingFee(
    address _trader,
    address _token,
    uint256 _devFeeAmount,
    uint256 _protocolFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from trader balance
    _deductTraderBalance(_trader, _token, _devFeeAmount + _protocolFeeAmount);

    // Increase the amount to devFees and protocolFees
    devFees[_token] += _devFeeAmount;
    protocolFees[_token] += _protocolFeeAmount;
  }

  function payBorrowingFee(
    address _trader,
    address _token,
    uint256 _devFeeAmount,
    uint256 _hlpFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from trader balance
    _deductTraderBalance(_trader, _token, _devFeeAmount + _hlpFeeAmount);

    // Increase the amount to devFees and hlpLiquidity
    devFees[_token] += _devFeeAmount;
    hlpLiquidity[_token] += _hlpFeeAmount;
  }

  function payFundingFeeFromTraderToHlp(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from trader balance
    _deductTraderBalance(_trader, _token, _fundingFeeAmount);

    // Increase the amount to hlpLiquidity
    hlpLiquidity[_token] += _fundingFeeAmount;
  }

  function payFundingFeeFromHlpToTrader(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from hlpLiquidity
    hlpLiquidity[_token] -= _fundingFeeAmount;

    // Increase the amount to trader
    _increaseTraderBalance(_trader, _token, _fundingFeeAmount);
  }

  function payTraderProfit(
    address _trader,
    address _token,
    uint256 _totalProfitAmount,
    uint256 _settlementFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from hlpLiquidity
    hlpLiquidity[_token] -= _totalProfitAmount;

    protocolFees[_token] += _settlementFeeAmount;
    _increaseTraderBalance(_trader, _token, _totalProfitAmount - _settlementFeeAmount);
  }

  function _increaseTraderBalance(address _trader, address _token, uint256 _amount) internal {
    if (_amount == 0) return;

    if (traderBalances[_trader][_token] == 0) {
      _addTraderToken(_trader, _token);
    }
    traderBalances[_trader][_token] += _amount;
  }

  function _deductTraderBalance(address _trader, address _token, uint256 _amount) internal {
    if (_amount == 0) return;
    traderBalances[_trader][_token] -= _amount;
    if (traderBalances[_trader][_token] == 0) {
      _removeTraderToken(_trader, _token);
    }
  }

  function convertFundingFeeReserveWithHLP(
    address _convertToken,
    address _targetToken,
    uint256 _convertAmount,
    uint256 _targetAmount
  ) external onlyWhitelistedExecutor {
    // Deduct convert token amount from funding fee reserve
    fundingFeeReserve[_convertToken] -= _convertAmount;

    // Increase convert token amount to HLP
    hlpLiquidity[_convertToken] += _convertAmount;

    // Deduct target token amount from HLP
    hlpLiquidity[_targetToken] -= _targetAmount;

    // Deduct convert token amount from funding fee reserve
    fundingFeeReserve[_targetToken] += _targetAmount;
  }

  function withdrawSurplusFromFundingFeeReserveToHLP(
    address _token,
    uint256 _fundingFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from funding fee reserve
    fundingFeeReserve[_token] -= _fundingFeeAmount;

    // Increase the amount to HLP
    hlpLiquidity[_token] += _fundingFeeAmount;
  }

  function payFundingFeeFromTraderToFundingFeeReserve(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from trader balance
    _deductTraderBalance(_trader, _token, _fundingFeeAmount);

    // Increase the amount to fundingFee
    fundingFeeReserve[_token] += _fundingFeeAmount;
  }

  function payFundingFeeFromFundingFeeReserveToTrader(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount
  ) external onlyWhitelistedExecutor {
    // Deduct amount from fundingFee
    fundingFeeReserve[_token] -= _fundingFeeAmount;

    // Increase the amount to trader
    _increaseTraderBalance(_trader, _token, _fundingFeeAmount);
  }

  function repayFundingFeeDebtFromTraderToHlp(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount,
    uint256 _fundingFeeValue
  ) external onlyWhitelistedExecutor {
    // Deduct amount from trader balance
    _deductTraderBalance(_trader, _token, _fundingFeeAmount);

    // Add token amounts that HLP received
    hlpLiquidity[_token] += _fundingFeeAmount;

    // Remove debt value on HLP as received
    hlpLiquidityDebtUSDE30 -= _fundingFeeValue;
  }

  function borrowFundingFeeFromHlpToTrader(
    address _trader,
    address _token,
    uint256 _fundingFeeAmount,
    uint256 _fundingFeeValue
  ) external onlyWhitelistedExecutor {
    // Deduct token amounts from HLP
    hlpLiquidity[_token] -= _fundingFeeAmount;

    // Increase the amount to trader
    _increaseTraderBalance(_trader, _token, _fundingFeeAmount);

    // Add debt value on HLP
    hlpLiquidityDebtUSDE30 += _fundingFeeValue;
  }

  function addTradingFeeDebt(address _trader, uint256 _tradingFeeDebt) external onlyWhitelistedExecutor {
    tradingFeeDebt[_trader] += _tradingFeeDebt;
    globalTradingFeeDebt += _tradingFeeDebt;
  }

  function addBorrowingFeeDebt(address _trader, uint256 _borrowingFeeDebt) external onlyWhitelistedExecutor {
    borrowingFeeDebt[_trader] += _borrowingFeeDebt;
    globalBorrowingFeeDebt += _borrowingFeeDebt;
  }

  function addFundingFeeDebt(address _trader, uint256 _fundingFeeDebt) external onlyWhitelistedExecutor {
    fundingFeeDebt[_trader] += _fundingFeeDebt;
    globalFundingFeeDebt += _fundingFeeDebt;
  }

  function addLossDebt(address _trader, uint256 _lossDebt) external onlyWhitelistedExecutor {
    lossDebt[_trader] += _lossDebt;
    globalLossDebt += _lossDebt;
  }

  function subTradingFeeDebt(address _trader, uint256 _tradingFeeDebt) external onlyWhitelistedExecutor {
    tradingFeeDebt[_trader] -= _tradingFeeDebt;
    globalTradingFeeDebt -= _tradingFeeDebt;
  }

  function subBorrowingFeeDebt(address _trader, uint256 _borrowingFeeDebt) external onlyWhitelistedExecutor {
    borrowingFeeDebt[_trader] -= _borrowingFeeDebt;
    globalBorrowingFeeDebt -= _borrowingFeeDebt;
  }

  function subFundingFeeDebt(address _trader, uint256 _fundingFeeDebt) external onlyWhitelistedExecutor {
    fundingFeeDebt[_trader] -= _fundingFeeDebt;
    globalFundingFeeDebt -= _fundingFeeDebt;
  }

  function subLossDebt(address _trader, uint256 _lossDebt) external onlyWhitelistedExecutor {
    lossDebt[_trader] -= _lossDebt;
    globalLossDebt -= _lossDebt;
  }

  /**
   * Strategy
   */

  /// @notice Set the strategy for a token
  /// @param _token The token to set the strategy for
  /// @param _strategy The strategy to set
  /// @param _target The target to set
  function setStrategyAllowance(address _token, address _strategy, address _target) external onlyOwner {
    // Target must be a contract. This to prevent strategy calling to EOA.
    if (!_target.isContract()) revert IVaultStorage_TargetNotContract();

    emit LogSetStrategyAllowance(_token, _strategy, strategyAllowances[_token][_strategy], _target);
    strategyAllowances[_token][_strategy] = _target;
  }

  /// @notice Set the allowed function sig of a strategy for a token
  /// @param _token The token to set the strategy for
  /// @param _strategy The strategy to set
  /// @param _target The target function sig to allow
  function setStrategyFunctionSigAllowance(address _token, address _strategy, bytes4 _target) external onlyOwner {
    emit LogSetStrategyFunctionSigAllowance(
      _token,
      _strategy,
      strategyFunctionSigAllowances[_token][_strategy],
      _target
    );
    strategyFunctionSigAllowances[_token][_strategy] = _target;
  }

  function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
    // If the _res length is less than 68, then the transaction failed silently (without a revert message)
    if (_returnData.length < 68) return "Transaction reverted silently";
    assembly {
      // Slice the sighash.
      _returnData := add(_returnData, 0x04)
    }
    return abi.decode(_returnData, (string)); // All that remains is the revert string
  }

  /// @notice invoking the target contract using call data.
  /// @param _token The token to cook
  /// @param _target target to execute callData
  /// @param _callData call data signature
  function cook(address _token, address _target, bytes calldata _callData) external returns (bytes memory) {
    // Check
    // 1. Only strategy for specific token can call this function
    if (strategyAllowances[_token][msg.sender] != _target) revert IVaultStorage_Forbidden();

    // Only whitelisted function sig can be performed by the strategy
    bytes4 functionSig = bytes4(_callData[:4]);
    if (strategyFunctionSigAllowances[_token][msg.sender] != functionSig) revert IVaultStorage_Forbidden();

    // 2. Execute the call as what the strategy wants
    (bool _success, bytes memory _returnData) = _target.call(_callData);
    // 3. Revert if not success
    require(_success, _getRevertMsg(_returnData));

    return _returnData;
  }

  /**
   * Private Functions
   */

  function _addTraderToken(address _trader, address _token) private {
    _validateAddTraderToken(_trader, _token);
    traderTokens[_trader].push(_token);
  }

  function _removeTraderToken(address _trader, address _token) private {
    _validateRemoveTraderToken(_trader, _token);

    address[] storage traderToken = traderTokens[_trader];
    uint256 tokenLen = traderToken.length;
    uint256 lastTokenIndex = tokenLen - 1;

    // find and deregister the token
    for (uint256 i; i < tokenLen; ) {
      if (traderToken[i] == _token) {
        // delete the token by replacing it with the last one and then pop it from there
        if (i != lastTokenIndex) {
          traderToken[i] = traderToken[lastTokenIndex];
        }
        traderToken.pop();
        break;
      }

      unchecked {
        i++;
      }
    }
  }

  function _validateRemoveTraderToken(address _trader, address _token) private view {
    if (traderBalances[_trader][_token] != 0) revert IVaultStorage_TraderBalanceRemaining();
  }

  function _validateAddTraderToken(address _trader, address _token) private view {
    address[] memory traderToken = traderTokens[_trader];

    uint256 len = traderToken.length;
    for (uint256 i; i < len; ) {
      if (traderToken[i] == _token) revert IVaultStorage_TraderTokenAlreadyExists();
      unchecked {
        i++;
      }
    }
  }

  function feed(address _token, uint256 _feedAmount, uint256 _duration) external onlyWhitelistedExecutor {
    _feed(_token, _feedAmount, _duration);
  }

  function feedWithExpiredAt(address _token, uint256 _feedAmount, uint256 _expiredAt) external onlyWhitelistedExecutor {
    _feed(_token, _feedAmount, _expiredAt - block.timestamp);
  }

  function _feed(address _token, uint256 _feedAmount, uint256 _duration) internal {
    // Transfer token
    IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _feedAmount);

    uint256 leftOverReward = rewardRateExpiredAt > block.timestamp
      ? (rewardRateExpiredAt - block.timestamp) * rewardRate
      : 0;
    uint256 totalRewardAmount = leftOverReward + _feedAmount;

    rewardRate = totalRewardAmount / _duration;
    rewardRateExpiredAt = block.timestamp + _duration;

    emit LogFeed(_token, _feedAmount, rewardRate, rewardRateExpiredAt);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
