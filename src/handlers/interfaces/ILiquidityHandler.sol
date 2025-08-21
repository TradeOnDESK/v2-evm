// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILiquidityHandler {
  /**
   * Errors
   */
  error ILiquidityHandler_InvalidSender();
  error ILiquidityHandler_InsufficientExecutionFee();
  error ILiquidityHandler_InCorrectValueTransfer();
  error ILiquidityHandler_InsufficientRefund();
  error ILiquidityHandler_NotWhitelisted();
  error ILiquidityHandler_InvalidAddress();
  error ILiquidityHandler_NotExecutionState();
  error ILiquidityHandler_NoOrder();
  error ILiquidityHandler_NotOrderOwner();
  error ILiquidityHandler_NotWNativeToken();
  error ILiquidityHandler_Unauthorized();
  error ILiquidityHandler_ContractPaused();

  /**
   * Structs
   */
  enum LiquidityOrderStatus {
    PENDING,
    SUCCESS,
    FAIL
  }

  struct LiquidityOrder {
    uint256 orderId;
    uint256 amount;
    uint256 minOut;
    uint256 actualAmountOut;
    uint256 executionFee;
    address payable account;
    uint48 createdTimestamp;
    uint48 executedTimestamp;
    address token;
    bool isAdd;
    bool isNativeOut; // token Out for remove liquidity(!unwrap) and refund addLiquidity (shouldWrap) flag
    LiquidityOrderStatus status;
  }

  /**
   * States
   */
  function nextExecutionOrderIndex() external view returns (uint256);

  /**
   * Functions
   */
  function createAddLiquidityOrder(
    address _tokenBuy,
    uint256 _amountIn,
    uint256 _minOut,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable returns (uint256);

  function createRemoveLiquidityOrder(
    address _tokenSell,
    uint256 _amountIn,
    uint256 _minOut,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable returns (uint256);

  function executeOrder(
    uint256 _endIndex,
    address payable _feeReceiver,
    bytes32[] calldata _priceData,
    bytes32[] calldata _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external;

  function cancelLiquidityOrder(uint256 _orderIndex) external;

  function getLiquidityOrders() external view returns (LiquidityOrder[] memory);

  function getLiquidityOrderLength() external view returns (uint256);

  function setOrderExecutor(address _executor, bool _isOk) external;

  function executeLiquidity(LiquidityOrder calldata _order) external returns (uint256);

  function getActiveLiquidityOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (LiquidityOrder[] memory _liquidityOrders);

  function getExecutedLiquidityOrders(
    address _account,
    uint256 _limit,
    uint256 _offset
  ) external view returns (LiquidityOrder[] memory _liquidityOrders);

  function setMaxExecutionChunk(uint256 _maxExecutionChunk) external;

  function setMinExecutionFee(uint256 _newMinExecutionFee) external;

  function setHlpStaking(address _hlpStaking) external;

  function pause() external;

  function unpause() external;

  function paused() external view returns (bool);
}
