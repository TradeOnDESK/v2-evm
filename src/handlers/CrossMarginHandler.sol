// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// base
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

// interfaces
import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";

import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { IDESKVault } from "@hmx/interfaces/desk/IDESKVault.sol";

/// @title CrossMarginHandler
/// @notice This contract handles the deposit and withdrawal of collateral tokens for the Cross Margin Trading module.
contract CrossMarginHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, ICrossMarginHandler {
  using SafeERC20Upgradeable for ERC20Upgradeable;

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
  event LogTransferCollateralSubAccount(
    address indexed primaryAccount,
    uint256 indexed subAccountFrom,
    uint256 indexed subAccountTo,
    address token,
    uint256 amount
  );
  event LogSetCrossMarginService(address indexed oldCrossMarginService, address newCrossMarginService);
  event LogSetPyth(address indexed oldPyth, address newPyth);
  event LogSetOrderExecutor(address executor, bool isAllow);
  event LogSetMinExecutionFee(uint256 oldValue, uint256 newValue);
  event LogMaxExecutionChuck(uint256 oldValue, uint256 newValue);
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
    uint256 indexed orderId,
    address token,
    uint256 amount,
    uint256 executionFee,
    bool shouldUnwrap
  );
  event LogExecuteWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderId,
    address token,
    uint256 amount,
    bool shouldUnwrap,
    bool isSuccess,
    string errMsg
  );
  event LogCreateMigrateToDESK(uint256 indexed orderId);
  event LogSetDESKVault(address indexed vault);

  /**
   * Constants
   */
  uint64 internal constant RATE_PRECISION = 1e18;

  /**
   * States
   */
  address public crossMarginService;
  address public pyth;
  uint256 public nextExecutionOrderIndex; // the index of the next withdraw order that should be executed
  uint256 public minExecutionOrderFee; // minimum execution order fee in native token amount
  uint256 public maxExecutionChuck; // maximum execution order sizes per request

  WithdrawOrder[] public withdrawOrders; // all withdrawOrders
  mapping(address => WithdrawOrder[]) public subAccountExecutedWithdrawOrders; // subAccount -> executed orders
  mapping(address => bool) public orderExecutors; // address -> flag to execute
  mapping(address user => bool isBanned) banlist;
  mapping(uint256 orderId => bool isMigrateToDESK) isMigrateToDESKMapping;
  IDESKVault public deskVault;

  /// @notice Initializes the CrossMarginHandler contract with the provided configuration parameters.
  /// @param _crossMarginService Address of the CrossMarginService contract.
  /// @param _pyth Address of the Pyth contract.
  /// @param _minExecutionOrderFee Minimum execution fee for a withdrawal order.
  function initialize(
    address _crossMarginService,
    address _pyth,
    uint256 _minExecutionOrderFee,
    uint256 _maxExecutionChuck
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
    IEcoPyth(_pyth).getAssetIds();

    crossMarginService = _crossMarginService;
    pyth = _pyth;
    minExecutionOrderFee = _minExecutionOrderFee;
    maxExecutionChuck = _maxExecutionChuck;
  }

  function getActiveWithdrawOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder) {
    // Find the _returnCount
    uint256 _returnCount;
    {
      uint256 _activeOrderCount = withdrawOrders.length - nextExecutionOrderIndex;

      uint256 _afterOffsetCount = _activeOrderCount > _offset ? (_activeOrderCount - _offset) : 0;
      _returnCount = _afterOffsetCount > _limit ? _limit : _afterOffsetCount;

      if (_returnCount == 0) return _withdrawOrder;
    }

    // Initialize order array
    _withdrawOrder = new WithdrawOrder[](_returnCount);

    // Build the array
    {
      for (uint i = 0; i < _returnCount; ) {
        _withdrawOrder[i] = withdrawOrders[nextExecutionOrderIndex + _offset + i];
        unchecked {
          ++i;
        }
      }

      return _withdrawOrder;
    }
  }

  function getExecutedWithdrawOrders(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder) {
    // Find the _returnCount and
    uint256 _returnCount;
    {
      uint256 _exeuctedOrderCount = subAccountExecutedWithdrawOrders[_subAccount].length;
      uint256 _afterOffsetCount = _exeuctedOrderCount > _offset ? (_exeuctedOrderCount - _offset) : 0;
      _returnCount = _afterOffsetCount > _limit ? _limit : _afterOffsetCount;

      if (_returnCount == 0) return _withdrawOrder;
    }

    // Initialize order array
    _withdrawOrder = new WithdrawOrder[](_returnCount);

    // Build the array
    {
      for (uint i = 0; i < _returnCount; ) {
        _withdrawOrder[i] = subAccountExecutedWithdrawOrders[_subAccount][_offset + i];
        unchecked {
          ++i;
        }
      }
      return _withdrawOrder;
    }
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
    if (!orderExecutors[msg.sender]) revert ICrossMarginHandler_NotWhitelisted();
    _;
  }

  modifier onlyOrderExecutorOrOwner() {
    if (!orderExecutors[msg.sender] && msg.sender != owner()) revert ICrossMarginHandler_NotWhitelisted();
    _;
  }

  /**
   * Deposit Collateral
   */

  /// @notice Deposits the specified amount of collateral token into the user's sub-account.
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to deposit.
  /// @param _amount Amount of collateral token to deposit.
  /// @param _shouldWrap Whether to wrap native ETH into WETH before depositing.
  function depositCollateral(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    bool _shouldWrap
  ) external payable nonReentrant onlyAcceptedToken(_token) {
    if (_amount == 0) revert ICrossMarginHandler_BadAmount();
    // SLOAD
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);

    if (_shouldWrap) {
      // Prevent mismatch msgValue and the input amount
      if (msg.value != _amount) {
        revert ICrossMarginHandler_MismatchMsgValue();
      }

      // Wrap the native to wNative. The _token must be wNative.
      // If not, it would revert transfer amount exceed on the next line.
      // slither-disable-next-line arbitrary-send-eth
      IWNative(_token).deposit{ value: _amount }();
      // Transfer those wNative token from this contract to VaultStorage
      ERC20Upgradeable(_token).safeTransfer(_crossMarginService.vaultStorage(), _amount);
    } else {
      // Transfer depositing token from trader's wallet to VaultStorage
      ERC20Upgradeable(_token).safeTransferFrom(msg.sender, _crossMarginService.vaultStorage(), _amount);
    }

    // Call service to deposit collateral
    _crossMarginService.depositCollateral(msg.sender, _subAccountId, _token, _amount);

    emit LogDepositCollateral(msg.sender, _subAccountId, _token, _amount);
  }

  /**
   * Withdraw Collateral
   */

  function createWithdrawCollateralOrder(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable returns (uint256 _orderId) {
    return createWithdrawCollateralOrder(_subAccountId, _token, _amount, _executionFee, _shouldUnwrap, false);
  }

  /// @notice Creates a new withdraw order to withdraw the specified amount of collateral token from the user's sub-account.
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to withdraw.
  /// @param _amount Amount of collateral token to withdraw.
  /// @param _executionFee Execution fee to pay for this order.
  /// @param _shouldUnwrap Whether to unwrap WETH into native ETH after withdrawing.
  /// @return _orderId The ID of the newly created withdraw order.
  function createWithdrawCollateralOrder(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap,
    bool _isMigrateToDESK
  ) public payable nonReentrant onlyAcceptedToken(_token) returns (uint256 _orderId) {
    if (_amount == 0) revert ICrossMarginHandler_BadAmount();
    if (_executionFee < minExecutionOrderFee) revert ICrossMarginHandler_InsufficientExecutionFee();
    if (msg.value != _executionFee) revert ICrossMarginHandler_InCorrectValueTransfer();
    if (_shouldUnwrap && _token != ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth())
      revert ICrossMarginHandler_NotWNativeToken();
    if (banlist[msg.sender]) revert ICrossMarginHandler_Unauthorized();
    if (_isMigrateToDESK) {
      if (address(deskVault) == address(0)) {
        revert ICrossMarginHandler_DESKVaultNotSet();
      }
      uint256 _minDeposit = deskVault.minDeposits(_token);
      if (_minDeposit == 0) {
        revert ICrossMarginHandler_DESKVaultNotAcceptedToken();
      }
      if (_minDeposit > _amount) {
        revert ICrossMarginHandler_DESKVaultMinDeposit();
      }
    }

    // convert native to WNative (including executionFee)
    _transferInETH();

    _orderId = withdrawOrders.length;

    withdrawOrders.push(
      WithdrawOrder({
        account: payable(msg.sender),
        orderId: _orderId,
        token: _token,
        amount: _amount,
        executionFee: _executionFee,
        shouldUnwrap: _shouldUnwrap,
        subAccountId: _subAccountId,
        crossMarginService: CrossMarginService(crossMarginService),
        createdTimestamp: uint48(block.timestamp),
        executedTimestamp: 0,
        status: WithdrawOrderStatus.PENDING
      })
    );

    if (_isMigrateToDESK) {
      isMigrateToDESKMapping[_orderId] = true;
      emit LogCreateMigrateToDESK(_orderId);
    }

    emit LogCreateWithdrawOrder(msg.sender, _subAccountId, _orderId, _token, _amount, _executionFee, _shouldUnwrap);
    return _orderId;
  }

  function createWithdrawCollateralOrderOnBehalf(
    address _account,
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable nonReentrant onlyAcceptedToken(_token) onlyOwner returns (uint256 _orderId) {
    if (_amount == 0) revert ICrossMarginHandler_BadAmount();
    if (_executionFee < minExecutionOrderFee) revert ICrossMarginHandler_InsufficientExecutionFee();
    if (msg.value != _executionFee) revert ICrossMarginHandler_InCorrectValueTransfer();
    if (_shouldUnwrap && _token != ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth())
      revert ICrossMarginHandler_NotWNativeToken();
    if (!banlist[_account]) revert ICrossMarginHandler_Unauthorized();

    // convert native to WNative (including executionFee)
    _transferInETH();

    _orderId = withdrawOrders.length;

    withdrawOrders.push(
      WithdrawOrder({
        account: payable(_account),
        orderId: _orderId,
        token: _token,
        amount: _amount,
        executionFee: _executionFee,
        shouldUnwrap: _shouldUnwrap,
        subAccountId: _subAccountId,
        crossMarginService: CrossMarginService(crossMarginService),
        createdTimestamp: uint48(block.timestamp),
        executedTimestamp: 0,
        status: WithdrawOrderStatus.PENDING
      })
    );

    emit LogCreateWithdrawOrder(_account, _subAccountId, _orderId, _token, _amount, _executionFee, _shouldUnwrap);
    return _orderId;
  }

  /// @notice Executes a batch of pending withdraw orders.
  /// @param _endIndex The index of the last withdraw order to execute.
  /// @param _feeReceiver The address to receive the total execution fee.
  /// @param _priceData Price data from the Pyth oracle.
  /// @param _publishTimeData Publish time data from the Pyth oracle.
  /// @param _minPublishTime Minimum publish time for the Pyth oracle data.
  /// @param _encodedVaas Encoded VaaS data for the Pyth oracle.
  // slither-disable-next-line reentrancy-eth
  function executeOrder(
    uint256 _endIndex,
    address payable _feeReceiver,
    bytes32[] memory _priceData,
    bytes32[] memory _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external nonReentrant onlyOrderExecutor {
    // SLOAD
    uint256 _nextExecutionOrderIndex = nextExecutionOrderIndex;

    // Get the number of withdraw orders
    uint256 _orderLength = withdrawOrders.length;

    // Ensure there are orders to execute
    if (_nextExecutionOrderIndex == _orderLength) revert ICrossMarginHandler_NoOrder();

    // Set the end index to the latest order index if it exceeds the number of orders
    uint256 _latestOrderIndex = _orderLength - 1;
    if (_endIndex > _latestOrderIndex) {
      _endIndex = _latestOrderIndex;
    }

    // split execution into chunk for preventing exceed block gas limit
    if (_endIndex - _nextExecutionOrderIndex > maxExecutionChuck)
      _endIndex = _nextExecutionOrderIndex + maxExecutionChuck;

    // Update the price and publish time data using the Pyth oracle
    // slither-disable-next-line arbitrary-send-eth
    IEcoPyth(pyth).updatePriceFeeds(_priceData, _publishTimeData, _minPublishTime, _encodedVaas);

    // Initialize variables for the execution loop
    WithdrawOrder memory _order;
    uint256 _totalFeeReceiver;
    uint256 _executionFee;

    for (uint256 i = _nextExecutionOrderIndex; i <= _endIndex; ) {
      _order = withdrawOrders[i];

      // skip cancelled orders
      if (_order.amount == 0) {
        unchecked {
          ++i;
        }
        continue;
      }

      _executionFee = _order.executionFee;

      try this.executeWithdrawOrder(i, _order) {
        emit LogExecuteWithdrawOrder(
          _order.account,
          _order.subAccountId,
          _order.orderId,
          _order.token,
          _order.amount,
          _order.shouldUnwrap,
          true,
          ""
        );
        // update order status
        _order.status = WithdrawOrderStatus.SUCCESS;
      } catch Error(string memory errMsg) {
        _handleOrderFail(_order, errMsg);
      } catch Panic(uint /*errorCode*/) {
        _handleOrderFail(_order, "Panic occurred while executing the withdraw order");
      } catch (bytes memory errMsg) {
        _handleOrderFail(_order, string(errMsg));
      }

      // assign exec time
      _order.executedTimestamp = uint48(block.timestamp);
      _totalFeeReceiver += _executionFee;

      // save to executed order first
      subAccountExecutedWithdrawOrders[HMXLib.getSubAccount(_order.account, _order.subAccountId)].push(_order);
      // clear executed withdraw order
      delete withdrawOrders[i];

      unchecked {
        ++i;
      }
    }

    nextExecutionOrderIndex = _endIndex + 1;
    // Pay total collected fees to the executor
    _transferOutETH(_totalFeeReceiver, _feeReceiver);
  }

  function _handleOrderFail(WithdrawOrder memory order, string memory errMsg) internal {
    emit LogExecuteWithdrawOrder(
      order.account,
      order.subAccountId,
      order.orderId,
      order.token,
      order.amount,
      order.shouldUnwrap,
      false,
      errMsg
    );

    order.status = WithdrawOrderStatus.FAIL;
  }

  /// @notice Executes a single withdraw order by transferring the specified amount of collateral token to the user's wallet.
  /// @param _order WithdrawOrder struct representing the order to execute.
  function executeWithdrawOrder(uint256 _orderId, WithdrawOrder memory _order) external {
    // if not in executing state, then revert
    if (msg.sender != address(this)) revert ICrossMarginHandler_Unauthorized();
    if (
      _order.shouldUnwrap &&
      _order.token != ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()
    ) revert ICrossMarginHandler_NotWNativeToken();

    bool isMigrateToDESK = isMigrateToDESKMapping[_orderId];

    // Call service to withdraw collateral
    if (!isMigrateToDESK) {
      if (_order.shouldUnwrap) {
        // Withdraw wNative straight to this contract first.
        _order.crossMarginService.withdrawCollateral(
          _order.account,
          _order.subAccountId,
          _order.token,
          _order.amount,
          address(this)
        );
        // Then we unwrap the wNative token. The receiving amount should be the exact same as _amount. (No fee deducted when withdraw)
        IWNative(_order.token).withdraw(_order.amount);

        // slither-disable-next-line arbitrary-send-eth
        payable(_order.account).transfer(_order.amount);
      } else {
        // Withdraw _token straight to the user
        _order.crossMarginService.withdrawCollateral(
          _order.account,
          _order.subAccountId,
          _order.token,
          _order.amount,
          _order.account
        );
      }
    } else {
      // Migrate to DESK
      _order.crossMarginService.withdrawCollateral(
        _order.account,
        _order.subAccountId,
        _order.token,
        _order.amount,
        address(this)
      );
      ERC20Upgradeable(_order.token).safeApprove(address(deskVault), type(uint256).max);
      deskVault.deposit(_order.token, bytes32(bytes20(address(_order.account))), _order.amount);
    }

    emit LogWithdrawCollateral(_order.account, _order.subAccountId, _order.token, _order.amount);
  }

  /// @notice Cancels the specified withdraw order.
  /// @param _orderIndex Index of the order to cancel.
  function cancelWithdrawOrder(uint256 _orderIndex) external nonReentrant {
    // if order index >= liquidity order's length, then out of bound
    // if order index < next execute index, means order index outdate
    if (_orderIndex >= withdrawOrders.length || _orderIndex < nextExecutionOrderIndex) {
      revert ICrossMarginHandler_NoOrder();
    }

    // SLOAD
    WithdrawOrder memory _order = withdrawOrders[_orderIndex];

    // validate if msg.sender is not owned the order, then revert
    if (msg.sender != _order.account) revert ICrossMarginHandler_NotOrderOwner();

    delete withdrawOrders[_orderIndex];

    // refund the _order.executionFee
    _transferOutETH(_order.executionFee, msg.sender);

    emit LogCancelWithdrawOrder(
      payable(msg.sender),
      _order.subAccountId,
      _order.orderId,
      _order.token,
      _order.amount,
      _order.executionFee,
      _order.shouldUnwrap
    );
  }

  /**
   * Getters
   */

  /// @notice Returns all pending withdraw orders.
  /// @return _withdrawOrders An array of WithdrawOrder structs representing all pending withdraw orders.
  function getWithdrawOrders() external view returns (WithdrawOrder[] memory _withdrawOrders) {
    return withdrawOrders;
  }

  /// @notice get withdraw orders length
  function getWithdrawOrderLength() external view returns (uint256) {
    return withdrawOrders.length;
  }

  /**
   * Setters
   */

  /// @notice Sets a new CrossMarginService contract address.
  /// @param _crossMarginService The new CrossMarginService contract address.
  function setCrossMarginService(address _crossMarginService) external nonReentrant onlyOwner {
    if (_crossMarginService == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetCrossMarginService(crossMarginService, _crossMarginService);
    crossMarginService = _crossMarginService;

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
  }

  /// @notice Sets a new Pyth contract address.
  /// @param _pyth The new Pyth contract address.
  function setPyth(address _pyth) external nonReentrant onlyOwner {
    if (_pyth == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetPyth(pyth, _pyth);
    pyth = _pyth;

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  function setBanlist(address[] memory users, bool[] memory isBanned) external onlyOwner {
    for (uint256 i = 0; i < users.length; i++) {
      banlist[users[i]] = isBanned[i];
    }
  }

  /// @notice setMinExecutionFee
  /// @param _newMinExecutionFee minExecutionFee in ethers
  function setMinExecutionFee(uint256 _newMinExecutionFee) external nonReentrant onlyOrderExecutorOrOwner {
    emit LogSetMinExecutionFee(minExecutionOrderFee, _newMinExecutionFee);
    minExecutionOrderFee = _newMinExecutionFee;
  }

  /// @notice setMaxExecutionChuck
  /// @param _maxExecutionChuck maximum check sizes when execute orders
  function setMaxExecutionChuck(uint256 _maxExecutionChuck) external nonReentrant onlyOwner {
    emit LogMaxExecutionChuck(maxExecutionChuck, _maxExecutionChuck);
    maxExecutionChuck = _maxExecutionChuck;
  }

  /// @notice setOrderExecutor
  /// @param _executor address who will be executor
  /// @param _isAllow flag to allow to execute
  function setOrderExecutor(address _executor, bool _isAllow) external nonReentrant onlyOwner {
    orderExecutors[_executor] = _isAllow;
    emit LogSetOrderExecutor(_executor, _isAllow);
  }

  function setDESKVault(address _vault) external nonReentrant onlyOwner {
    deskVault = IDESKVault(_vault);
    emit LogSetDESKVault(_vault);
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
