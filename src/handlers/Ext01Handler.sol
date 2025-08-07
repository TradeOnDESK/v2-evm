// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

/// Bases
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin-4.8.1/contracts/utils/structs/EnumerableSet.sol";

/// Interfaces
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";
import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";

/// Services
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { LiquidationService } from "@hmx/services/LiquidationService.sol";
import { LiquidityService } from "@hmx/services/LiquidityService.sol";
import { TradeService } from "@hmx/services/TradeService.sol";

/// Storages
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";

/// Libs
import { HMXLib } from "@hmx/libraries/HMXLib.sol";

/// @title Ext01Handler - Handler for extended actions which not related to core functionality.
contract Ext01Handler is OwnableUpgradeable, ReentrancyGuardUpgradeable, IExt01Handler {
  using EnumerableSet for EnumerableSet.UintSet;

  event LogSwitchCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address[] path,
    address fromToken,
    address toToken,
    uint256 fromAmount,
    uint256 toAmount
  );
  event LogCancelOrder(
    address indexed primaryAccount,
    uint256 indexed orderIndex,
    uint24 orderType,
    uint8 indexed subAccountId
  );
  event LogTransferCollateral(
    address indexed primaryAccount,
    uint256 indexed fromSubAccountId,
    uint256 indexed toSubAccountId,
    address token,
    uint256 amount
  );
  event LogCreateSwitchCollateralOrder(
    address indexed primaryAccount,
    uint8 indexed subAccountId,
    uint248 amount,
    address[] path,
    uint256 minToAmount
  );
  event LogCreateTransferCollateralOrder(
    address indexed primaryAccount,
    uint8 indexed fromSubAccountId,
    uint8 indexed toSubAccountId,
    address token,
    uint256 amount
  );
  event LogSetCrossMarginService(
    CrossMarginService indexed prevCrossMarginService,
    CrossMarginService indexed newCrossMarginService
  );
  event LogSetLiquidationService(
    LiquidationService indexed oldLiquidationService,
    LiquidationService indexed newLiquidationService
  );
  event LogSetLiquidityService(
    LiquidityService indexed oldLiquidityService,
    LiquidityService indexed newLiquidityService
  );
  event LogSetMinExecutionFee(uint24 indexed orderType, uint256 prevMinExecutionFee, uint256 newMinExecutionFee);
  event LogSetOrderExecutor(address indexed executor, bool prevIsAllow, bool isAllow);
  event LogSetPyth(IEcoPyth indexed prevPyth, IEcoPyth indexed newPyth);
  event LogSetDelegate(address sender, address delegate);
  event LogSetTradeService(TradeService indexed oldTradeService, TradeService indexed newTradeService);
  event LogExecuteOrderResult(
    uint256 indexed orderIndex,
    uint24 orderType,
    uint128 executionFee,
    bool isSuccess,
    string errMsg
  );

  struct ExecuteOrderVars {
    GenericOrder order;
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
   * Configuration States
   */
  CrossMarginService public crossMarginService;
  LiquidationService public liquidationService;
  LiquidityService public liquidityService;
  TradeService public tradeService;
  IEcoPyth public pyth;

  /**
   * Storage States
   */
  address private _senderOverride;

  mapping(uint24 orderType => uint128 minExecutionFee) public minExecutionOrderOf; // Minimum execution fee of each orderType
  mapping(address => mapping(uint256 => GenericOrder)) public genericOrders; // Array of Orders of each sub-account
  mapping(address => uint256) public genericOrdersIndex; // The last limit order index of each sub-account
  mapping(address => address) public delegations; // The mapping of mainAccount => Smart Wallet to be used for Account Abstraction

  // Pointers
  EnumerableSet.UintSet private _activeOrderPointers;
  EnumerableSet.UintSet private _executedOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountActiveOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountExecutedOrderPointers;

  mapping(address => bool) public orderExecutors; // address -> flag to execute

  /// @notice Validate only whitelisted executors to call function
  modifier onlyOrderExecutor() {
    if (!orderExecutors[msg.sender]) revert IExt01Handler_Unauthorized();
    _;
  }

  modifier onlyOrderExecutorOrOwner() {
    if (!orderExecutors[msg.sender] && msg.sender != owner()) revert IExt01Handler_Unauthorized();
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

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the Ext01Handler with the provided configuration parameters.
  /// @param _crossMarginService Address of the CrossMarginService contract.
  /// @param _liquidationService Address of the LiquidationService contract.
  /// @param _liquidityService Address of the LiquidityService contract.
  /// @param _tradeService Address of the TradeService contract.
  /// @param _pyth Address of the Pyth contract.
  function initialize(
    address _crossMarginService,
    address _liquidationService,
    address _liquidityService,
    address _tradeService,
    address _pyth
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    crossMarginService = CrossMarginService(_crossMarginService);
    liquidationService = LiquidationService(_liquidationService);
    liquidityService = LiquidityService(_liquidityService);
    tradeService = TradeService(_tradeService);
    pyth = IEcoPyth(_pyth);

    // Sanity check
    crossMarginService.vaultStorage();
    liquidationService.vaultStorage();
    liquidityService.vaultStorage();
    tradeService.vaultStorage();
    pyth.getAssetIds();
  }

  struct CreateSwitchCollateralOrderParams {
    uint8 subAccountId;
    uint248 amount;
    address[] path;
    uint256 minToAmount;
  }

  struct CreateTransferCollateralOrderParams {
    uint8 fromSubAccountId;
    uint8 toSubAccountId;
    address token;
    uint256 amount;
  }

  /**
   * Main routines
   */

  function createExtOrder(
    CreateExtOrderParams memory _params
  ) external payable nonReentrant delegate(_params.mainAccount) returns (uint256 _orderIndex) {
    // Check
    // Check if overrided _msgSender() is the same as _mainAccount.
    // If msg.sender is not a delegatee, _msgSender() won't be overrided
    // which then makes _msgSender() to become msg.sender not the _mainAccount.
    if (_params.mainAccount != _msgSender()) revert IExt01Handler_Unauthorized();
    // 0 = Cancelled order
    if (_params.orderType == 0) revert IExt01Handler_BadOrderType();
    uint128 _minExecutionFee = minExecutionOrderOf[_params.orderType];
    if (_params.executionFee < _minExecutionFee) revert IExt01Handler_InsufficientExecutionFee();
    if (msg.value != _params.executionFee) revert IExt01Handler_InCorrectValueTransfer();

    // Convert native to wrapped native.
    // This should just only a executionFee
    _transferInETH();

    bytes memory _rawOrder;
    // Create order according to the command
    if (_params.orderType == 1) {
      // OrderType 1 = Create switch collateral order
      CreateSwitchCollateralOrderParams memory _localVars;
      (_localVars.subAccountId, _localVars.amount, _localVars.path, _localVars.minToAmount) = abi.decode(
        _params.data,
        (uint8, uint248, address[], uint256)
      );
      _rawOrder = _createSwitchCollateralOrder(
        _localVars.subAccountId,
        _localVars.amount,
        _localVars.path,
        _localVars.minToAmount
      );
    } else if (_params.orderType == 2) {
      // OrderType 2 = Create transfer collateral order
      CreateTransferCollateralOrderParams memory _localVars;
      (_localVars.fromSubAccountId, _localVars.toSubAccountId, _localVars.token, _localVars.amount) = abi.decode(
        _params.data,
        (uint8, uint8, address, uint256)
      );
      _rawOrder = _createTransferCollateralOrder(
        _localVars.fromSubAccountId,
        _localVars.toSubAccountId,
        _localVars.token,
        _localVars.amount
      );
    }

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _params.subAccountId);
    _orderIndex = genericOrdersIndex[_subAccount];

    GenericOrder memory order = GenericOrder({
      orderIndex: uint248(_orderIndex),
      status: OrderStatus.PENDING,
      createdTimestamp: uint48(block.timestamp),
      executedTimestamp: 0,
      orderType: uint24(_params.orderType),
      executionFee: _params.executionFee,
      rawOrder: _rawOrder
    });

    _addOrder(order, _subAccount, _orderIndex);
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
      revert IExt01Handler_InvalidArraySize();

    // Update the price and publish time data using the Pyth oracle
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
    // Pay execution fee to the executor
    _transferOutETH(totalFeeReceived, _feeReceiver);
  }

  function executeOrder(GenericOrder memory _order) external {
    // If not in executing state, then revert
    if (msg.sender != address(this)) revert IExt01Handler_Unauthorized();

    if (_order.orderType == 1) {
      // OrderType 1 == Switch collateral order
      SwitchCollateralOrder memory _switchCollateralOrder = abi.decode(_order.rawOrder, (SwitchCollateralOrder));
      // Check if this order still exists
      if (_switchCollateralOrder.primaryAccount == address(0)) revert IExt01Handler_NonExistentOrder();
      _executeSwitchCollateralOrder(_switchCollateralOrder);
    } else if (_order.orderType == 2) {
      // OrderType 2 == Transfer collateral order
      TransferCollateralOrder memory _transferCollateralOrder = abi.decode(_order.rawOrder, (TransferCollateralOrder));
      _executeTransferCollateralOrder(_transferCollateralOrder);
    }
  }

  /// @notice Cancels the specified withdraw order.
  /// @param _mainAccount main address of user
  /// @param _subAccountId ID of the user's sub-account
  /// @param _orderIndex index of user's order
  function cancelOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex
  ) external nonReentrant delegate(_mainAccount) {
    _cancelOrder(_msgSender(), _subAccountId, _orderIndex);
  }

  function _handleFailedError(GenericOrder memory _order, string memory errMsg, bool _isRevert) internal {
    if (_isRevert) {
      require(false, string(errMsg));
    } else {
      emit LogExecuteOrderResult(_order.orderIndex, _order.orderType, _order.executionFee, false, errMsg);
      _order.status = OrderStatus.FAIL;
      if (_order.orderType == 1) {
        SwitchCollateralOrder memory _switchCollateralOrder = abi.decode(_order.rawOrder, (SwitchCollateralOrder));
        _cancelOrder(_switchCollateralOrder.primaryAccount, _switchCollateralOrder.subAccountId, _order.orderIndex);
      } else if (_order.orderType == 2) {
        TransferCollateralOrder memory _transferCollateralOrder = abi.decode(
          _order.rawOrder,
          (TransferCollateralOrder)
        );
        _cancelOrder(
          _transferCollateralOrder.primaryAccount,
          _transferCollateralOrder.fromSubAccountId,
          _order.orderIndex
        );
      }
    }
  }

  function _handleOrderSuccess(address _subAccount, uint256 _orderIndex) internal {
    _removeOrder(_subAccount, _orderIndex);

    GenericOrder storage order = genericOrders[_subAccount][_orderIndex];
    order.status = OrderStatus.SUCCESS;
    order.executedTimestamp = uint48(block.timestamp);
    // Execution succeeded, store the executed order pointer
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _executedOrderPointers.add(_pointer);
    _subAccountExecutedOrderPointers[_subAccount].add(_pointer);
  }

  /**
   * Switch Collateral
   */

  /// @notice Creates a new switch collateral order to facilitate the switch of collateral token from one to another.
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _amount Amount of path[0] to switch.
  /// @param _path Path of the switch collateral.
  /// @param _minToAmount Minimum amount to be received.
  function _createSwitchCollateralOrder(
    uint8 _subAccountId,
    uint248 _amount,
    address[] memory _path,
    uint256 _minToAmount
  ) internal returns (bytes memory _rawOrder) {
    // Check
    (address _fromToken, address _toToken) = (_path[0], _path[_path.length - 1]);
    _revertOnNotAcceptedCollateral(_fromToken);
    _revertOnNotAcceptedCollateral(_toToken);
    if (_amount == 0) revert IExt01Handler_BadAmount();
    if (_fromToken == _toToken) revert IExt01Handler_SameFromToToken();

    emit LogCreateSwitchCollateralOrder(_msgSender(), _subAccountId, _amount, _path, _minToAmount);

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    uint256 _orderIndex = genericOrdersIndex[_subAccount];

    _rawOrder = abi.encode(
      SwitchCollateralOrder({
        primaryAccount: _msgSender(),
        subAccountId: _subAccountId,
        orderIndex: _orderIndex,
        amount: _amount,
        fromToken: _fromToken,
        toToken: _toToken,
        path: _path,
        minToAmount: _minToAmount,
        crossMarginService: crossMarginService
      })
    );
  }

  function _executeOrder(
    ExecuteOrderVars memory vars,
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    bool _isRevert
  ) internal returns (uint256 _totalFeeReceived) {
    vars.subAccount = HMXLib.getSubAccount(_account, _subAccountId);
    vars.order = genericOrders[vars.subAccount][_orderIndex];
    vars.orderIndex = _orderIndex;

    if (vars.order.createdTimestamp == 0) revert IExt01Handler_NonExistentOrder();

    // Skip cancelled order
    if (vars.order.orderType != 0) {
      try this.executeOrder(vars.order) {
        // update order status
        _handleOrderSuccess(vars.subAccount, _orderIndex);
        emit LogExecuteOrderResult(vars.order.orderIndex, vars.order.orderType, vars.order.executionFee, true, "");
      } catch Error(string memory errMsg) {
        _handleFailedError(vars.order, errMsg, _isRevert);
      } catch Panic(uint /*errorCode*/) {
        _handleFailedError(vars.order, "Panic occurred while executing the switch collateral order", _isRevert);
      } catch (bytes memory errMsg) {
        _handleFailedError(vars.order, string(errMsg), _isRevert);
      }

      // Assign execution time
      _totalFeeReceived = vars.order.executionFee;
    }
  }

  /**
   * Transfer Collateral
   */

  /// @notice Calculate new trader balance after transfer collateral token.
  /// @dev This uses to calculate new trader balance when they tranferring token as collateral.
  /// @param _fromSubAccountId Trader's Sub-Account Id to withdraw from.
  /// @param _toSubAccountId Trader's Sub-Account Id to deposit to.
  /// @param _token Token that's withdrawn as collateral.
  /// @param _amount Token withdrawing amount.
  function _createTransferCollateralOrder(
    uint8 _fromSubAccountId,
    uint8 _toSubAccountId,
    address _token,
    uint256 _amount
  ) internal returns (bytes memory _rawOrder) {
    // Check
    // _revertOnNotAcceptedCollateral(_token);
    if (_amount == 0) revert IExt01Handler_BadAmount();
    if (_fromSubAccountId == _toSubAccountId) revert IExt01Handler_SelfTransfer();

    emit LogCreateTransferCollateralOrder(_msgSender(), _fromSubAccountId, _toSubAccountId, _token, _amount);

    _rawOrder = abi.encode(
      TransferCollateralOrder({
        primaryAccount: _msgSender(),
        fromSubAccountId: _fromSubAccountId,
        toSubAccountId: _toSubAccountId,
        token: _token,
        amount: _amount,
        crossMarginService: crossMarginService
      })
    );
  }

  function _executeSwitchCollateralOrder(SwitchCollateralOrder memory _order) internal {
    // Call service to switch collateral
    (address _fromToken, address _toToken) = (_order.path[0], _order.path[_order.path.length - 1]);
    uint256 _toAmount = _order.crossMarginService.switchCollateral(
      ICrossMarginService.SwitchCollateralParams(
        _order.primaryAccount,
        _order.subAccountId,
        _order.amount,
        _order.path,
        _order.minToAmount
      )
    );

    emit LogSwitchCollateral(
      _order.primaryAccount,
      _order.subAccountId,
      _order.path,
      _fromToken,
      _toToken,
      _order.amount,
      _toAmount
    );
  }

  function _executeTransferCollateralOrder(TransferCollateralOrder memory _order) internal {
    // Call service to transfer collateral
    _order.crossMarginService.transferCollateral(
      ICrossMarginService.TransferCollateralParams(
        _order.primaryAccount,
        _order.fromSubAccountId,
        _order.primaryAccount,
        _order.toSubAccountId,
        _order.token,
        _order.amount
      )
    );

    emit LogTransferCollateral(
      _order.primaryAccount,
      _order.fromSubAccountId,
      _order.toSubAccountId,
      _order.token,
      _order.amount
    );
  }

  function _cancelOrder(address _mainAccount, uint8 _subAccountId, uint256 _orderIndex) internal {
    address subAccount = HMXLib.getSubAccount(_mainAccount, _subAccountId);
    // SLOAD
    GenericOrder memory _order = genericOrders[subAccount][_orderIndex];

    if (_order.orderType == 0) revert IExt01Handler_NonExistentOrder();

    address _owner;
    if (_order.orderType == 1) {
      SwitchCollateralOrder memory _switchCollateralOrder = abi.decode(_order.rawOrder, (SwitchCollateralOrder));
      _owner = _switchCollateralOrder.primaryAccount;
    } else if (_order.orderType == 2) {
      TransferCollateralOrder memory _transferCollateralOrder = abi.decode(_order.rawOrder, (TransferCollateralOrder));
      _owner = _transferCollateralOrder.primaryAccount;
    }

    bool _isExecutor = orderExecutors[_msgSender()];
    // validate if msg.sender is not owned the order or not executor, then revert
    if (_msgSender() != _owner && !_isExecutor) revert IExt01Handler_NotOrderOwner();

    _removeOrder(subAccount, _orderIndex);

    // refund the _order.executionFee if the caller is not executor
    if (!_isExecutor) {
      _transferOutETH(_order.executionFee, _owner);
    }

    emit LogCancelOrder(payable(_owner), _order.orderIndex, _order.orderType, _subAccountId);

    delete genericOrders[subAccount][_orderIndex];
  }

  function _addOrder(GenericOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    genericOrdersIndex[_subAccount] = _orderIndex + 1;
    genericOrders[_subAccount][_orderIndex] = _order;

    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.add(_pointer);
    _subAccountActiveOrderPointers[_subAccount].add(_pointer);
  }

  function _removeOrder(address _subAccount, uint256 _orderIndex) internal {
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.remove(_pointer);
    _subAccountActiveOrderPointers[_subAccount].remove(_pointer);
  }

  function getAllActiveOrders(uint256 _limit, uint256 _offset) external view returns (GenericOrder[] memory _orders) {
    return _getOrders(_activeOrderPointers, _limit, _offset);
  }

  function getAllExecutedOrders(uint256 _limit, uint256 _offset) external view returns (GenericOrder[] memory _orders) {
    return _getOrders(_executedOrderPointers, _limit, _offset);
  }

  function getAllActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (GenericOrder[] memory _orders) {
    return _getOrders(_subAccountActiveOrderPointers[_subAccount], _limit, _offset);
  }

  function getAllExecutedOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (GenericOrder[] memory _orders) {
    return _getOrders(_subAccountExecutedOrderPointers[_subAccount], _limit, _offset);
  }

  function _encodePointer(address _account, uint96 _index) internal pure returns (uint256 _pointer) {
    return uint256(bytes32(abi.encodePacked(_account, _index)));
  }

  function _decodePointer(uint256 _pointer) internal pure returns (address _account, uint96 _index) {
    return (address(uint160(_pointer >> 96)), uint96(_pointer));
  }

  function _getOrders(
    EnumerableSet.UintSet storage _pointers,
    uint256 _limit,
    uint256 _offset
  ) internal view returns (GenericOrder[] memory _orders) {
    uint256 _len = _pointers.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _orders;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _orders = new GenericOrder[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      (address _account, uint96 _index) = _decodePointer(_pointers.at(i));
      GenericOrder memory _order = genericOrders[_account][_index];

      _orders[i - _offset] = _order;
      unchecked {
        ++i;
      }
    }

    return _orders;
  }

  /**
   * Private Functions
   */

  /// @notice Transfer in ETH from user to be used as execution fee
  /// @dev The received ETH will be wrapped into WETH and store in this contract for later use.
  function _transferInETH() internal {
    IWNative(ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()).deposit{
      value: msg.value
    }();
  }

  /// @notice Transfer out ETH to the receiver
  /// @dev The stored WETH will be unwrapped and transfer as native token
  /// @param _amountOut Amount of ETH to be transferred
  /// @param _receiver The receiver of ETH in its native form. The receiver must be able to accept native token.
  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    IWNative(ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()).withdraw(_amountOut);
    // slither-disable-next-line arbitrary-send-eth
    // To mitigate potential attacks, the call method is utilized,
    // allowing the contract to bypass any revert calls from the destination address.
    // By setting the gas limit to 2300, equivalent to the gas limit of the transfer method,
    // the transaction maintains a secure execution."
    (bool success, ) = _receiver.call{ value: _amountOut, gas: 2300 }("");
    // send WNative instead when native token transfer fail
    if (!success) {
      address weth = ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth();
      IWNative(weth).deposit{ value: _amountOut }();
      IWNative(weth).transfer(_receiver, _amountOut);
    }
  }

  /// @notice Validate only accepted collateral tokens
  function _revertOnNotAcceptedCollateral(address _token) internal view {
    ConfigStorage(CrossMarginService(crossMarginService).configStorage()).validateAcceptedCollateral(_token);
  }

  receive() external payable {
    // @dev Cannot enable this check due to Solidity Fallback Function Gas Limit introduced in 0.8.17.
    // ref - https://stackoverflow.com/questions/74930609/solidity-fallback-function-gas-limit
  }

  /*
   * Setters
   */

  /// @notice Sets a new CrossMarginService contract address.
  /// @param _crossMarginService The new CrossMarginService contract address.
  function setCrossMarginService(address _crossMarginService) external onlyOwner {
    if (_crossMarginService == address(0)) revert IExt01Handler_BadAddress();
    emit LogSetCrossMarginService(crossMarginService, CrossMarginService(_crossMarginService));
    crossMarginService = CrossMarginService(_crossMarginService);

    // Sanity check
    crossMarginService.vaultStorage();
  }

  /// @notice Set a new LiquidationService
  /// @param _liquidationService The new LiquidationService contract address.
  function setLiquidationService(address _liquidationService) external onlyOwner {
    if (_liquidationService == address(0)) revert IExt01Handler_BadAddress();
    emit LogSetLiquidationService(liquidationService, LiquidationService(_liquidationService));
    liquidationService = LiquidationService(_liquidationService);

    // Sanity check
    liquidationService.vaultStorage();
  }

  /// @notice Set a new LiquidityService
  /// @param _liquidityService The new LiquidityService contract address.
  function setLiquidityService(address _liquidityService) external onlyOwner {
    if (_liquidityService == address(0)) revert IExt01Handler_BadAddress();
    emit LogSetLiquidityService(liquidityService, LiquidityService(_liquidityService));
    liquidityService = LiquidityService(_liquidityService);

    // Sanity check
    liquidityService.vaultStorage();
  }

  /// @notice Set a new TradeService
  /// @param _tradeService The new TradeService contract address.
  function setTradeService(address _tradeService) external onlyOwner {
    if (_tradeService == address(0)) revert IExt01Handler_BadAddress();
    emit LogSetTradeService(tradeService, TradeService(_tradeService));
    tradeService = TradeService(_tradeService);

    // Sanity check
    tradeService.vaultStorage();
  }

  function setDelegate(address _delegate) external {
    delegations[msg.sender] = _delegate;
    emit LogSetDelegate(msg.sender, _delegate);
  }

  /// @notice Sets a new Pyth contract address.
  /// @param _pyth The new Pyth contract address.
  function setPyth(address _pyth) external onlyOwner {
    if (_pyth == address(0)) revert IExt01Handler_BadAddress();
    emit LogSetPyth(pyth, IEcoPyth(_pyth));
    pyth = IEcoPyth(_pyth);

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  /// @notice setMinExecutionFee
  /// @param _orderType Order type to set min execution fee
  /// @param _newMinExecutionFee minExecutionFee in ethers
  function setMinExecutionFee(
    uint24 _orderType,
    uint128 _newMinExecutionFee
  ) external nonReentrant onlyOrderExecutorOrOwner {
    emit LogSetMinExecutionFee(_orderType, minExecutionOrderOf[_orderType], _newMinExecutionFee);
    minExecutionOrderOf[_orderType] = _newMinExecutionFee;
  }

  /// @notice setOrderExecutor
  /// @param _executor address who will be executor
  /// @param _isAllow flag to allow to execute
  function setOrderExecutor(address _executor, bool _isAllow) external onlyOwner {
    emit LogSetOrderExecutor(_executor, orderExecutors[_executor], _isAllow);
    orderExecutors[_executor] = _isAllow;
  }
}
