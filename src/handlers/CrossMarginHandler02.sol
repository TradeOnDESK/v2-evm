// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// base
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin-4.8.1/contracts/utils/structs/EnumerableSet.sol";

// interfaces
import { ICrossMarginHandler02 } from "@hmx/handlers/interfaces/ICrossMarginHandler02.sol";
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";

import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";

/// @title CrossMarginHandler
/// @notice This contract handles the deposit and withdrawal of collateral tokens for the Cross Margin Trading module.
contract CrossMarginHandler02 is OwnableUpgradeable, ReentrancyGuardUpgradeable, ICrossMarginHandler02 {
  using SafeERC20Upgradeable for ERC20Upgradeable;
  using EnumerableSet for EnumerableSet.UintSet;

  /**
   * Events
   */
  event LogDepositCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );
  event LogWithdrawCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );
  event LogSetCrossMarginService(address indexed oldCrossMarginService, address newCrossMarginService);
  event LogSetDelegate(address sender, address delegate);
  event LogSetPyth(address indexed oldPyth, address newPyth);
  event LogSetOrderExecutor(address executor, bool isAllow);
  event LogSetMinExecutionFee(uint256 oldValue, uint256 newValue);
  event LogCreateWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderId,
    address token,
    uint256 amount,
    uint256 executionFee,
    bool shouldUnwrap
  );
  event LogCancelWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderIndex,
    address token,
    uint256 amount,
    uint256 executionFee,
    bool shouldUnwrap
  );
  event LogExecuteWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderIndex,
    address token,
    uint256 amount,
    bool shouldUnwrap,
    bool isSuccess,
    string errMsg
  );

  struct ExecuteOrderVars {
    WithdrawOrder order;
    address subAccount;
    bytes32 positionId;
    bytes32 encodedVaas;
    bytes32[] priceData;
    bytes32[] publishTimeData;
    address payable feeReceiver;
    uint256 orderIndex;
    uint256 minPublishTime;
  }

  /**
   * States
   */
  address public crossMarginService;
  address public pyth;
  address private _senderOverride;

  uint256 public minExecutionOrderFee; // minimum execution order fee in native token amount

  mapping(address => bool) public orderExecutors; // address -> flag to execute
  mapping(address => mapping(uint256 => WithdrawOrder)) public withdrawOrders; // The last limit order index of each sub-account
  mapping(address => uint256) public withdrawOrdersIndex; // The last withdraw order index of each sub-account
  mapping(address => address) public delegations; // The mapping of mainAccount => Smart Wallet to be used for Account Abstraction

  // Pointers
  EnumerableSet.UintSet private _activeOrderPointers;
  EnumerableSet.UintSet private _executedOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountActiveOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountExecutedOrderPointers;

  /// @notice Initializes the CrossMarginHandler contract with the provided configuration parameters.
  /// @param _crossMarginService Address of the CrossMarginService contract.
  /// @param _pyth Address of the Pyth contract.
  /// @param _minExecutionOrderFee Minimum execution fee for a withdrawal order.
  function initialize(address _crossMarginService, address _pyth, uint256 _minExecutionOrderFee) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
    IEcoPyth(_pyth).getAssetIds();

    crossMarginService = _crossMarginService;
    pyth = _pyth;
    minExecutionOrderFee = _minExecutionOrderFee;
  }

  /**
   * Modifiers
   */

  /// @notice Validate only accepted collateral tokens to be deposited or withdrawn
  modifier onlyAcceptedToken(address _token) {
    ConfigStorage(CrossMarginService(crossMarginService).configStorage()).validateAcceptedCollateral(_token);
    _;
  }

  /// @notice Validate only whitelisted executors to call function
  modifier onlyOrderExecutor() {
    if (!orderExecutors[msg.sender]) revert ICrossMarginHandler02_NotWhitelisted();
    _;
  }

  modifier delegate(address _mainAccount) {
    if (delegations[_mainAccount] == msg.sender) {
      _senderOverride = _mainAccount;
    }
    _;
    _senderOverride = address(0);
  }

  function _msgSender() internal view override returns (address) {
    if (_senderOverride == address(0)) {
      return msg.sender;
    } else {
      return _senderOverride;
    }
  }

  /**
   * Deposit Collateral
   */

  /// @notice Deposits the specified amount of collateral token into the user's sub-account.
  /// @param _mainAccount main address of user
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to deposit.
  /// @param _amount Amount of collateral token to deposit.
  /// @param _shouldWrap Whether to wrap native ETH into WETH before depositing.
  function depositCollateral(
    address _mainAccount,
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    bool _shouldWrap
  ) external payable nonReentrant onlyAcceptedToken(_token) delegate(_mainAccount) {
    if (_amount == 0) revert ICrossMarginHandler02_BadAmount();
    if (_mainAccount != _msgSender()) revert ICrossMarginHandler02_Unauthorized();
    // SLOAD
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);

    if (_shouldWrap) {
      // Prevent mismatch msgValue and the input amount
      if (msg.value != _amount) {
        revert ICrossMarginHandler02_MismatchMsgValue();
      }

      // Wrap the native to wNative. The _token must be wNative.
      // If not, it would revert transfer amount exceed on the next line.
      // slither-disable-next-line arbitrary-send-eth
      IWNative(_token).deposit{ value: _amount }();
      // Transfer those wNative token from this contract to VaultStorage
      ERC20Upgradeable(_token).safeTransfer(_crossMarginService.vaultStorage(), _amount);
    } else {
      // Transfer depositing token from trader's wallet to VaultStorage
      ERC20Upgradeable(_token).safeTransferFrom(_msgSender(), _crossMarginService.vaultStorage(), _amount);
    }

    // Call service to deposit collateral
    _crossMarginService.depositCollateral(_msgSender(), _subAccountId, _token, _amount);

    emit LogDepositCollateral(_msgSender(), _subAccountId, _token, _amount);
  }

  /**
   * Withdraw Collateral
   */

  /// @notice Creates a new withdraw order to withdraw the specified amount of collateral token from the user's sub-account.
  /// @param _mainAccount main address of user
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to withdraw.
  /// @param _amount Amount of collateral token to withdraw.
  /// @param _executionFee Execution fee to pay for this order.
  /// @param _shouldUnwrap Whether to unwrap WETH into native ETH after withdrawing.
  function createWithdrawCollateralOrder(
    address _mainAccount,
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable nonReentrant onlyAcceptedToken(_token) delegate(_mainAccount) returns (uint256 _orderIndex) {
    if (_mainAccount != _msgSender()) revert ICrossMarginHandler02_Unauthorized();
    if (_amount == 0) revert ICrossMarginHandler02_BadAmount();
    if (_executionFee < minExecutionOrderFee) revert ICrossMarginHandler02_InsufficientExecutionFee();
    if (msg.value != _executionFee) revert ICrossMarginHandler02_InCorrectValueTransfer();
    if (_shouldUnwrap && _token != ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth())
      revert ICrossMarginHandler02_NotWNativeToken();

    // convert native to WNative (including executionFee)
    _transferInETH();

    // Get the sub-account and order index for the limit order
    address subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    _orderIndex = withdrawOrdersIndex[subAccount];

    WithdrawOrder memory order = WithdrawOrder({
      account: payable(_msgSender()),
      orderIndex: _orderIndex,
      token: _token,
      amount: _amount,
      executionFee: _executionFee,
      shouldUnwrap: _shouldUnwrap,
      subAccountId: _subAccountId,
      createdTimestamp: uint48(block.timestamp),
      executedTimestamp: 0,
      status: WithdrawOrderStatus.PENDING
    });

    _addOrder(order, subAccount, _orderIndex);

    emit LogCreateWithdrawOrder(
      _msgSender(),
      _subAccountId,
      _orderIndex,
      _token,
      _amount,
      _executionFee,
      _shouldUnwrap
    );
  }

  function executeOrders(
    address[] memory _accounts,
    uint8[] memory _subAccountIds,
    uint256[] memory _orderIndexes,
    address payable _feeReceiver,
    bytes32[] memory _priceData,
    bytes32[] memory _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas,
    bool _isRevert
  ) external nonReentrant onlyOrderExecutor {
    if (_accounts.length != _subAccountIds.length || _accounts.length != _orderIndexes.length)
      revert ICrossMarginHandler02_InvalidArraySize();

    IEcoPyth(pyth).updatePriceFeeds(_priceData, _publishTimeData, _minPublishTime, _encodedVaas);

    ExecuteOrderVars memory vars;
    vars.feeReceiver = _feeReceiver;
    vars.priceData = _priceData;
    vars.publishTimeData = _publishTimeData;
    vars.minPublishTime = _minPublishTime;
    vars.encodedVaas = _encodedVaas;

    uint256 totalFeeReceived;
    uint256 length = _accounts.length;
    for (uint256 i = 0; i < length; ) {
      totalFeeReceived += _executeOrder(vars, _accounts[i], _subAccountIds[i], _orderIndexes[i], _isRevert);

      unchecked {
        ++i;
      }
    }
    _transferOutETH(totalFeeReceived, _feeReceiver);
  }

  /// @notice Executes a single withdraw order by transferring the specified amount of collateral token to the user's wallet.
  /// @param _order WithdrawOrder struct representing the order to execute.
  function executeWithdrawOrder(WithdrawOrder memory _order) external {
    // if not in executing state, then revert
    if (msg.sender != address(this)) revert ICrossMarginHandler02_Unauthorized();
    // SLOAD
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);
    if (_order.shouldUnwrap && _order.token != ConfigStorage(_crossMarginService.configStorage()).weth())
      revert ICrossMarginHandler02_NotWNativeToken();

    // Call service to withdraw collateral
    if (_order.shouldUnwrap) {
      // Withdraw wNative straight to this contract first.
      _crossMarginService.withdrawCollateral(
        _order.account,
        _order.subAccountId,
        _order.token,
        _order.amount,
        address(this)
      );
      _transferOutETH(_order.amount, _order.account);
    } else {
      // Withdraw _token straight to the user
      _crossMarginService.withdrawCollateral(
        _order.account,
        _order.subAccountId,
        _order.token,
        _order.amount,
        _order.account
      );
    }

    emit LogWithdrawCollateral(_order.account, _order.subAccountId, _order.token, _order.amount);
  }

  /// @notice Cancels the specified withdraw order.
  /// @param _mainAccount main address of user
  /// @param _subAccountId ID of the user's sub-account
  /// @param _orderIndex index of user's order
  function cancelWithdrawOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex
  ) external nonReentrant delegate(_mainAccount) {
    _cancelWithdrawOrder(_msgSender(), _subAccountId, _orderIndex);
  }

  /**
   * Internals
   */

  function _executeOrder(
    ExecuteOrderVars memory vars,
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    bool _isRevert
  ) internal returns (uint256 _totalFeeReceiver) {
    vars.subAccount = HMXLib.getSubAccount(_account, _subAccountId);
    vars.order = withdrawOrders[vars.subAccount][_orderIndex];
    vars.orderIndex = _orderIndex;

    // Check if this order still exists
    if (vars.order.account == address(0)) revert ICrossMarginHandler02_NonExistentOrder();

    // ignore this order, if amount = 0
    if (vars.order.amount == 0) return 0;

    // try executing order
    try this.executeWithdrawOrder(vars.order) {
      _handleOrderSuccess(vars.subAccount, _orderIndex);
    } catch Error(string memory errMsg) {
      _handleOrderFail(vars, bytes(errMsg), _isRevert);
    } catch Panic(uint /*errorCode*/) {
      _handleOrderFail(vars, bytes("Panic occurred while executing the withdraw order"), _isRevert);
    } catch (bytes memory errMsg) {
      _handleOrderFail(vars, errMsg, _isRevert);
    }

    _totalFeeReceiver = vars.order.executionFee;
  }

  function _cancelWithdrawOrder(address _account, uint8 _subAccountId, uint256 _orderIndex) internal {
    address subAccount = HMXLib.getSubAccount(_account, _subAccountId);
    // SLOAD
    WithdrawOrder memory _order = withdrawOrders[subAccount][_orderIndex];

    // Check if this order still exists
    if (_order.account == address(0)) revert ICrossMarginHandler02_NonExistentOrder();
    // validate if msg.sender is not owned the order, then revert
    if (_msgSender() != _order.account && !orderExecutors[_msgSender()]) revert ICrossMarginHandler02_NotOrderOwner();

    _removeOrder(subAccount, _orderIndex);

    // refund the _order.executionFee if the caller is not executor
    if (!orderExecutors[_msgSender()]) {
      _transferOutETH(_order.executionFee, _order.account);
    }

    emit LogCancelWithdrawOrder(
      payable(_order.account),
      _order.subAccountId,
      _orderIndex,
      _order.token,
      _order.amount,
      _order.executionFee,
      _order.shouldUnwrap
    );

    delete withdrawOrders[subAccount][_orderIndex];
  }

  function _addOrder(WithdrawOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    withdrawOrdersIndex[_subAccount] = _orderIndex + 1;
    withdrawOrders[_subAccount][_orderIndex] = _order;

    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.add(_pointer);
    _subAccountActiveOrderPointers[_subAccount].add(_pointer);
  }

  function _handleOrderSuccess(address _subAccount, uint256 _orderIndex) internal {
    _removeOrder(_subAccount, _orderIndex);

    WithdrawOrder storage order = withdrawOrders[_subAccount][_orderIndex];
    order.status = WithdrawOrderStatus.SUCCESS;
    order.executedTimestamp = uint48(block.timestamp);
    // Execution succeeded, store the executed order pointer
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _executedOrderPointers.add(_pointer);
    _subAccountExecutedOrderPointers[_subAccount].add(_pointer);
  }

  function _removeOrder(address _subAccount, uint256 _orderIndex) internal {
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.remove(_pointer);
    _subAccountActiveOrderPointers[_subAccount].remove(_pointer);
  }

  function _handleOrderFail(ExecuteOrderVars memory vars, bytes memory errMsg, bool _isRevert) internal {
    if (_isRevert) {
      require(false, string(errMsg));
    } else {
      emit LogExecuteWithdrawOrder(
        vars.order.account,
        vars.order.subAccountId,
        vars.orderIndex,
        vars.order.token,
        vars.order.amount,
        vars.order.shouldUnwrap,
        false,
        string(errMsg)
      );

      vars.order.status = WithdrawOrderStatus.FAIL;
      _cancelWithdrawOrder(vars.order.account, vars.order.subAccountId, vars.orderIndex);
    }
  }

  function _getOrders(
    EnumerableSet.UintSet storage _pointers,
    uint256 _limit,
    uint256 _offset
  ) internal view returns (WithdrawOrder[] memory _orders) {
    uint256 _len = _pointers.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _orders;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _orders = new WithdrawOrder[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      (address _account, uint96 _index) = _decodePointer(_pointers.at(i));
      WithdrawOrder memory _order = withdrawOrders[_account][_index];

      _orders[i - _offset] = _order;
      unchecked {
        ++i;
      }
    }

    return _orders;
  }

  function _encodePointer(address _account, uint96 _index) internal pure returns (uint256 _pointer) {
    return uint256(bytes32(abi.encodePacked(_account, _index)));
  }

  function _decodePointer(uint256 _pointer) internal pure returns (address _account, uint96 _index) {
    return (address(uint160(_pointer >> 96)), uint96(_pointer));
  }

  /**
   * Getters
   */

  function getAllActiveOrders(uint256 _limit, uint256 _offset) external view returns (WithdrawOrder[] memory _orders) {
    return _getOrders(_activeOrderPointers, _limit, _offset);
  }

  function getAllExecutedOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _orders) {
    return _getOrders(_executedOrderPointers, _limit, _offset);
  }

  function getAllActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _orders) {
    return _getOrders(_subAccountActiveOrderPointers[_subAccount], _limit, _offset);
  }

  function getAllExecutedOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _orders) {
    return _getOrders(_subAccountExecutedOrderPointers[_subAccount], _limit, _offset);
  }

  /**
   * Setters
   */
  function setDelegate(address _delegate) external {
    delegations[msg.sender] = _delegate;
    emit LogSetDelegate(msg.sender, _delegate);
  }

  /// @notice Sets a new CrossMarginService contract address.
  /// @param _crossMarginService The new CrossMarginService contract address.
  function setCrossMarginService(address _crossMarginService) external nonReentrant onlyOwner {
    if (_crossMarginService == address(0)) revert ICrossMarginHandler02_InvalidAddress();
    emit LogSetCrossMarginService(crossMarginService, _crossMarginService);
    crossMarginService = _crossMarginService;

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
  }

  /// @notice Sets a new Pyth contract address.
  /// @param _pyth The new Pyth contract address.
  function setPyth(address _pyth) external nonReentrant onlyOwner {
    if (_pyth == address(0)) revert ICrossMarginHandler02_InvalidAddress();
    emit LogSetPyth(pyth, _pyth);
    pyth = _pyth;

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  /// @notice setMinExecutionFee
  /// @param _newMinExecutionFee minExecutionFee in ethers
  function setMinExecutionFee(uint256 _newMinExecutionFee) external nonReentrant onlyOwner {
    emit LogSetMinExecutionFee(minExecutionOrderFee, _newMinExecutionFee);
    minExecutionOrderFee = _newMinExecutionFee;
  }

  /// @notice setOrderExecutor
  /// @param _executor address who will be executor
  /// @param _isAllow flag to allow to execute
  function setOrderExecutor(address _executor, bool _isAllow) external nonReentrant onlyOwner {
    orderExecutors[_executor] = _isAllow;
    emit LogSetOrderExecutor(_executor, _isAllow);
  }

  /**
   * Private Functions
   */

  /// @notice Transfer in ETH from user to be used as execution fee
  /// @dev The received ETH will be wrapped into WETH and store in this contract for later use.
  function _transferInETH() private {
    IWNative(ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()).deposit{
      value: msg.value
    }();
  }

  /// @notice Transfer out ETH to the receiver
  /// @dev The stored WETH will be unwrapped and transfer as native token
  /// @param _amountOut Amount of ETH to be transferred
  /// @param _receiver The receiver of ETH in its native form. The receiver must be able to accept native token.
  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);
    IWNative(ConfigStorage(_crossMarginService.configStorage()).weth()).withdraw(_amountOut);
    // slither-disable-next-line arbitrary-send-eth
    // To mitigate potential attacks, the call method is utilized,
    // allowing the contract to bypass any revert calls from the destination address.
    // By setting the gas limit to 2300, equivalent to the gas limit of the transfer method,
    // the transaction maintains a secure execution."
    (bool success, ) = _receiver.call{ value: _amountOut, gas: 2300 }("");
    // send WNative instead when native token transfer fail
    if (!success) {
      address weth = ConfigStorage(_crossMarginService.configStorage()).weth();
      IWNative(weth).deposit{ value: _amountOut }();
      IWNative(weth).transfer(_receiver, _amountOut);
    }
  }

  receive() external payable {
    // @dev Cannot enable this check due to Solidity Fallback Function Gas Limit introduced in 0.8.17.
    // ref - https://stackoverflow.com/questions/74930609/solidity-fallback-function-gas-limit
    // require(msg.sender == ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth());
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
