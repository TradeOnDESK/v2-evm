// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";

interface ILimitTradeHandler {
  /**
   * Errors
   */
  error ILimitTradeHandler_InvalidAddress();
  error ILimitTradeHandler_InvalidArraySize();
  error ILimitTradeHandler_InsufficientExecutionFee();
  error ILimitTradeHandler_IncorrectValueTransfer();
  error ILimitTradeHandler_NotWhitelisted();
  error ILimitTradeHandler_BadSubAccountId();
  error ILimitTradeHandler_InvalidSender();
  error ILimitTradeHandler_NonExistentOrder();
  error ILimitTradeHandler_MarketIsClosed();
  error ILimitTradeHandler_InvalidPriceForExecution(uint256 oraclePrice, uint256 triggerPrice);
  error ILimitTradeHandler_WrongSizeDelta();
  error ILimitTradeHandler_UnknownOrderType();
  error ILimitTradeHandler_MaxExecutionFee();
  error ILimitTradeHandler_TriggerPriceBelowCurrentPrice();
  error ILimitTradeHandler_TriggerPriceAboveCurrentPrice();
  error ILimitTradeHandler_BadSizeDelta();
  error ILimitTradeHandler_MarketOrderNoUpdate();
  error ILimitTradeHandler_LimitOrderConvertToMarketOrder();
  error ILimitTradeHandler_NotExecutionState();
  error ILimitTradeHandler_Unauthorized();
  error ILimitTradeHandler_BadCalldata();
  error ILimitTradeHandler_PriceSlippage();
  error ILimitTradeHandler_MaxPositionSize();
  error ILimitTradeHandler_MaxTradeSize();
  error ILimitTradeHandler_NotWhitelistedOrNotOwner();

  /**
   * Enums
   */
  enum Command {
    Create,
    Update,
    Cancel
  }

  /**
   * Structs
   */
  struct LimitOrder {
    address account;
    address tpToken;
    bool triggerAboveThreshold;
    bool reduceOnly;
    int256 sizeDelta;
    uint8 subAccountId;
    uint256 orderIndex;
    uint256 marketIndex;
    uint256 triggerPrice;
    uint256 acceptablePrice;
    uint256 executionFee;
    uint256 createdTimestamp;
  }

  struct OrderPointer {
    address account;
    uint256 index;
  }

  /**
   * States
   */
  function pyth() external returns (IEcoPyth);

  function tradeService() external returns (address);

  function minExecutionFee() external returns (uint64);

  function minExecutionTimestamp() external returns (uint32);

  function orderExecutors(address _address) external returns (bool);

  function limitOrdersIndex(address _address) external returns (uint256);

  function limitOrders(
    address _subAccount,
    uint256 _index
  )
    external
    returns (
      address account,
      address tpToken,
      bool triggerAboveThreshold,
      bool reduceOnly,
      int256 sizeDelta,
      uint8 subAccountId,
      uint256 marketIndex,
      uint256 orderIndex,
      uint256 triggerPrice,
      uint256 acceptablePrice,
      uint256 executionFee,
      uint256 createdTimestamp
    );

  /**
   * Functions
   */
  function batch(
    address _mainAccount,
    uint8 _subAccountId,
    Command[] calldata _cmds,
    bytes[] calldata _data
  ) external payable;

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
  ) external payable;

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
  ) external payable;

  function executeOrders(
    address[] calldata _accounts,
    uint8[] calldata _subAccountIds,
    uint256[] calldata _orderIndexes,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external;

  function executeOrders(
    address[] calldata _accounts,
    uint8[] calldata _subAccountIds,
    uint256[] calldata _orderIndexes,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas,
    bool _isRevert
  ) external;

  function cancelOrder(address _mainAccount, uint8 _subAccountId, uint256 _orderIndex) external;

  function batchCancelOrders(address _mainAccount, uint8 _subAccountId, uint256[] calldata _orderIndices) external;

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
  ) external;

  function setDelegate(address _delegate) external;

  function setPyth(address _pyth) external;

  function setGuaranteeLimitPrice(bool isActive) external;

  function setTradeService(address _newTradeService) external;

  function setMinExecutionFee(uint64 _newMinExecutionFee) external;

  function setMinExecutionTimestamp(uint32 _newMinExecutionTimestamp) external;

  function setOrderExecutor(address _executor, bool _isAllow) external;

  function getAllActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders);

  function getMarketActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders);

  function getLimitActiveOrders(uint256 _limit, uint256 _offset) external view returns (LimitOrder[] memory _orders);

  function activeLimitOrdersCount() external view returns (uint256);

  function getAllActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders);

  function getMarketActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders);

  function getLimitActiveOrdersBySubAccount(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LimitOrder[] memory _orders);

  function setLimitTradeHelper(address _limitTradeHelper) external;
}
