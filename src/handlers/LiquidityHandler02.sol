// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// base
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin-4.8.1/contracts/utils/structs/EnumerableSet.sol";

// contracts
import { LiquidityService } from "@hmx/services/LiquidityService.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";

// interfaces
import { ILiquidityHandler02 } from "@hmx/handlers/interfaces/ILiquidityHandler02.sol";
import { IWNative } from "../interfaces/IWNative.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { ISurgeStaking } from "@hmx/staking/interfaces/ISurgeStaking.sol";

/// Libs
import { HMXLib } from "@hmx/libraries/HMXLib.sol";

/// @title LiquidityHandler
/// @notice This contract handles liquidity orders for adding or removing liquidity from a pool
contract LiquidityHandler02 is OwnableUpgradeable, ReentrancyGuardUpgradeable, ILiquidityHandler02 {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using EnumerableSet for EnumerableSet.UintSet;

  /**
   * Events
   */
  event LogSetLiquidityService(address oldValue, address newValue);
  event LogSetMinExecutionFee(uint256 oldValue, uint256 newValue);
  event LogSetPyth(address oldPyth, address newPyth);
  event LogSetDelegate(address indexed mainAccount, address indexed delegateAccount);
  event LogSetOrderExecutor(address executor, bool isAllow);
  event LogCreateAddLiquidityOrder(
    address indexed account,
    uint256 indexed orderIndex,
    address indexed tokenIn,
    uint256 amountIn,
    uint256 minOut,
    uint256 executionFee,
    uint48 createdTimestamp
  );
  event LogCreateRemoveLiquidityOrder(
    address indexed account,
    uint256 indexed orderIndex,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 minOut,
    uint256 executionFee,
    bool isNativeOut,
    uint48 createdTimestamp
  );
  event LogExecuteLiquidityOrder(
    address indexed account,
    uint256 indexed orderIndex,
    address indexed token,
    uint256 amount,
    uint256 minOut,
    bool isAdd,
    uint256 actualOut,
    bool isSuccess,
    string errMsg
  );
  event LogCancelLiquidityOrder(
    address indexed account,
    uint256 indexed orderIndex,
    address indexed token,
    uint256 amount,
    uint256 minOut,
    bool isAdd
  );
  event LogRefund(
    address indexed account,
    uint256 indexed orderIndex,
    address indexed token,
    uint256 amount,
    bool isNativeOut
  );
  event LogSetHlpStaking(address oldHlpStaking, address newHlpStaking);

  struct ExecuteOrderVars {
    LiquidityOrder order;
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
  address public liquidityService; //liquidityService
  address public pyth; //pyth
  uint256 public minExecutionOrderFee; // minimum execution order fee in native token amount

  address private _senderOverride;

  mapping(address => bool) public orderExecutors; // address -> whitelist executors
  mapping(address => mapping(uint256 => LiquidityOrder)) public liquidityOrders; // Array of Orders of each sub-account
  mapping(address => uint256) public liquidityOrdersIndex; // The last limit order index of each sub-account
  mapping(address => address) public delegations; // The mapping of mainAccount => Smart Wallet to be used for Account Abstraction

  ISurgeStaking public hlpStaking;

  // Pointers
  EnumerableSet.UintSet private _activeOrderPointers;
  EnumerableSet.UintSet private _executedOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountActiveOrderPointers;
  mapping(address => EnumerableSet.UintSet) private _subAccountExecutedOrderPointers;

  /// @notice Initializes the LiquidityHandler contract with the provided configuration parameters.
  /// @param _liquidityService Address of the LiquidityService contract.
  /// @param _pyth Address of the Pyth contract.
  /// @param _minExecutionOrderFee Minimum execution fee for execute order.
  function initialize(address _liquidityService, address _pyth, uint256 _minExecutionOrderFee) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    liquidityService = _liquidityService;
    pyth = _pyth;
    minExecutionOrderFee = _minExecutionOrderFee;

    // Sanity check
    // slither-disable-next-line unused-return
    LiquidityService(_liquidityService).perpStorage();
    IEcoPyth(_pyth).getAssetIds();
  }

  /**
   * Modifiers
   */

  modifier onlyAcceptedToken(address _token) {
    ConfigStorage(LiquidityService(liquidityService).configStorage()).validateAcceptedLiquidityToken(_token);
    _;
  }

  modifier onlyOrderExecutor() {
    if (!orderExecutors[msg.sender]) revert ILiquidityHandler02_NotWhitelisted();
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

  receive() external payable {
    if (msg.sender != ConfigStorage(LiquidityService(liquidityService).configStorage()).weth())
      revert ILiquidityHandler02_InvalidSender();
  }

  /**
   * Core Functions
   */

  /// @notice Create a new AddLiquidity order without participating in HLP Surge event
  /// @param _mainAccount The address of main user's wallet
  /// @param _subAccountId The address of sub-account of user
  /// @param _tokenIn address token in
  /// @param _amountIn amount token in (based on decimals)
  /// @param _minOut minHLP out
  /// @param _executionFee The execution fee of order
  /// @param _shouldWrap in case of sending native token
  function createAddLiquidityOrder(
    address _mainAccount,
    uint8 _subAccountId,
    address _tokenIn,
    uint256 _amountIn,
    uint256 _minOut,
    uint256 _executionFee,
    bool _shouldWrap
  ) external payable nonReentrant onlyAcceptedToken(_tokenIn) delegate(_mainAccount) returns (uint256 _orderIndex) {
    // pre validate
    if (_mainAccount != _msgSender()) revert ILiquidityHandler02_Unauthorized();
    LiquidityService(liquidityService).validatePreAddRemoveLiquidity(_amountIn);
    if (_executionFee < minExecutionOrderFee) revert ILiquidityHandler02_InsufficientExecutionFee();
    if (_shouldWrap) {
      if (_tokenIn != ConfigStorage(LiquidityService(liquidityService).configStorage()).weth())
        revert ILiquidityHandler02_NotWNativeToken();
      if (msg.value != _amountIn + _executionFee) revert ILiquidityHandler02_InCorrectValueTransfer();
    } else {
      if (msg.value != _executionFee) revert ILiquidityHandler02_InCorrectValueTransfer();
      IERC20Upgradeable(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountIn);
    }
    // convert native to WNative (including executionFee)
    _transferInETH();

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    _orderIndex = liquidityOrdersIndex[_subAccount];

    LiquidityOrder memory order = LiquidityOrder({
      account: payable(_msgSender()),
      orderIndex: _orderIndex,
      token: _tokenIn,
      amount: _amountIn,
      minOut: _minOut,
      actualAmountOut: 0,
      isAdd: true,
      executionFee: _executionFee,
      isNativeOut: _shouldWrap,
      createdTimestamp: uint48(block.timestamp),
      executedTimestamp: 0,
      status: LiquidityOrderStatus.PENDING
    });

    _addOrder(order, _subAccount, _orderIndex);

    emit LogCreateAddLiquidityOrder(
      _msgSender(),
      _orderIndex,
      _tokenIn,
      _amountIn,
      _minOut,
      _executionFee,
      uint48(block.timestamp)
    );
  }

  /// @notice Create a new RemoveLiquidity order
  /// @param _mainAccount The address of main user's wallet
  /// @param _subAccountId The address of sub-account of user
  /// @param _tokenOut The address of the token user wish to receive
  /// @param _amountIn The amount of HLP to remove liquidity
  /// @param _minOut minAmountOut of the selected token out
  /// @param _executionFee The execution fee of order
  /// @param _isNativeOut If true, the contract will try to unwrap it into Native Token
  function createRemoveLiquidityOrder(
    address _mainAccount,
    uint8 _subAccountId,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minOut,
    uint256 _executionFee,
    bool _isNativeOut
  ) external payable nonReentrant onlyAcceptedToken(_tokenOut) delegate(_mainAccount) returns (uint256 _orderIndex) {
    // pre validate
    if (_mainAccount != _msgSender()) revert ILiquidityHandler02_Unauthorized();
    LiquidityService(liquidityService).validatePreAddRemoveLiquidity(_amountIn);
    if (_executionFee < minExecutionOrderFee) revert ILiquidityHandler02_InsufficientExecutionFee();
    if (msg.value != _executionFee) revert ILiquidityHandler02_InCorrectValueTransfer();
    if (_isNativeOut && _tokenOut != ConfigStorage(LiquidityService(liquidityService).configStorage()).weth())
      revert ILiquidityHandler02_NotWNativeToken();

    // convert native to WNative (including executionFee)
    _transferInETH();

    // transfers ERC-20 token from user's account to this contract
    IERC20Upgradeable(ConfigStorage(LiquidityService(liquidityService).configStorage()).hlp()).safeTransferFrom(
      _msgSender(),
      address(this),
      _amountIn
    );

    address _subAccount = HMXLib.getSubAccount(_msgSender(), _subAccountId);
    _orderIndex = liquidityOrdersIndex[_subAccount];

    LiquidityOrder memory order = LiquidityOrder({
      account: payable(_msgSender()),
      orderIndex: _orderIndex,
      token: _tokenOut,
      amount: _amountIn,
      minOut: _minOut,
      actualAmountOut: 0,
      isAdd: false,
      executionFee: _executionFee,
      isNativeOut: _isNativeOut,
      createdTimestamp: uint48(block.timestamp),
      executedTimestamp: 0,
      status: LiquidityOrderStatus.PENDING
    });

    _addOrder(order, _subAccount, _orderIndex);

    emit LogCreateRemoveLiquidityOrder(
      _msgSender(),
      _orderIndex,
      _tokenOut,
      _amountIn,
      _minOut,
      _executionFee,
      _isNativeOut,
      uint48(block.timestamp)
    );
  }

  /// @notice Executes liquidity orders within the given range, updating price data and publishing time data as necessary.
  /// @param _params store all data needed to execute, avoid stack-too-deep
  function executeOrders(ExecuteOrdersParam memory _params) external nonReentrant onlyOrderExecutor {
    if (
      _params.accounts.length != _params.subAccountIds.length || _params.accounts.length != _params.orderIndexes.length
    ) revert ILiquidityHandler02_InvalidArraySize();

    // slither-disable-next-line arbitrary-send-eth
    IEcoPyth(pyth).updatePriceFeeds(
      _params.priceData,
      _params.publishTimeData,
      _params.minPublishTime,
      _params.encodedVaas
    );

    ExecuteOrderVars memory vars;
    vars.feeReceiver = _params.feeReceiver;
    vars.priceData = _params.priceData;
    vars.publishTimeData = _params.publishTimeData;
    vars.minPublishTime = _params.minPublishTime;
    vars.encodedVaas = _params.encodedVaas;

    uint256 _totalFeeReceived;
    uint256 length = _params.accounts.length;
    for (uint256 i = 0; i < length; ) {
      _totalFeeReceived += _executeOrder(
        vars,
        _params.accounts[i],
        _params.subAccountIds[i],
        _params.orderIndexes[i],
        _params.isRevert
      );
      unchecked {
        ++i;
      }
    }

    // Pay total collected fees to the executor
    _transferOutETH(_totalFeeReceived, _params.feeReceiver);
  }

  /// @notice execute either addLiquidity or removeLiquidity
  /// @param _order LiquidityOrder struct representing the order to execute.
  function executeLiquidity(LiquidityOrder calldata _order) external returns (uint256 _amountOut) {
    // if not in executing state, then revert
    if (msg.sender != address(this)) revert ILiquidityHandler02_Unauthorized();

    if (_order.isAdd) {
      bool isHlpStakingDeployed = address(hlpStaking) != address(0);
      IERC20Upgradeable(_order.token).safeTransfer(LiquidityService(liquidityService).vaultStorage(), _order.amount);
      _amountOut = LiquidityService(liquidityService).addLiquidity(
        _order.account,
        _order.token,
        _order.amount,
        _order.minOut,
        isHlpStakingDeployed ? address(this) : _order.account
      );
      if (isHlpStakingDeployed) {
        // If HLPStaking is live
        // Auto stake into HLPStaking
        ISurgeStaking(hlpStaking).deposit(_order.account, _amountOut);
      }
      return _amountOut;
    } else {
      _amountOut = LiquidityService(liquidityService).removeLiquidity(
        _order.account,
        _order.token,
        _order.amount,
        _order.minOut
      );

      if (_order.isNativeOut) {
        _transferOutETH(_amountOut, payable(_order.account));
      } else {
        IERC20Upgradeable(_order.token).safeTransfer(_order.account, _amountOut);
      }

      return _amountOut;
    }
  }

  /// @notice Cancels the specified add/remove liquidity order and refunds the execution fee.
  /// @param _orderIndex Index of the order to cancel.
  function cancelLiquidityOrder(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex
  ) external nonReentrant delegate(_mainAccount) {
    _cancelOrder(_msgSender(), _subAccountId, _orderIndex);
  }

  /**
   * Internal Functions
   */
  function _executeOrder(
    ExecuteOrderVars memory vars,
    address _account,
    uint8 _subAccountId,
    uint256 _orderIndex,
    bool _isRevert
  ) internal returns (uint256 _totalFeeReceived) {
    vars.subAccount = HMXLib.getSubAccount(_account, _subAccountId);
    vars.order = liquidityOrders[vars.subAccount][_orderIndex];
    vars.orderIndex = _orderIndex;

    // check if this order still exists
    if (vars.order.account == address(0)) revert ILiquidityHandler02_NonExistentOrder();

    // Skip cancelled order
    if (vars.order.amount > 0) {
      try this.executeLiquidity(vars.order) returns (uint256 actualOut) {
        emit LogExecuteLiquidityOrder(
          vars.order.account,
          vars.orderIndex,
          vars.order.token,
          vars.order.amount,
          vars.order.minOut,
          vars.order.isAdd,
          actualOut,
          true,
          ""
        );
        // update order status
        _handleOrderSuccess(vars.subAccount, _orderIndex);
      } catch Error(string memory errMsg) {
        _handleOrderFail(vars.order, _subAccountId, errMsg, _isRevert);
      } catch Panic(uint /*errorCode*/) {
        _handleOrderFail(vars.order, _subAccountId, "Panic occurred while executing the withdraw order", _isRevert);
      } catch (bytes memory errMsg) {
        _handleOrderFail(vars.order, _subAccountId, string(errMsg), _isRevert);
      }

      // Assign execution time
      _totalFeeReceived = vars.order.executionFee;
    }
  }

  function _cancelOrder(address _mainAccount, uint8 _subAccountId, uint256 _orderIndex) internal {
    address subAccount = HMXLib.getSubAccount(_mainAccount, _subAccountId);
    // SLOAD
    LiquidityOrder memory _order = liquidityOrders[subAccount][_orderIndex];

    // validate if msg.sender is not owned the order, then revert
    if (_msgSender() != _order.account && !orderExecutors[_msgSender()]) revert ILiquidityHandler02_InvalidOrder();

    _removeOrder(subAccount, _orderIndex);

    // refund the _order.executionFee to user if the caller is a user
    if (!orderExecutors[_msgSender()]) {
      _transferOutETH(_order.executionFee, _order.account);
    }
    _refund(_order);

    emit LogCancelLiquidityOrder(
      payable(_order.account),
      _orderIndex,
      _order.token,
      _order.amount,
      _order.minOut,
      _order.isAdd
    );

    delete liquidityOrders[subAccount][_orderIndex];
  }

  function _handleOrderFail(
    LiquidityOrder memory order,
    uint8 _subAccountId,
    string memory errMsg,
    bool _isRevert
  ) internal {
    if (_isRevert) {
      require(false, errMsg);
    } else {
      emit LogExecuteLiquidityOrder(
        order.account,
        order.orderIndex,
        order.token,
        order.amount,
        order.minOut,
        order.isAdd,
        0,
        false,
        errMsg
      );
    }
    order.status = LiquidityOrderStatus.FAIL;
    order.amount = 0;

    // order.amount will be refunded in _cancelOrder();
    _cancelOrder(order.account, _subAccountId, order.orderIndex);
  }

  function _handleOrderSuccess(address _subAccount, uint256 _orderIndex) internal {
    _removeOrder(_subAccount, _orderIndex);

    LiquidityOrder storage order = liquidityOrders[_subAccount][_orderIndex];
    order.status = LiquidityOrderStatus.SUCCESS;
    order.executedTimestamp = uint48(block.timestamp);
    // Execution succeeded, store the executed order pointer
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _executedOrderPointers.add(_pointer);
    _subAccountExecutedOrderPointers[_subAccount].add(_pointer);
  }

  function _addOrder(LiquidityOrder memory _order, address _subAccount, uint256 _orderIndex) internal {
    liquidityOrdersIndex[_subAccount] = _orderIndex + 1;
    liquidityOrders[_subAccount][_orderIndex] = _order;

    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.add(_pointer);
    _subAccountActiveOrderPointers[_subAccount].add(_pointer);
  }

  function _removeOrder(address _subAccount, uint256 _orderIndex) internal {
    uint256 _pointer = _encodePointer(_subAccount, uint96(_orderIndex));
    _activeOrderPointers.remove(_pointer);
    _subAccountActiveOrderPointers[_subAccount].remove(_pointer);
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
  ) internal view returns (LiquidityOrder[] memory _orders) {
    uint256 _len = _pointers.length();
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return _orders;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    _orders = new LiquidityOrder[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      (address _account, uint96 _index) = _decodePointer(_pointers.at(i));
      LiquidityOrder memory _order = liquidityOrders[_account][_index];

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

  /// @notice refund order
  /// @dev this method has not be called directly
  /// @param _order order to execute
  // slither-disable-next-line
  function _refund(LiquidityOrder memory _order) private {
    // if found order with amount 0. means order has been executed or canceled
    uint256 _amount = _order.amount;
    if (_amount == 0) return;

    address _account = _order.account;

    // Add Liquidity order
    if (_order.isAdd) {
      if (_order.isNativeOut) {
        _transferOutETH(_amount, _account);
      } else {
        IERC20Upgradeable(_order.token).safeTransfer(_account, _amount);
      }
      emit LogRefund(_account, _order.orderIndex, _order.token, _amount, _order.isNativeOut);
    }
    // Remove Liquidity order
    else {
      address hlp = ConfigStorage(LiquidityService(liquidityService).configStorage()).hlp();
      IERC20Upgradeable(hlp).safeTransfer(_account, _amount);
      emit LogRefund(_account, _order.orderIndex, hlp, _amount, false);
    }
  }

  /// @notice Transfer in ETH from user to be used as execution fee
  /// @dev The received ETH will be wrapped into WETH and store in this contract for later use.
  function _transferInETH() private {
    IWNative(ConfigStorage(LiquidityService(liquidityService).configStorage()).weth()).deposit{ value: msg.value }();
  }

  /// @notice Transfer out ETH to the receiver
  /// @dev The stored WETH will be unwrapped and transfer as native token
  /// @param _amountOut Amount of ETH to be transferred
  /// @param _receiver The receiver of ETH in its native form. The receiver must be able to accept native token.
  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    IWNative(ConfigStorage(LiquidityService(liquidityService).configStorage()).weth()).withdraw(_amountOut);
    // slither-disable-next-line arbitrary-send-eth
    // To mitigate potential attacks, the call method is utilized,
    // allowing the contract to bypass any revert calls from the destination address.
    // By setting the gas limit to 2300, equivalent to the gas limit of the transfer method,
    // the transaction maintains a secure execution."
    (bool success, ) = _receiver.call{ value: _amountOut, gas: 2300 }("");
    // send WNative instead when native token transfer fail
    if (!success) {
      address weth = ConfigStorage(LiquidityService(liquidityService).configStorage()).weth();
      IWNative(weth).deposit{ value: _amountOut }();
      IWNative(weth).transfer(_receiver, _amountOut);
    }
  }

  /**
   * GETTER
   */

  function getAllActiveOrders(uint256 _limit, uint256 _offset) external view returns (LiquidityOrder[] memory _orders) {
    return _getOrders(_activeOrderPointers, _limit, _offset);
  }

  function getAllExecutedOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (LiquidityOrder[] memory _orders) {
    return _getOrders(_executedOrderPointers, _limit, _offset);
  }

  function getAllActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LiquidityOrder[] memory _orders) {
    return _getOrders(_subAccountActiveOrderPointers[_subAccount], _limit, _offset);
  }

  function getAllExecutedOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LiquidityOrder[] memory _orders) {
    return _getOrders(_subAccountExecutedOrderPointers[_subAccount], _limit, _offset);
  }

  function getLiquidityOrderOfAccountPerIndex(
    address _mainAccount,
    uint8 _subAccountId,
    uint256 _orderIndex
  ) external view returns (LiquidityOrder memory _order) {
    address subAccount = HMXLib.getSubAccount(_mainAccount, _subAccountId);
    return liquidityOrders[subAccount][_orderIndex];
  }

  /**
   * SETTER
   */

  /// @notice setLiquidityService
  /// @param _newLiquidityService liquidityService address
  function setLiquidityService(address _newLiquidityService) external nonReentrant onlyOwner {
    if (_newLiquidityService == address(0)) revert ILiquidityHandler02_InvalidAddress();
    emit LogSetLiquidityService(liquidityService, _newLiquidityService);
    liquidityService = _newLiquidityService;

    // Sanity check
    LiquidityService(_newLiquidityService).vaultStorage();
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

  /// @notice Set new Pyth contract address.
  /// @param _pyth New Pyth contract address.
  function setPyth(address _pyth) external nonReentrant onlyOwner {
    if (_pyth == address(0)) revert ILiquidityHandler02_InvalidAddress();
    emit LogSetPyth(pyth, _pyth);
    pyth = _pyth;

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  function setHlpStaking(address _hlpStaking) external onlyOwner {
    if (_hlpStaking == address(0)) revert ILiquidityHandler02_InvalidAddress();
    emit LogSetHlpStaking(address(hlpStaking), _hlpStaking);
    hlpStaking = ISurgeStaking(_hlpStaking);

    // Sanity check
    hlpStaking.startSurgeEventDepositTimestamp();

    // Max approve
    IERC20Upgradeable(ConfigStorage(LiquidityService(liquidityService).configStorage()).hlp()).safeApprove(
      address(hlpStaking),
      type(uint256).max
    );
  }

  function setDelegate(address _delegate) external {
    delegations[msg.sender] = _delegate;
    emit LogSetDelegate(msg.sender, _delegate);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
