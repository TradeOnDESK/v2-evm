// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { LiquidityHandler_Base, IConfigStorage, IPerpStorage } from "./LiquidityHandler_Base.t.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// - revert
//   - Try directCall executeLiquidity
//   - Try directCall refund
//   - Try executeOrder not orderExecutor
//   - Try cancelOrder not ownerOrder
//   - Try cancelOrder with uncreated order

// - success
//   - Try executeOrder_addLiquidityOrder
//   - Try executeOrder_refundAddLiquidityOrder (service revert as message)
//   - Try executeOrder_refundAddLiquidityOrder (service revert as bytes)
//   - Try executeOrder_refundRemoveLiquidityOrder (service revert as message)
//   - Try executeOrder_refundRemoveLiquidityOrder (service revert as bytes)
//   - Try executeOrder_removeLiquidityOrder
//   - Try executeOrder_cancelOrder
//   - Try executeOrder_refundOrder
//   - Try executeOrder_refundOrder native

struct Price {
  // Price
  int64 price;
  // Confidence interval around the price
  uint64 conf;
  // Price exponent
  int32 expo;
  // Unix timestamp describing when the price was published
  uint publishTime;
}

// PriceFeed represents a current aggregate price from pyth publisher feeds.
struct PriceFeed {
  // The price ID.
  bytes32 id;
  // Latest available price
  Price price;
  // Latest available exponentially-weighted moving average price
  Price emaPrice;
}

contract LiquidityHandler_ExecuteOrder is LiquidityHandler_Base {
  bytes32[] internal priceUpdateData;
  bytes32[] internal publishTimeUpdateData;

  function setUp() public override {
    super.setUp();

    liquidityHandler.setOrderExecutor(address(this), true);
  }

  /**
   * REVERT
   */
  function test_revert_directCall_executeLiquidity() external {
    _createAddLiquidityWBTCOrder();
    ILiquidityHandler.LiquidityOrder[] memory aliceOrders = liquidityHandler.getLiquidityOrders();
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_Unauthorized()"));
    liquidityHandler.executeLiquidity(aliceOrders[0]);
  }

  function test_revert_executeOrder_notOrderExecutor() external {
    _createAddLiquidityWBTCOrder();

    ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getLiquidityOrders();

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_NotWhitelisted()"));
    liquidityHandler.executeOrder(
      _orders.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );
  }

  function test_revert_cancelOrder_notOwnerOrder() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_NotOrderOwner()"));
    liquidityHandler.cancelLiquidityOrder(_orderIndex);
  }

  function test_revert_cancelOrder_uncreatedOrder() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_NoOrder()"));
    liquidityHandler.cancelLiquidityOrder(0);
  }

  function test_correctness_userRefund_addLiquidity_revertAsMessage() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(true);

    uint256 _orderIndex = _createAddLiquidityWBTCOrder();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    // Handler executor
    assertEq(_nextExecutionOrderIndex, 0, "nextExecutionOrderIndex");
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after Executed Order
    _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    //user have to get refund
    assertEq(_nextExecutionOrderIndex, 1, "nextExecutionOrderIndex After executed");
    assertEq(_ordersAfter[0].amount, 0, "Amount order should be removed");
    assertEq(wbtc.balanceOf(ALICE), 1 ether);
  }

  function test_correctness_userRefund_addLiquidity_revertAsBytes() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(false);

    uint256 _orderIndex = _createAddLiquidityWBTCOrder();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    // Handler executor
    assertEq(_nextExecutionOrderIndex, 0, "nextExecutionOrderIndex");
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after Executed Order
    _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    //user have to get refund
    assertEq(_nextExecutionOrderIndex, 1, "nextExecutionOrderIndex After executed");
    assertEq(_ordersAfter[0].amount, 0, "Amount order should be removed");
    assertEq(wbtc.balanceOf(ALICE), 1 ether);
  }

  function test_correctness_userRefund_removeLiquidity_revertAsMessage() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(true);

    _createRemoveLiquidityOrder();

    // Handler executor
    ILiquidityHandler.LiquidityOrder[] memory _ordersBefore = liquidityHandler.getLiquidityOrders();
    liquidityHandler.executeOrder(
      _ordersBefore.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after ExecuteOrder
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    //user have to get refund
    assertEq(_nextExecutionOrderIndex, 1, "nextExecutionOrderIndex After executed");
    assertEq(_ordersAfter[0].amount, 0, "Amount order should be removed");
    assertEq(hlp.balanceOf(ALICE), 5 ether);
  }

  function test_correctness_userRefund_removeLiquidity_revertAsBytes() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(false);

    _createRemoveLiquidityOrder();

    // Handler executor
    ILiquidityHandler.LiquidityOrder[] memory _ordersBefore = liquidityHandler.getLiquidityOrders();
    liquidityHandler.executeOrder(
      _ordersBefore.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after ExecuteOrder
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    //user have to get refund
    assertEq(_nextExecutionOrderIndex, 1, "nextExecutionOrderIndex After executed");
    assertEq(_ordersAfter[0].amount, 0, "Amount order should be removed");
    assertEq(hlp.balanceOf(ALICE), 5 ether);
  }

  /**
   * CORRECTNESS
   */

  function test_correctness_executeOrder_IncreaseOneOrder() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    // Handler executor
    assertEq(_nextExecutionOrderIndex, 0, "LastExecutedOrderIndex Before Execute");
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after Executed Order
    _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();

    assertEq(_nextExecutionOrderIndex, 1, "LastExecutedOrderIndex After Excuted");
    assertEq(_ordersAfter.length, _nextExecutionOrderIndex, "OrderAfter size != lastExecutedOrderIndex");
  }

  /// @dev hlp burn and receive tokenOut in service
  function test_correctness_executeOrder_createRemoveLiquidityOrder() external {
    _createRemoveLiquidityOrder();

    // Handler executor
    ILiquidityHandler.LiquidityOrder[] memory _ordersBefore = liquidityHandler.getLiquidityOrders();
    liquidityHandler.executeOrder(
      _ordersBefore.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );
    // Assertion after ExecuteOrder
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    uint256 _nextExecutionOrderIndex = liquidityHandler.nextExecutionOrderIndex();

    assertEq(_ordersAfter.length, 1, "Order Amount After Executed Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 1, "Order Index After Executed Order");
    assertEq(wbtc.balanceOf(ALICE), 5 ether, "ALICE received balance");
    assertEq(_ordersAfter.length, _nextExecutionOrderIndex, "OrderAfter size != lastExecutedOrderIndex");
  }

  function test_correctness_executeOrder_createRemoveLiquidityOrders() external {
    _createRemoveLiquidityOrder();
    _createRemoveLiquidityOrder();

    // Handler executor
    ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getLiquidityOrders();

    liquidityHandler.executeOrder(
      _orders.length - 1,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    assertEq(_orders.length, 2, "Order Amount After Executed Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 2, "Order Index After Executed Order");
    assertEq(wbtc.balanceOf(ALICE), 10 ether, "ALICE received balance");
  }

  /// @dev hlp burn and receive tokenOut in service
  function test_correctness_executeOrder_native_createRemoveLiquidityOrder() external {
    // 1 Create Native add liquidity
    vm.deal(ALICE, 10 ether); //5 for executeOrderFee , 5 for create liquidity position
    hlp.mint(address(liquidityHandler), 1);
    vm.startPrank(ALICE);

    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 10 ether }(
      address(weth),
      5 ether,
      0,
      5 ether,
      true
    );

    ILiquidityHandler.LiquidityOrder[] memory _beforeExecuteOrders = liquidityHandler.getLiquidityOrders();
    vm.stopPrank();

    // 2 Assert LIquidity Order
    assertEq(address(weth).balance, 10 ether, "weth balance");

    assertEq(_beforeExecuteOrders.length, 1, "Order Amount After Created Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 0, "Order Index After Created Order");

    assertEq(_beforeExecuteOrders[_orderIndex].account, ALICE, "Alice Order.account");
    assertEq(_beforeExecuteOrders[_orderIndex].token, address(weth), "Alice Order.token");
    assertEq(_beforeExecuteOrders[_orderIndex].amount, 5 ether, "Alice Order.amount");
    assertEq(_beforeExecuteOrders[_orderIndex].minOut, 0, "Alice Order.minOut");
    assertEq(_beforeExecuteOrders[_orderIndex].actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(_beforeExecuteOrders[_orderIndex].isAdd, true, "Alice Order.isAdd");
    assertEq(_beforeExecuteOrders[_orderIndex].executionFee, 5 ether, "Alice Order.executionFee");
    assertEq(_beforeExecuteOrders[_orderIndex].isNativeOut, true, "Alice Order.isNativeOut");

    // 3 execute create native order
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // 4 Assertion after ExecuteOrder
    ILiquidityHandler.LiquidityOrder[] memory _aliceOrdersAfter = liquidityHandler.getLiquidityOrders();

    assertEq(_aliceOrdersAfter.length, 1, "Order Amount After Executed Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 1, "Order Index After Executed Order");
    assertEq(ALICE.balance, 0, "ALICE received balance");

    assertEq(address(weth).balance, 5 ether, "weth balance 2");

    // 5 Create remove Liquidity order
    _orderIndex = _createRemoveLiquidityNativeOrder();
    assertEq(address(weth).balance, 10 ether, "weth balance 3");
    // 6 execute liquidity order
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );
    assertEq(address(weth).balance, 0 ether, "weth balance 4");

    _aliceOrdersAfter = liquidityHandler.getLiquidityOrders();

    // 7 Assertion after ExecuteOrder
    assertEq(_aliceOrdersAfter.length, 2, "Order Amount After Executed Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 2, "Order Index After Executed Order");
    assertEq(ALICE.balance, 5 ether, "ALICE received balance");
  }

  function test_correctness_executeOrder_native_refundCreateLiquidityOrder() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(false);

    // 1 Create Native add liquidity
    vm.deal(ALICE, 10 ether); //5 for executeOrderFee , 5 for create liquidity position
    vm.startPrank(ALICE);

    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 10 ether }(
      address(weth),
      5 ether,
      0,
      5 ether,
      true
    );

    ILiquidityHandler.LiquidityOrder[] memory _beforeExecuteOrders = liquidityHandler.getLiquidityOrders();
    vm.stopPrank();

    // 2 Assert LIquidity Order
    assertEq(_beforeExecuteOrders.length, 1, "Order Amount After Created Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 0, "Order Index After Created Order");

    assertEq(_beforeExecuteOrders[_orderIndex].account, ALICE, "Alice Order.account");
    assertEq(_beforeExecuteOrders[_orderIndex].token, address(weth), "Alice Order.token");
    assertEq(_beforeExecuteOrders[_orderIndex].amount, 5 ether, "Alice Order.amount");
    assertEq(_beforeExecuteOrders[_orderIndex].minOut, 0, "Alice Order.minOut");
    assertEq(_beforeExecuteOrders[_orderIndex].actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(_beforeExecuteOrders[_orderIndex].isAdd, true, "Alice Order.isAdd");
    assertEq(_beforeExecuteOrders[_orderIndex].executionFee, 5 ether, "Alice Order.executionFee");
    assertEq(_beforeExecuteOrders[_orderIndex].isNativeOut, true, "Alice Order.isNativeOut");

    // 3 execute create native order
    liquidityHandler.executeOrder(
      _orderIndex,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    // Assertion after Executed Order
    ILiquidityHandler.LiquidityOrder[] memory _ordersAfter = liquidityHandler.getLiquidityOrders();
    //user have to get refund
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 1, "nextExecutionOrderIndex After executed");
    assertEq(_ordersAfter[0].amount, 0, "Amount order should be removed");

    //alice will get 5 ether from order.amount (Native)
    assertEq(ALICE.balance, _beforeExecuteOrders[_orderIndex].amount, "Alice refund Balance");
  }

  function test_correctness_cancelOrder() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();
    _createAddLiquidityWBTCOrder();
    _createAddLiquidityWBTCOrder();

    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(_orderIndex);

    ILiquidityHandler.LiquidityOrder[] memory aliceOrders = liquidityHandler.getLiquidityOrders();
    assertEq(aliceOrders[0].account, address(0), "Alice account address");

    liquidityHandler.executeOrder(
      type(uint256).max,
      payable(FEEVER),
      priceUpdateData,
      publishTimeUpdateData,
      block.timestamp,
      keccak256("someEncodedVaas")
    );

    assertEq(liquidityHandler.nextExecutionOrderIndex(), 3);
  }

  function test_correctness_refunding_when_cancelOrder() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    // Check Alice balance before cancel
    assertEq(wbtc.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 0 ether);

    // Cancel
    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(_orderIndex);

    // Check Alice balance after cancel
    assertEq(wbtc.balanceOf(ALICE), 1 ether);
    assertEq(ALICE.balance, 5 ether);
  }

  function _createAddLiquidityWBTCOrder() internal returns (uint256) {
    vm.deal(ALICE, 5 ether); //deal with out of gas
    wbtc.mint(ALICE, 1 ether);

    vm.startPrank(ALICE);

    wbtc.approve(address(liquidityHandler), type(uint256).max);

    ILiquidityHandler.LiquidityOrder[] memory _beforeCreateOrders = liquidityHandler.getLiquidityOrders();

    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );

    // Assertion after createLiquidity
    // alice should has 0 wbtc (open order),  (5 weth left)
    // handler should has 1 order on alice
    assertEq(wbtc.balanceOf(ALICE), 0, "User Liquidity Balance");

    ILiquidityHandler.LiquidityOrder[] memory _beforeExecuteOrders = liquidityHandler.getLiquidityOrders();
    vm.stopPrank();

    assertEq(_beforeExecuteOrders.length, _beforeCreateOrders.length + 1, "Order Amount After Created Order");
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 0, "Order Index After Created Order");

    assertEq(_beforeExecuteOrders[_orderIndex].account, ALICE, "Alice Order.account");
    assertEq(_beforeExecuteOrders[_orderIndex].token, address(wbtc), "Alice Order.token");
    assertEq(_beforeExecuteOrders[_orderIndex].amount, 1 ether, "Alice Order.amount");
    assertEq(_beforeExecuteOrders[_orderIndex].minOut, 1 ether, "Alice Order.minOut");
    assertEq(_beforeExecuteOrders[_orderIndex].actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(_beforeExecuteOrders[_orderIndex].isAdd, true, "Alice Order.isAdd");
    assertEq(_beforeExecuteOrders[_orderIndex].isNativeOut, false, "Alice Order.isNativeOut");

    return _orderIndex;
  }

  function _createRemoveLiquidityOrder() internal returns (uint256) {
    uint256 hlpBalanceBefore = hlp.balanceOf(ALICE);
    vm.deal(ALICE, 5 ether);
    hlp.mint(ALICE, 5 ether);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), type(uint256).max);

    // hlpIn 5 ether, executionfee 5
    uint256 _index = liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      5 ether,
      0,
      5 ether,
      false
    );
    vm.stopPrank();

    assertEq(hlpBalanceBefore - hlp.balanceOf(ALICE), 0, "User HLP Balance");

    ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getLiquidityOrders();

    assertEq(_orders[_index].account, ALICE, "Alice Order.account");
    assertEq(_orders[_index].token, address(wbtc), "Alice Order.token");
    assertEq(_orders[_index].amount, 5 ether, "Alice HLP Order.amount");
    assertEq(_orders[_index].minOut, 0, "Alice WBTC Order.minOut");
    assertEq(_orders[_index].actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(_orders[_index].isAdd, false, "Alice Order.isAdd");
    assertEq(_orders[_index].isNativeOut, false, "Alice Order.isNativeOut");

    return _index;
  }

  function _createRemoveLiquidityNativeOrder() internal returns (uint256 _orderIndex) {
    uint256 hlpBalanceBefore = hlp.balanceOf(ALICE);
    vm.deal(ALICE, 5 ether);
    uint256 _amount = 5 ether;
    hlp.mint(ALICE, _amount);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), type(uint256).max);

    _orderIndex = liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(
      address(weth),
      _amount,
      0,
      5 ether,
      true
    );
    vm.stopPrank();

    assertEq(ALICE.balance, 0, "Alice Balance After createOrder");
    assertEq(
      ERC20(configStorage.weth()).balanceOf(address(liquidityHandler)),
      5 ether,
      "LiquidityHandler Order ExecutionFee"
    );
    assertEq(hlpBalanceBefore - hlp.balanceOf(ALICE), 0, "User HLP Balance");

    ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getLiquidityOrders();

    assertEq(_orders[_orderIndex].account, ALICE, "Alice Order.account");
    assertEq(_orders[_orderIndex].token, address(weth), "Alice Order.token");
    assertEq(_orders[_orderIndex].amount, _amount, "Alice HLP Order.amount");
    assertEq(_orders[_orderIndex].minOut, 0, "Alice WBTC Order.minOut");
    assertEq(_orders[_orderIndex].actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(_orders[_orderIndex].isAdd, false, "Alice Order.isAdd");
    assertEq(_orders[_orderIndex].executionFee, 5 ether, "Alice Execute fee");
    assertEq(_orders[_orderIndex].isNativeOut, true, "Alice Order.isNativeOut");

    return _orderIndex;
  }
}
