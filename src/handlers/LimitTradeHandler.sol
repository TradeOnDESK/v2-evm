// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// base
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCastUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { AddressUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/AddressUpgradeable.sol";

// contracts
import { OracleMiddleware } from "@hmx/oracles/OracleMiddleware.sol";
import { TradeService } from "@hmx/services/TradeService.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";

// interfaces
import { ILimitTradeHandler } from "./interfaces/ILimitTradeHandler.sol";
import { IWNative } from "../interfaces/IWNative.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { LimitTradeHelper } from "@hmx/helpers/LimitTradeHelper.sol";

/// @title LimitTradeHandler
/// @notice This contract handles the create, update, and cancel for the Trading module.
contract LimitTradeHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, ILimitTradeHandler {
  using EnumerableSet for EnumerableSet.UintSet;
  using SafeCastUpgradeable for uint256;
  using SafeCastUpgradeable for int256;

  /**
   * Events
   */
  event LogSetTradeService(address oldValue, address newValue);
  event LogSetMinExecutionFee(uint64 oldValue, uint64 newValue);
  event LogSetIsAllowAllExecutor(bool oldValue, bool newValue);
  event LogSetMinExecutionTimestamp(uint32 oldValue, uint32 newValue);
  event LogSetOrderExecutor(address executor, bool isAllow);
  event LogSetPyth(address oldValue, address newValue);
  event LogCreateLimitOrder(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    uint256 acceptablePrice,
    bool triggerAboveThreshold,
    uint256 executionFee,
    bool reduceOnly,
    address tpToken
  );
  event LogExecuteMarketOrderFail(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    uint256 executionFee,
    bool reduceOnly,
    address tpToken,
    bytes errMsg
  );
  event LogExecuteLimitOrder(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    uint256 executionFee,
    uint256 executionPrice,
    bool reduceOnly,
    address tpToken
  );
  event LogUpdateLimitOrder(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    bool reduceOnly,
    address tpToken
  );
  event LogCancelLimitOrder(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    uint256 executionFee,
    bool reduceOnly,
    address tpToken
  );
  event LogSetGuaranteeLimitPrice(bool isActive);
  event LogSetDelegate(address sender, address delegate);
  event LogExecuteLimitOrderFail(
    address indexed account,
    uint256 indexed subAccountId,
    uint256 orderIndex,
    uint256 marketIndex,
    int256 sizeDelta,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    uint256 executionFee,
    bool reduceOnly,
    address tpToken,
    bytes errMsg
  );

  /**
   * Structs
   */

  struct ExecuteOrderVars {
    LimitOrder order;
    address subAccount;
    bytes32 positionId;
    bytes32 encodedVaas;
    bytes32[] priceData;
    bytes32[] publishTimeData;
    address payable feeReceiver;
    uint256 orderIndex;
    uint256 minPublishTime;
    bool positionIsLong;
    bool isNewPosition;
    bool isMarketOrder;
    int256 sizeDelta;
  }

  struct ValidatePositionOrderPriceVars {
    ConfigStorage.MarketConfig marketConfig;
    OracleMiddleware oracle;
    PerpStorage.Market globalMarket;
    uint256 oraclePrice;
    uint256 adaptivePrice;
    uint8 marketStatus;
    bool isPriceValid;
  }

  /**
   * Constants
   */
  uint8 internal constant BUY = 0;
  uint8 internal constant SELL = 1;
  uint64 internal constant MAX_EXECUTION_FEE = 5 ether;

  /**
   * States
   */
  IEcoPyth public pyth;
  address public weth;
  address public tradeService;
  address private senderOverride;

  uint64 public minExecutionFee; // Minimum execution fee to be collected by the order executor addresses for gas
  uint32 public minExecutionTimestamp; // Minimum execution timestamp using on market order to validate on order stale
  bool public isAllowAllExecutor; // If this is true, everyone can execute limit orders
  bool public isGuaranteeLimitPrice; // If this is ture, Gurantee Limit Price feature will be turned on. Limit Price set by orders will be used instead of the current Oracle Price.

  mapping(address => bool) public orderExecutors; // The allowed addresses to execute limit orders
  mapping(address => mapping(uint256 => LimitOrder)) public limitOrders; // Array of Limit Orders of each sub-account
  mapping(address => uint256) public limitOrdersIndex; // The last limit order index of each sub-account
  mapping(address => address) public delegations; // The mapping of mainAccount => Smart Wallet to be used for Account Abstraction

  // Pointers
  EnumerableSet.UintSet private activeOrderPointers;
  EnumerableSet.UintSet private activeMarketOrderPointers;
  EnumerableSet.UintSet private activeLimitOrderPointers;

  mapping(address => EnumerableSet.UintSet) private subAccountActiveOrderPointers;
  mapping(address => EnumerableSet.UintSet) private subAccountActiveMarketOrderPointers;
  mapping(address => EnumerableSet.UintSet) private subAccountActiveLimitOrderPointers;

  LimitTradeHelper public limitTradeHelper;

  /// @notice Initializes the CrossMarginHandler contract with the provided configuration parameters.
  /// @param _weth Address of WETH.
  /// @param _tradeService Address of the TradeService contract.
  /// @param _pyth Address of the Pyth contract.
  /// @param _minExecutionFee Minimum execution fee for a trading order.
  /// @param _minExecutionTimestamp If the order lives longer than this config, the order is stale and should be cancelled.
  function initialize(
    address _weth,
    address _tradeService,
    address _pyth,
    uint64 _minExecutionFee,
    uint32 _minExecutionTimestamp
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    if (_minExecutionFee > MAX_EXECUTION_FEE) revert ILimitTradeHandler_MaxExecutionFee();

    minExecutionFee = _minExecutionFee;
    minExecutionTimestamp = _minExecutionTimestamp;
    weth = _weth;
    tradeService = _tradeService;
    pyth = IEcoPyth(_pyth);
    isAllowAllExecutor = false;
    isGuaranteeLimitPrice = false;

    // Sanity check
    // slither-disable-next-line unused-return
    TradeService(_tradeService).perpStorage();
    IEcoPyth(_pyth).getAssetIds();
  }

  receive() external payable {
    if (msg.sender != weth) revert ILimitTradeHandler_InvalidSender();
  }

  /**
   * Modifiers
   */

  // Only whitelisted addresses can be able to execute limit orders
  modifier onlyOrderExecutor() {
    if (!orderExecutors[msg.sender]) revert ILimitTradeHandler_NotWhitelisted();
    _;
  }

  // Only whitelisted addresses or owner can be able to execute limit orders
  modifier onlyOrderExecutorOrOwner() {
    if (!orderExecutors[msg.sender] && msg.sender != owner()) revert ILimitTradeHandler_NotWhitelistedOrNotOwner();
    _;
  }

  modifier delegate(address _mainAccount) {
    if (delegations[_mainAccount] == msg.sender) {
      senderOverride = _mainAccount;
    }
    _;
    senderOverride = address(0);
  }

  function _msgSender() internal view override returns (address) {
    if (senderOverride == address(0)) {
      return msg.sender;
    } else {
      return senderOverride;
    }
  }

  /**
   * Core Functions
   */
  function setDelegate(address _delegate) external {
    delegations[msg.sender] = _delegate;
    emit LogSetDelegate(msg.sender, _delegate);
  }

  function createOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    bool _triggerAboveThreshold,
    uint256 _executionFee,
    bool _reduceOnly,
    address _tpToken
  ) external payable nonReentrant delegate(_mainAccount) {
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_mainAccount != _msgSender()) revert ILimitTradeHandler_Unauthorized();
    // Check if execution fee is lower than minExecutionFee, then it's too low. We won't allow it.
    if (_executionFee < uint256(minExecutionFee)) revert ILimitTradeHandler_InsufficientExecutionFee();
    // The attached native token must be equal to _executionFee
    if (msg.value != _executionFee) revert ILimitTradeHandler_IncorrectValueTransfer();
    // Transfer in the native token to be used as execution fee
    _transferInETH();

    _createOrder(
      _subAccountId,
      _marketIndex,
      _sizeDelta,
      _triggerPrice,
      _acceptablePrice,
      _triggerAboveThreshold,
      _executionFee,
      _reduceOnly,
      _tpToken
    );
  }

  /// @notice Create a new limit order
  /// @param _subAccountId Sub-account Id
  /// @param _marketIndex Market Index
  /// @param _sizeDelta How much the position size will change in USD (1e30), can be negative for INCREASE order
  /// @param _triggerPrice The price that this limit order will be triggered
  /// @param _acceptablePrice The acceptable price for the order
  /// @param _triggerAboveThreshold The current price must go above/below the trigger price for the order to be executed
  /// @param _executionFee The execution fee of this limit order
  /// @param _reduceOnly If true, it's a Reduce-Only order which will not flip the side of the position
  /// @param _tpToken Take profit token, when trader has profit
  function createOrder(
    uint8 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    bool _triggerAboveThreshold,
    uint256 _executionFee,
    bool _reduceOnly,
    address _tpToken
  ) external payable nonReentrant {
    // Check if execution fee is lower than minExecutionFee, then it's too low. We won't allow it.
    if (_executionFee < uint256(minExecutionFee)) revert ILimitTradeHandler_InsufficientExecutionFee();
    // The attached native token must be equal to _executionFee
    if (msg.value != _executionFee) revert ILimitTradeHandler_IncorrectValueTransfer();
    // Transfer in the native token to be used as execution fee
    _transferInETH();

    _createOrder(
      _subAccountId,
      _marketIndex,
      _sizeDelta,
      _triggerPrice,
      _acceptablePrice,
      _triggerAboveThreshold,
      _executionFee,
      _reduceOnly,
      _tpToken
    );
  }

  struct BatchCreateOrderLocalVars {
    uint256 marketIndex;
    int256 sizeDelta;
    uint256 triggerPrice;
    uint256 acceptablePrice;
    bool triggerAboveThreshold;
    uint256 executionFee;
    bool reduceOnly;
    address tpToken;
  }

  struct BatchUpdateOrderLocalVars {
    uint256 orderIndex;
    int256 sizeDelta;
    uint256 triggerPrice;
    uint256 acceptablePrice;
    bool triggerAboveThreshold;
    bool reduceOnly;
    address tpToken;
  }

  /// @notice Batch multiple commands to a one single transaction.
  /// @dev Support delegate and enforce a hard auth.
  /// @dev This is useful for a better UX to handle TP/SL.
  /// @param _mainAccount The owner of these actions.
  /// @param _subAccountId The sub account id.
  /// @param _cmds The commands to be executed.
  /// @param _datas The data for each command.
  function batch(
    address _mainAccount,
    uint8 _subAccountId,
    Command[] calldata _cmds,
    bytes[] calldata _datas
  ) external payable nonReentrant delegate(_mainAccount) {
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_mainAccount != _msgSender()) revert ILimitTradeHandler_Unauthorized();
    // Check if _cmds's len match with _data's len
    if (_cmds.length != _datas.length) revert ILimitTradeHandler_BadCalldata();

    // Execute commands
    // _expectedMsgValue is used for check after cmds are executed
    uint256 _expectedMsgValue = 0;
    for (uint i = 0; i < _cmds.length; ) {
      if (_cmds[i] == Command.Create) {
        // Perform the create order command
        BatchCreateOrderLocalVars memory _localVars;
        (
          _localVars.marketIndex,
          _localVars.sizeDelta,
          _localVars.triggerPrice,
          _localVars.acceptablePrice,
          _localVars.triggerAboveThreshold,
          _localVars.executionFee,
          _localVars.reduceOnly,
          _localVars.tpToken
        ) = abi.decode(_datas[i], (uint256, int256, uint256, uint256, bool, uint256, bool, address));
        // Check execution fee to make sure it is > minExecution before create an order.
        if (_localVars.executionFee < minExecutionFee) revert ILimitTradeHandler_InsufficientExecutionFee();
        // Optimistically create order here w/o checking if provided msg.value
        // is enough to execution fee here, but will check after finished all cmds.
        _createOrder(
          _subAccountId,
          _localVars.marketIndex,
          _localVars.sizeDelta,
          _localVars.triggerPrice,
          _localVars.acceptablePrice,
          _localVars.triggerAboveThreshold,
          _localVars.executionFee,
          _localVars.reduceOnly,
          _localVars.tpToken
        );
        // Update expectedMsgValue
        _expectedMsgValue += _localVars.executionFee;
      } else if (_cmds[i] == Command.Update) {
        BatchUpdateOrderLocalVars memory _localVars;
        (
          _localVars.orderIndex,
          _localVars.sizeDelta,
          _localVars.triggerPrice,
          _localVars.acceptablePrice,
          _localVars.triggerAboveThreshold,
          _localVars.reduceOnly,
          _localVars.tpToken
        ) = abi.decode(_datas[i], (uint256, int256, uint256, uint256, bool, bool, address));
        _updateOrder(
          _mainAccount,
          _subAccountId,
          _localVars.orderIndex,
          _localVars.sizeDelta,
          _localVars.triggerPrice,
          _localVars.acceptablePrice,
          _localVars.triggerAboveThreshold,
          _localVars.reduceOnly,
          _localVars.tpToken
        );
      } else if (_cmds[i] == Command.Cancel) {
        // Perform the cancel order command
        uint256 _orderIndex = abi.decode(_datas[i], (uint256));
        address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
        LimitOrder memory _order = limitOrders[_subAccount][_orderIndex];
        // Check if order still exists
        if (_order.account == address(0)) revert ILimitTradeHandler_NonExistentOrder();
        _cancelOrder(_order, _subAccount, _orderIndex);
      }

      unchecked {
        ++i;
      }
    }

    // Check if msg.value equals to _expectedMsgValue
    // This is a bit anti-check/effect/interaction pattern
    // but it's the best way to make sure that the msg.value is enough
    if (msg.value != _expectedMsgValue) revert ILimitTradeHandler_InsufficientExecutionFee();
    // Transfer in the native token to be used as execution fee
    _transferInETH();
  }

  function _createOrder(
    uint8 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    bool _triggerAboveThreshold,
    uint256 _executionFee,
    bool _reduceOnly,
    address _tpToken
  ) internal {
    // Get the sub-account and order index for the limit order
    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    uint256 _orderIndex = limitOrdersIndex[_subAccount];

    if (address(limitTradeHelper) != address(0))
      limitTradeHelper.validate(_msgSender(), _subAccountId, _marketIndex, _reduceOnly, _sizeDelta, true);

    // Create the limit order
    LimitOrder memory _order = LimitOrder({
      account: _msgSender(),
      subAccountId: _subAccountId,
      orderIndex: _orderIndex,
      marketIndex: _marketIndex,
      sizeDelta: _sizeDelta,
      triggerPrice: _triggerPrice,
      acceptablePrice: _acceptablePrice,
      triggerAboveThreshold: _triggerPrice == 0 ? true : _triggerAboveThreshold,
      executionFee: _executionFee,
      reduceOnly: _reduceOnly,
      tpToken: _tpToken,
      createdTimestamp: block.timestamp
    });

    // Insert the limit order into the list
    _addOrder(_order, _subAccount, _orderIndex);

    emit LogCreateLimitOrder(
      _msgSender(),
      _subAccountId,
      _orderIndex,
      _marketIndex,
      _sizeDelta,
      _triggerPrice,
      _acceptablePrice,
      _triggerAboveThreshold,
      _executionFee,
      _reduceOnly,
      _tpToken
    );
  }

  /// @notice Execute a limit order
  /// @param _accounts the primary account of the order
  /// @param _subAccountIds Sub-account Id
  /// @param _orderIndexes Order Index which could be retrieved from the emitted event from `createOrder()`
  /// @param _feeReceiver Which address will receive the execution fee for this transaction
  /// @param _priceData Price data from the Pyth oracle.
  /// @param _publishTimeData Publish time data from the Pyth oracle.
  /// @param _minPublishTime Minimum publish time for the Pyth oracle data.
  /// @param _encodedVaas Encoded VaaS data for the Pyth oracle.
  /// @param _isRevert If true, when limit order failed to execute, this function will revert.
  function executeOrders(
    address[] memory _accounts,
    uint8[] memory _subAccountIds,
    uint256[] memory _orderIndexes,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas,
    bool _isRevert
  ) external nonReentrant onlyOrderExecutor {
    _executeOrders(
      _accounts,
      _subAccountIds,
      _orderIndexes,
      _feeReceiver,
      _priceData,
      _publishTimeData,
      _minPublishTime,
      _encodedVaas,
      _isRevert
    );
  }

  function executeOrders(
    address[] memory _accounts,
    uint8[] memory _subAccountIds,
    uint256[] memory _orderIndexes,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external nonReentrant onlyOrderExecutor {
    _executeOrders(
      _accounts,
      _subAccountIds,
      _orderIndexes,
      _feeReceiver,
      _priceData,
      _publishTimeData,
      _minPublishTime,
      _encodedVaas,
      false
    );
  }

  function _executeOrders(
    address[] memory _accounts,
    uint8[] memory _subAccountIds,
    uint256[] memory _orderIndexes,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas,
    bool _isRevert
  ) internal {
    if (_accounts.length != _subAccountIds.length || _accounts.length != _orderIndexes.length)
      revert ILimitTradeHandler_InvalidArraySize();

    // Update price to Pyth
    pyth.updatePriceFeeds(_priceData, _publishTimeData, _minPublishTime, _encodedVaas);

    ExecuteOrderVars memory vars;
    vars.feeReceiver = _feeReceiver;
    vars.priceData = _priceData;
    vars.publishTimeData = _publishTimeData;
    vars.minPublishTime = _minPublishTime;
    vars.encodedVaas = _encodedVaas;

    // Loop through order list
    for (uint256 i = 0; i < _accounts.length; ) {
      _executeOrder(vars, _accounts[i], _subAccountIds[i], _orderIndexes[i], _isRevert);

      unchecked {
        ++i;
      }
    }
  }

  function _executeOrder(
    ExecuteOrderVars memory vars,
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    bool _isRevert
  ) internal {
    vars.subAccount = HMXLib.getSubAccount(_account, _subAccountId);
    vars.order = limitOrders[vars.subAccount][_orderIndex];
    vars.orderIndex = _orderIndex;
    vars.isMarketOrder = vars.order.triggerAboveThreshold && vars.order.triggerPrice == 0;

    // Check if this order still exists
    if (vars.order.account == address(0)) revert ILimitTradeHandler_NonExistentOrder();

    // Check if the order is a market order and is stale
    if (vars.isMarketOrder && block.timestamp > vars.order.createdTimestamp + uint256(minExecutionTimestamp)) {
      _cancelOrder(vars.order, vars.subAccount, vars.orderIndex);
      return;
    }

    // try executing order
    try this.executeLimitOrder(vars) {
      // Execution succeeded
    } catch Error(string memory errMsg) {
      _handleOrderFail(vars, bytes(errMsg), _isRevert);
    } catch Panic(uint /*errorCode*/) {
      _handleOrderFail(vars, bytes("Panic occurred while executing the limit order"), _isRevert);
    } catch (bytes memory errMsg) {
      _handleOrderFail(vars, errMsg, _isRevert);
    }
  }

  function _handleOrderFail(ExecuteOrderVars memory vars, bytes memory errMsg, bool _isRevert) internal {
    // Handle the error depending on the type of order
    if (vars.isMarketOrder) {
      // Cancel market order and transfer execution fee to executor
      _removeOrder(vars.order, vars.subAccount, vars.orderIndex);
      _transferOutETH(vars.order.executionFee, vars.feeReceiver);

      emit LogExecuteMarketOrderFail(
        vars.order.account,
        vars.order.subAccountId,
        vars.orderIndex,
        vars.order.marketIndex,
        vars.order.sizeDelta,
        vars.order.triggerPrice,
        vars.order.triggerAboveThreshold,
        vars.order.executionFee,
        vars.order.reduceOnly,
        vars.order.tpToken,
        errMsg
      );
    } else {
      if (_isRevert) {
        // Revert with the error message
        require(false, string(errMsg));
      } else {
        emit LogExecuteLimitOrderFail(
          vars.order.account,
          vars.order.subAccountId,
          vars.orderIndex,
          vars.order.marketIndex,
          vars.order.sizeDelta,
          vars.order.triggerPrice,
          vars.order.triggerAboveThreshold,
          vars.order.executionFee,
          vars.order.reduceOnly,
          vars.order.tpToken,
          errMsg
        );
      }
    }
  }

  function executeLimitOrder(ExecuteOrderVars memory vars) external {
    // if not in executing state, then revert
    if (msg.sender != address(this)) revert ILimitTradeHandler_Unauthorized();

    // SLOADs
    TradeService _tradeService = TradeService(tradeService);
    bool _isGuaranteeLimitPrice = isGuaranteeLimitPrice;

    // Remove this executed order from the list
    _removeOrder(vars.order, vars.subAccount, vars.orderIndex);

    // Retrieve existing position
    vars.positionId = HMXLib.getPositionId(vars.subAccount, vars.order.marketIndex);
    PerpStorage.Position memory _existingPosition = PerpStorage(_tradeService.perpStorage()).getPositionById(
      vars.positionId
    );

    if (address(limitTradeHelper) != address(0))
      limitTradeHelper.validate(
        vars.order.account,
        vars.order.subAccountId,
        vars.order.marketIndex,
        vars.order.reduceOnly,
        vars.order.sizeDelta,
        true
      );

    vars.positionIsLong = _existingPosition.positionSizeE30 > 0;
    vars.isNewPosition = _existingPosition.positionSizeE30 == 0;

    // Validate if the current price is valid for the execution of this order
    // Handle the sizeDelta in case it is sent with max int 256
    vars.sizeDelta = vars.order.sizeDelta;
    if (vars.order.sizeDelta == type(int256).max || vars.order.sizeDelta == type(int256).min) {
      if (vars.order.sizeDelta > 0) {
        vars.sizeDelta = int256(HMXLib.abs(_existingPosition.positionSizeE30));
      } else {
        vars.sizeDelta = -int256(HMXLib.abs(_existingPosition.positionSizeE30));
      }
    }
    if (vars.sizeDelta == 0) revert ILimitTradeHandler_BadSizeDelta();
    (uint256 _currentPrice, ) = _validatePositionOrderPrice(
      vars.order.triggerAboveThreshold,
      vars.order.triggerPrice,
      vars.order.acceptablePrice,
      vars.order.marketIndex,
      vars.sizeDelta,
      vars.sizeDelta > 0
    );

    // Execute the order
    if (vars.order.reduceOnly) {
      bool isDecreaseShort = (vars.sizeDelta > 0 && _existingPosition.positionSizeE30 < 0);
      bool isDecreaseLong = (vars.sizeDelta < 0 && _existingPosition.positionSizeE30 > 0);
      bool isClosePosition = !vars.isNewPosition && (isDecreaseShort || isDecreaseLong);
      if (isClosePosition) {
        _tradeService.decreasePosition({
          _account: vars.order.account,
          _subAccountId: vars.order.subAccountId,
          _marketIndex: vars.order.marketIndex,
          _positionSizeE30ToDecrease: HMXLib.min(
            HMXLib.abs(vars.sizeDelta),
            HMXLib.abs(_existingPosition.positionSizeE30)
          ),
          _tpToken: vars.order.tpToken,
          _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
        });
      } else {
        // Do nothing if the size delta is wrong for reduce-only
      }
    } else {
      if (vars.sizeDelta > 0) {
        // BUY
        if (vars.isNewPosition || vars.positionIsLong) {
          // New position and Long position
          // just increase position when BUY
          _tradeService.increasePosition({
            _primaryAccount: vars.order.account,
            _subAccountId: vars.order.subAccountId,
            _marketIndex: vars.order.marketIndex,
            _sizeDelta: vars.sizeDelta,
            _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
          });
        } else {
          bool _flipSide = vars.sizeDelta > (-_existingPosition.positionSizeE30);
          if (_flipSide) {
            // Flip the position
            // Fully close Short position
            _tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(-_existingPosition.positionSizeE30),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
            // Flip it to Long position
            _tradeService.increasePosition({
              _primaryAccount: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _sizeDelta: vars.sizeDelta + _existingPosition.positionSizeE30,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
          } else {
            // Not flip
            _tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(vars.sizeDelta),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
          }
        }
      } else if (vars.sizeDelta < 0) {
        // SELL
        if (vars.isNewPosition || !vars.positionIsLong) {
          // New position and Short position
          // just increase position when SELL
          _tradeService.increasePosition({
            _primaryAccount: vars.order.account,
            _subAccountId: vars.order.subAccountId,
            _marketIndex: vars.order.marketIndex,
            _sizeDelta: vars.sizeDelta,
            _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
          });
        } else if (vars.positionIsLong) {
          bool _flipSide = (-vars.sizeDelta) > _existingPosition.positionSizeE30;
          if (_flipSide) {
            // Flip the position
            // Fully close Long position
            _tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(_existingPosition.positionSizeE30),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
            // Flip it to Short position
            _tradeService.increasePosition({
              _primaryAccount: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _sizeDelta: vars.sizeDelta + _existingPosition.positionSizeE30,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
          } else {
            // Not flip
            _tradeService.decreasePosition({
              _account: vars.order.account,
              _subAccountId: vars.order.subAccountId,
              _marketIndex: vars.order.marketIndex,
              _positionSizeE30ToDecrease: uint256(-vars.sizeDelta),
              _tpToken: vars.order.tpToken,
              _limitPriceE30: _isGuaranteeLimitPrice ? vars.order.triggerPrice : 0
            });
          }
        }
      }
    }

    // Pay the executor
    _transferOutETH(vars.order.executionFee, vars.feeReceiver);

    emit LogExecuteLimitOrder(
      vars.order.account,
      vars.order.subAccountId,
      vars.orderIndex,
      vars.order.marketIndex,
      vars.order.sizeDelta,
      vars.order.triggerPrice,
      vars.order.triggerAboveThreshold,
      vars.order.executionFee,
      _currentPrice,
      vars.order.reduceOnly,
      vars.order.tpToken
    );
  }

  /// @notice Cancel a limit order
  /// @param _subAccountId Sub-account Id
  /// @param _orderIndex Order Index which could be retrieved from the emitted event from `createOrder()`
  function cancelOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex
  ) external nonReentrant delegate(_mainAccount) {
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_mainAccount != _msgSender()) revert ILimitTradeHandler_Unauthorized();

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    LimitOrder memory _order = limitOrders[_subAccount][_orderIndex];
    // Check if this order still exists
    if (_order.account == address(0)) revert ILimitTradeHandler_NonExistentOrder();

    _cancelOrder(_order, _subAccount, _orderIndex);
  }

  function batchCancelOrders(
    address _mainAccount,
    uint8 _subAccountId,
    uint256[] calldata _orderIndices
  ) external nonReentrant delegate(_mainAccount) {
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_mainAccount != _msgSender()) revert ILimitTradeHandler_Unauthorized();

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    uint256 _len = _orderIndices.length;
    for (uint256 _i; _i < _len; ) {
      uint256 _orderIndex = _orderIndices[_i];
      LimitOrder memory _order = limitOrders[_subAccount][_orderIndex];
      // Check if this order still exists
      if (_order.account == address(0)) revert ILimitTradeHandler_NonExistentOrder();

      _cancelOrder(_order, _subAccount, _orderIndex);
      unchecked {
        ++_i;
      }
    }
  }

  function _cancelOrder(LimitOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    // Remove this order from the list
    _removeOrder(_order, _subAccount, _orderIndex);

    // Refund the execution fee to the creator of this order
    _transferOutETH(_order.executionFee, _order.account);

    emit LogCancelLimitOrder(
      _order.account,
      _order.subAccountId,
      _orderIndex,
      _order.marketIndex,
      _order.sizeDelta,
      _order.triggerPrice,
      _order.triggerAboveThreshold,
      _order.executionFee,
      _order.reduceOnly,
      _order.tpToken
    );
  }

  /// @notice Update a limit order
  /// @param _subAccountId Sub-account Id
  /// @param _orderIndex Order Index which could be retrieved from the emitted event from `createOrder()`
  /// @param _sizeDelta How much the position size will change in USD (1e30), can be negative for INCREASE order
  /// @param _triggerPrice The price that this limit order will be triggered
  /// @param _acceptablePrice The acceptable price for the order
  /// @param _triggerAboveThreshold The current price must go above/below the trigger price for the order to be executed
  /// @param _reduceOnly If true, it's a Reduce-Only order which will not flip the side of the position
  /// @param _tpToken Take profit token, when trader has profit
  function updateOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    bool _triggerAboveThreshold,
    bool _reduceOnly,
    address _tpToken
  ) external nonReentrant delegate(_mainAccount) {
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_mainAccount != _msgSender()) revert ILimitTradeHandler_Unauthorized();

    _updateOrder(
      _mainAccount,
      _subAccountId,
      _orderIndex,
      _sizeDelta,
      _triggerPrice,
      _acceptablePrice,
      _triggerAboveThreshold,
      _reduceOnly,
      _tpToken
    );
  }

  function _updateOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex,
    int256 _sizeDelta,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    bool _triggerAboveThreshold,
    bool _reduceOnly,
    address _tpToken
  ) internal {
    address subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    LimitOrder storage _order = limitOrders[subAccount][_orderIndex];
    // Check if this order still exists
    if (_order.account == address(0)) revert ILimitTradeHandler_NonExistentOrder();
    if (_sizeDelta == 0) revert ILimitTradeHandler_BadSizeDelta();

    if (_order.triggerPrice == 0) {
      // Market
      revert ILimitTradeHandler_MarketOrderNoUpdate();
    } else {
      // Limit
      // if trying to update to Market, revert
      if (_triggerPrice == 0) {
        revert ILimitTradeHandler_LimitOrderConvertToMarketOrder();
      }
    }

    // Update order
    _order.triggerPrice = _triggerPrice;
    _order.acceptablePrice = _acceptablePrice;
    _order.triggerAboveThreshold = _triggerAboveThreshold;
    _order.sizeDelta = _sizeDelta;
    _order.reduceOnly = _reduceOnly;
    _order.tpToken = _tpToken;

    emit LogUpdateLimitOrder(
      _mainAccount,
      _subAccountId,
      _orderIndex,
      _order.marketIndex,
      _sizeDelta,
      _triggerPrice,
      _triggerAboveThreshold,
      _reduceOnly,
      _tpToken
    );
  }

  function _addOrder(LimitOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    limitOrdersIndex[_subAccount] = _orderIndex + 1;
    limitOrders[_subAccount][_orderIndex] = _order;

    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    activeOrderPointers.add(_pointer);
    subAccountActiveOrderPointers[_subAccount].add(_pointer);

    if (_order.triggerPrice == 0) {
      // Market
      activeMarketOrderPointers.add(_pointer);
      subAccountActiveMarketOrderPointers[_subAccount].add(_pointer);
    } else {
      // Limit
      activeLimitOrderPointers.add(_pointer);
      subAccountActiveLimitOrderPointers[_subAccount].add(_pointer);
    }
  }

  function _removeOrder(LimitOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    delete limitOrders[_subAccount][_orderIndex];

    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    activeOrderPointers.remove(_pointer);
    subAccountActiveOrderPointers[_subAccount].remove(_pointer);

    if (_order.triggerPrice == 0) {
      // Market
      activeMarketOrderPointers.remove(_pointer);
      subAccountActiveMarketOrderPointers[_subAccount].remove(_pointer);
    } else {
      // Limit
      activeLimitOrderPointers.remove(_pointer);
      subAccountActiveLimitOrderPointers[_subAccount].remove(_pointer);
    }
  }

  /**
   * Getters
   */

  function getAllActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(activeOrderPointers, _limit, _offset);
  }

  function getMarketActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(activeMarketOrderPointers, _limit, _offset);
  }

  function getLimitActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(activeLimitOrderPointers, _limit, _offset);
  }

  function getAllActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(subAccountActiveOrderPointers[_subAccount], _limit, _offset);
  }

  function getMarketActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(subAccountActiveMarketOrderPointers[_subAccount], _limit, _offset);
  }

  function getLimitActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders) {
    return _getOrders(subAccountActiveLimitOrderPointers[_subAccount], _limit, _offset);
  }

  function _getOrders(
    EnumerableSet.UintSet storage _pointers,
    uint256 _limit,
    uint256 _offset
  ) internal view returns (LimitOrder[] memory _orders) {
    uint256 _len = _pointers.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _orders;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _orders = new LimitOrder[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      (address _account, uint96 _index) = _decodePointer(_pointers.at(i));
      LimitOrder memory _order = limitOrders[_account][_index];

      _orders[i - _offset] = _order;
      unchecked {
        ++i;
      }
    }

    return _orders;
  }

  function activeOrdersCount() external view returns (uint256) {
    return activeOrderPointers.length();
  }

  function activeLimitOrdersCount() external view returns (uint256) {
    return activeLimitOrderPointers.length();
  }

  function activeMarketOrdersCount() external view returns (uint256) {
    return activeMarketOrderPointers.length();
  }

  /**
   * Setters
   */
  function setGuaranteeLimitPrice(bool isActive) external onlyOwner {
    isGuaranteeLimitPrice = isActive;

    emit LogSetGuaranteeLimitPrice(isActive);
  }

  /// @notice Sets a new TradeService contract address.
  /// @param _tradeService The new TradeService contract address.
  function setTradeService(address _tradeService) external onlyOwner {
    if (_tradeService == address(0)) revert ILimitTradeHandler_InvalidAddress();
    TradeService(_tradeService).perpStorage();
    emit LogSetTradeService(address(tradeService), _tradeService);
    tradeService = _tradeService;
  }

  /// @notice setMinExecutionFee
  /// @param _newMinExecutionFee minExecutionFee in ethers
  function setMinExecutionFee(uint64 _newMinExecutionFee) external nonReentrant onlyOrderExecutorOrOwner {
    if (_newMinExecutionFee > MAX_EXECUTION_FEE) revert ILimitTradeHandler_MaxExecutionFee();
    emit LogSetMinExecutionFee(minExecutionFee, _newMinExecutionFee);
    minExecutionFee = _newMinExecutionFee;
  }

  function setMinExecutionTimestamp(uint32 _newMinExecutionTimestamp) external onlyOwner {
    emit LogSetMinExecutionTimestamp(minExecutionTimestamp, _newMinExecutionTimestamp);
    minExecutionTimestamp = _newMinExecutionTimestamp;
  }

  /// @notice setOrderExecutor
  /// @param _executor address who will be executor
  /// @param _isAllow flag to allow to execute
  function setOrderExecutor(address _executor, bool _isAllow) external nonReentrant onlyOwner {
    if (_executor == address(0)) revert ILimitTradeHandler_InvalidAddress();
    orderExecutors[_executor] = _isAllow;
    emit LogSetOrderExecutor(_executor, _isAllow);
  }

  /// @notice Sets a new Pyth contract address.
  /// @param _pyth The new Pyth contract address.
  function setPyth(address _pyth) external nonReentrant onlyOwner {
    if (_pyth == address(0)) revert ILimitTradeHandler_InvalidAddress();
    emit LogSetPyth(address(pyth), _pyth);
    pyth = IEcoPyth(_pyth);

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  function setLimitTradeHelper(address _limitTradeHelper) external onlyOwner {
    limitTradeHelper = LimitTradeHelper(_limitTradeHelper);
  }

  function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
    results = new bytes[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
      results[i] = _functionDelegateCall(address(this), data[i]);
    }
    return results;
  }

  /**
   * Private Functions
   */
  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
   * but performing a delegate call.
   *
   * _Available since v3.4._
   */
  function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
    require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.delegatecall(data);
    return AddressUpgradeable.verifyCallResult(success, returndata, "Address: low-level delegate call failed");
  }

  function _validatePositionOrderPrice(
    bool _triggerAboveThreshold,
    uint256 _triggerPrice,
    uint256 _acceptablePrice,
    uint256 _marketIndex,
    int256 _sizeDelta,
    bool _maximizePrice
  ) private view returns (uint256, bool) {
    ValidatePositionOrderPriceVars memory vars;

    // SLOADs
    // Get price from Pyth
    TradeService _tradeService = TradeService(tradeService);
    vars.marketConfig = ConfigStorage(_tradeService.configStorage()).getMarketConfigByIndex(_marketIndex);
    vars.oracle = OracleMiddleware(ConfigStorage(_tradeService.configStorage()).oracle());
    vars.globalMarket = PerpStorage(_tradeService.perpStorage()).getMarketByIndex(_marketIndex);

    // Validate trigger price with oracle price
    (vars.oraclePrice, ) = vars.oracle.getLatestPrice(vars.marketConfig.assetId, true);
    vars.isPriceValid = _triggerAboveThreshold ? vars.oraclePrice > _triggerPrice : vars.oraclePrice < _triggerPrice;

    if (!vars.isPriceValid) revert ILimitTradeHandler_InvalidPriceForExecution();

    // Validate acceptable price with adaptive price
    (vars.adaptivePrice, , vars.marketStatus) = vars.oracle.getLatestAdaptivePriceWithMarketStatus(
      vars.marketConfig.assetId,
      _maximizePrice,
      (int(vars.globalMarket.longPositionSize) - int(vars.globalMarket.shortPositionSize)),
      _sizeDelta,
      vars.marketConfig.fundingRate.maxSkewScaleUSD,
      0
    );

    // Validate market status
    if (vars.marketStatus != 2) revert ILimitTradeHandler_MarketIsClosed();

    // Validate price is executable
    bool isBuy = _sizeDelta > 0;
    vars.isPriceValid = isBuy ? vars.adaptivePrice < _acceptablePrice : vars.adaptivePrice > _acceptablePrice;

    if (!vars.isPriceValid) revert ILimitTradeHandler_PriceSlippage();

    return (vars.adaptivePrice, vars.isPriceValid);
  }

  function _validateCreateOrderPrice(
    bool _triggerAboveThreshold,
    uint256 _triggerPrice,
    uint256 _marketIndex,
    int256 _sizeDelta,
    bool _maximizePrice
  ) private view {
    if (_sizeDelta == 0) revert ILimitTradeHandler_BadSizeDelta();
    // SLOAD
    TradeService _tradeService = TradeService(tradeService);
    ConfigStorage _configStorage = ConfigStorage(_tradeService.configStorage());
    ValidatePositionOrderPriceVars memory vars;

    // Get price from Pyth
    vars.marketConfig = _configStorage.getMarketConfigByIndex(_marketIndex);
    vars.oracle = OracleMiddleware(_configStorage.oracle());
    vars.globalMarket = PerpStorage(_tradeService.perpStorage()).getMarketByIndex(_marketIndex);

    (uint256 _currentPrice, , ) = vars.oracle.unsafeGetLatestAdaptivePriceWithMarketStatus(
      vars.marketConfig.assetId,
      _maximizePrice,
      (int(vars.globalMarket.longPositionSize) - int(vars.globalMarket.shortPositionSize)),
      _sizeDelta,
      vars.marketConfig.fundingRate.maxSkewScaleUSD,
      0
    );

    if (_triggerAboveThreshold) {
      if (_triggerPrice != 0 && _triggerPrice <= _currentPrice) {
        revert ILimitTradeHandler_TriggerPriceBelowCurrentPrice();
      }
    } else {
      if (_triggerPrice >= _currentPrice) {
        revert ILimitTradeHandler_TriggerPriceAboveCurrentPrice();
      }
    }
  }

  /// @notice Transfer in ETH from user to be used as execution fee
  /// @dev The received ETH will be wrapped into WETH and store in this contract for later use.
  function _transferInETH() private {
    IWNative(weth).deposit{ value: msg.value }();
  }

  /// @notice Transfer out ETH to the receiver
  /// @dev The stored WETH will be unwrapped and transfer as native token
  /// @param _amountOut Amount of ETH to be transferred
  /// @param _receiver The receiver of ETH in its native form. The receiver must be able to accept native token.
  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    IWNative(weth).withdraw(_amountOut);
    // slither-disable-next-line arbitrary-send-eth
    // To mitigate potential attacks, the call method is utilized,
    // allowing the contract to bypass any revert calls from the destination address.
    // By setting the gas limit to 2300, equivalent to the gas limit of the transfer method,
    // the transaction maintains a secure execution."
    (bool success, ) = _receiver.call{ value: _amountOut, gas: 2300 }("");
    // send WNative instead when native token transfer fail
    if (!success) {
      IWNative(weth).deposit{ value: _amountOut }();
      IWNative(weth).transfer(_receiver, _amountOut);
    }
  }

  function _encodePointer(address _account, uint96 _index) internal pure returns (uint256 _pointer) {
    return uint256(bytes32(abi.encodePacked(_account, _index)));
  }

  function _decodePointer(uint256 _pointer) internal pure returns (address _account, uint96 _index) {
    return (address(uint160(_pointer >> 96)), uint96(_pointer));
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
