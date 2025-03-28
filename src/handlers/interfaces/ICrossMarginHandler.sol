// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";

interface ICrossMarginHandler {
  /**
   * Errors
   */
  error ICrossMarginHandler_InvalidAddress();
  error ICrossMarginHandler_MismatchMsgValue();
  error ICrossMarginHandler_InCorrectValueTransfer();
  error ICrossMarginHandler_NotWhitelisted();
  error ICrossMarginHandler_InsufficientExecutionFee();
  error ICrossMarginHandler_NoOrder();
  error ICrossMarginHandler_NotOrderOwner();
  error ICrossMarginHandler_NotExecutionState();
  error ICrossMarginHandler_NotWNativeToken();
  error ICrossMarginHandler_Unauthorized();
  error ICrossMarginHandler_BadAmount();
  error ICrossMarginHandler_SelfTransfer();
  error ICrossMarginHandler_DESKVaultNotSet();
  error ICrossMarginHandler_DESKVaultNotAcceptedToken();
  error ICrossMarginHandler_DESKVaultMinDeposit();

  /**
   * Structs
   */
  enum WithdrawOrderStatus {
    PENDING,
    SUCCESS,
    FAIL
  }

  struct WithdrawOrder {
    uint256 orderId;
    uint256 amount;
    uint256 executionFee;
    uint48 createdTimestamp;
    uint48 executedTimestamp;
    address payable account;
    address token;
    CrossMarginService crossMarginService;
    uint8 subAccountId;
    WithdrawOrderStatus status; // 0 = pending, 1 = execution success, 2 = execution fail
    bool shouldUnwrap;
  }

  /**
   * States
   */

  function nextExecutionOrderIndex() external view returns (uint256);

  function crossMarginService() external returns (address);

  function pyth() external returns (address);

  /**
   * Functions
   */

  function depositCollateral(uint8 _subAccountId, address _token, uint256 _amount, bool _shouldWrap) external payable;

  function createWithdrawCollateralOrder(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable returns (uint256 _orderId);

  function createWithdrawCollateralOrder(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap,
    bool _isMigrateToDESK
  ) external payable returns (uint256 _orderId);

  function executeOrder(
    uint256 _endIndex,
    address payable _feeReceiver,
    bytes32[] memory _priceData,
    bytes32[] memory _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external;

  function setCrossMarginService(address _address) external;

  function setPyth(address _address) external;

  function setOrderExecutor(address _executor, bool _isAllow) external;

  function setMinExecutionFee(uint256 _newMinExecutionFee) external;

  function setMaxExecutionChuck(uint256 _maxExecutionChuck) external;

  function getWithdrawOrders() external view returns (WithdrawOrder[] memory _withdrawOrder);

  function getWithdrawOrderLength() external view returns (uint256);

  function getActiveWithdrawOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder);

  function getExecutedWithdrawOrders(
    address _account,
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder);

  function setDESKVault(address _vault) external;
}
