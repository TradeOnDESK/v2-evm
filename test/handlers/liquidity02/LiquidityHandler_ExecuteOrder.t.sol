// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { LiquidityHandler_Base02, IConfigStorage, IPerpStorage } from "./LiquidityHandler_Base02.t.sol";
import { ILiquidityHandler02 } from "@hmx/handlers/interfaces/ILiquidityHandler02.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { MockAccountAbstraction } from "../../mocks/MockAccountAbstraction.sol";
import { MockEntryPoint } from "../../mocks/MockEntryPoint.sol";

import "forge-std/console.sol";
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

contract LiquidityHandler_ExecuteOrder is LiquidityHandler_Base02 {
  bytes32[] internal priceUpdateData;
  bytes32[] internal publishTimeUpdateData;

  MockEntryPoint entryPoint;

  function setUp() public override {
    super.setUp();
    vm.prank(ALICE);
    liquidityHandler.setDelegate(ALICE);
    liquidityHandler.setOrderExecutor(address(this), true);

    entryPoint = new MockEntryPoint();
  }

  /**
   * REVERT
   */
  function test_revert_directCall_executeLiquidity02() external {
    _createAddLiquidityWBTCOrder();
    ILiquidityHandler02.LiquidityOrder[] memory aliceOrders = liquidityHandler.getAllActiveOrders(10, 0);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler02_Unauthorized()"));
    liquidityHandler.executeLiquidity(aliceOrders[0]);
  }

  function test_revert_executeOrder_notOrderExecutor02() external {
    uint256 index = _createAddLiquidityWBTCOrder();

    ILiquidityHandler02.LiquidityOrder[] memory _orders = liquidityHandler.getAllActiveOrders(10, 0);
    assertEq(_orders.length, 1);
    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = index;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler02_NotWhitelisted()"));
    liquidityHandler.executeOrders(params);
  }

  function test_revert_cancelOrder_notOwnerOrder02() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler02_InvalidOrder()"));
    liquidityHandler.cancelLiquidityOrder(ALICE, SUB_ID, _orderIndex);
  }

  function test_revert_cancelOrder_uncreatedOrder02() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler02_InvalidOrder()"));
    liquidityHandler.cancelLiquidityOrder(ALICE, SUB_ID, 0);
  }

  /**
   * CORRECTNESS
   */

  function test_correctness_userRefund_addLiquidity_revertAsMessage02() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(true);

    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = false;

    // Handler executor
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 0, "Should have none executed order");
    assertEq(wbtc.balanceOf(ALICE), 1 ether);
  }

  function test_correctness_userRefund_removeLiquidity_revertAsMessage02() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(true);

    uint256 _orderIndex = _createRemoveLiquidityOrder();

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = false;

    // Handler executor
    liquidityHandler.executeOrders(params);

    // Assertion after ExecuteOrder
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 0, "Should have none executed order");
    assertEq(hlp.balanceOf(ALICE), 5 ether);
  }

  function test_correctness_executeOrder_IncreaseOneOrder02() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    // Handler executor
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 1, "Should have one executed order");
  }

  function test_correctness_executeOrder_IncreaseOneOrder_delegate() external {
    wbtc.mint(ALICE, 1 ether);

    MockAccountAbstraction DELEGATE = new MockAccountAbstraction(address(entryPoint));
    vm.deal(address(DELEGATE), 5 ether); //deal with out of gas

    vm.startPrank(ALICE);
    liquidityHandler.setDelegate(address(DELEGATE));
    wbtc.approve(address(liquidityHandler), type(uint256).max);
    vm.stopPrank();

    vm.prank(address(DELEGATE));
    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      ALICE,
      SUB_ID,
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );

    // Assertion after createLiquidity
    // alice should has 0 wbtc (open order),  (5 weth left)
    // handler should has 1 order on alice

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    // Handler executor
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 1, "Should have one executed order");
  }

  /// @dev hlp burn and receive tokenOut in service
  function test_correctness_executeOrder_createRemoveLiquidityOrder02() external {
    uint256 orderIndex = _createRemoveLiquidityOrder();

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    // Handler executor
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);

    assertEq(activeOrders.length, 0, "Active Order Amount After Executed Order");
    assertEq(executedOrders.length, 1, "Order Amount After Executed Order");
    assertEq(wbtc.balanceOf(ALICE), 5 ether, "ALICE received balance");
  }

  function test_correctness_executeOrder_createRemoveLiquidityOrders02() external {
    uint256 index1 = _createRemoveLiquidityOrder();
    uint256 index2 = _createRemoveLiquidityOrder();

    // Handler executor
    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](2);
    uint8[] memory subAccountIds = new uint8[](2);
    uint256[] memory orderIndexes = new uint256[](2);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = index1;
    accounts[1] = ALICE;
    subAccountIds[1] = SUB_ID;
    orderIndexes[1] = index2;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    ILiquidityHandler02.LiquidityOrder[] memory activeOrdersBefore = liquidityHandler.getAllActiveOrders(10, 0);
    assertEq(activeOrdersBefore.length, 2, "Should have none active order");

    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 2, "Should have none executed order");
    assertEq(wbtc.balanceOf(ALICE), 10 ether, "ALICE received balance");
  }

  /// @dev hlp burn and receive tokenOut in service
  function test_correctness_executeOrder_native_createRemoveLiquidityOrder02() external {
    // 1 Create Native add liquidity
    vm.deal(ALICE, 10 ether); //5 for executeOrderFee , 5 for create liquidity position
    vm.prank(ALICE);
    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 10 ether }(
      ALICE,
      SUB_ID,
      address(weth),
      5 ether,
      0,
      5 ether,
      true
    );

    ILiquidityHandler02.LiquidityOrder memory beforeExecuteOrder = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );

    // 2 Assert LIquidity Order
    assertEq(beforeExecuteOrder.account, ALICE, "Alice Order.account");
    assertEq(beforeExecuteOrder.token, address(weth), "Alice Order.token");
    assertEq(beforeExecuteOrder.amount, 5 ether, "Alice Order.amount");
    assertEq(beforeExecuteOrder.minOut, 0, "Alice Order.minOut");
    assertEq(beforeExecuteOrder.actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(beforeExecuteOrder.isAdd, true, "Alice Order.isAdd");
    assertEq(beforeExecuteOrder.executionFee, 5 ether, "Alice Order.executionFee");
    assertEq(beforeExecuteOrder.isNativeOut, true, "Alice Order.isNativeOut");

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = false;

    // 3 execute create native order
    liquidityHandler.executeOrders(params);

    // 4 Assertion after ExecuteOrder
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    assertEq(activeOrders.length, 0, "Active Order Amount After Executed Order");
    assertEq(executedOrders.length, 1, "Executed Order Amount After Executed Order");
    assertEq(ALICE.balance, 0, "ALICE received balance");

    // 5 Create remove Liquidity order
    uint256 _orderIndex02 = _createRemoveLiquidityNativeOrder();
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders02 = liquidityHandler.getAllActiveOrders(10, 0);
    assertEq(activeOrders02.length, 1, "Active Order Amount");

    // 6 execute liquidity order
    orderIndexes[0] = _orderIndex02;
    params.orderIndexes = orderIndexes;

    liquidityHandler.executeOrders(params);

    ILiquidityHandler02.LiquidityOrder[] memory activeOrders03 = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders02 = liquidityHandler.getAllExecutedOrders(10, 0);

    // 7 Assertion after ExecuteOrder
    assertEq(activeOrders03.length, 0, "Order Amount After Executed Order");
    assertEq(executedOrders02.length, 2, "Executed Order Amount After Executed Order");
    assertEq(ALICE.balance, 5 ether, "ALICE received balance");
  }

  function test_correctness_executeOrder_native_refundCreateLiquidityOrder02() external {
    mockLiquidityService.setReverted(true);
    mockLiquidityService.setRevertAsMessage(false);

    // 1 Create Native add liquidity
    vm.deal(ALICE, 10 ether); //5 for executeOrderFee , 5 for create liquidity position
    vm.startPrank(ALICE);

    uint256 _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 10 ether }(
      ALICE,
      SUB_ID,
      address(weth),
      5 ether,
      0,
      5 ether,
      true
    );

    ILiquidityHandler02.LiquidityOrder memory beforeExecuteOrder = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );

    // 2 Assert LIquidity Order
    assertEq(beforeExecuteOrder.account, ALICE, "Alice Order.account");
    assertEq(beforeExecuteOrder.token, address(weth), "Alice Order.token");
    assertEq(beforeExecuteOrder.amount, 5 ether, "Alice Order.amount");
    assertEq(beforeExecuteOrder.minOut, 0, "Alice Order.minOut");
    assertEq(beforeExecuteOrder.actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(beforeExecuteOrder.isAdd, true, "Alice Order.isAdd");
    assertEq(beforeExecuteOrder.executionFee, 5 ether, "Alice Order.executionFee");
    assertEq(beforeExecuteOrder.isNativeOut, true, "Alice Order.isNativeOut");
    vm.stopPrank();

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = false;

    // 3 execute create native order
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);

    ILiquidityHandler02.LiquidityOrder memory order = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 0, "Should have none executed order");
    assertEq(order.amount, 0, "Amount in order should be decreased to 0");

    //alice will get 5 ether from order.amount (Native)
    assertEq(ALICE.balance, beforeExecuteOrder.amount, "Alice refund Balance");
  }

  function test_correctness_cancelOrder02() external {
    assertEq(liquidityHandler.getAllActiveOrders(5, 0).length, 0);
    uint256 _orderIndex01 = _createAddLiquidityWBTCOrder();
    uint256 _orderIndex02 = _createAddLiquidityWBTCOrder();
    uint256 _orderIndex03 = _createAddLiquidityWBTCOrder();
    assertEq(liquidityHandler.getAllActiveOrders(5, 0).length, 3);

    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(ALICE, SUB_ID, _orderIndex01);
    assertEq(liquidityHandler.getAllActiveOrders(5, 0).length, 2);

    ILiquidityHandler02.LiquidityOrder memory order = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex01
    );
    assertEq(order.account, address(0), "Alice account address");

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](2);
    uint8[] memory subAccountIds = new uint8[](2);
    uint256[] memory orderIndexes = new uint256[](2);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex02;
    accounts[1] = ALICE;
    subAccountIds[1] = SUB_ID;
    orderIndexes[1] = _orderIndex03;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = false;

    liquidityHandler.executeOrders(params);

    assertEq(liquidityHandler.getAllExecutedOrders(5, 0).length, 2);
    assertEq(liquidityHandler.getAllActiveOrders(5, 0).length, 0);
  }

  function test_correctness_refunding_when_cancelOrder02() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    // Check Alice balance before cancel
    assertEq(wbtc.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 0 ether);

    // Cancel
    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(ALICE, SUB_ID, _orderIndex);

    // Check Alice balance after cancel
    assertEq(wbtc.balanceOf(ALICE), 1 ether);
    assertEq(ALICE.balance, 5 ether);
  }

  function _createAddLiquidityWBTCOrder() internal returns (uint256 _orderIndex) {
    vm.deal(ALICE, 5 ether); //deal with out of gas
    wbtc.mint(ALICE, 1 ether);

    ILiquidityHandler02.LiquidityOrder[] memory _beforeCreateOrders = liquidityHandler.getAllActiveOrders(10, 0);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), type(uint256).max);
    _orderIndex = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      ALICE,
      SUB_ID,
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );

    // Assertion after createLiquidity
    // alice should has 0 wbtc (open order),  (5 weth left)
    // handler should has 1 order on alice
    vm.stopPrank();
    assertEq(wbtc.balanceOf(ALICE), 0, "User Liquidity Balance");

    ILiquidityHandler02.LiquidityOrder[] memory _beforeExecuteOrders = liquidityHandler.getAllActiveOrders(10, 0);
    assertEq(_beforeExecuteOrders.length, _beforeCreateOrders.length + 1, "Order Amount After Created Order");

    ILiquidityHandler02.LiquidityOrder memory order = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );

    assertEq(order.account, ALICE, "Alice Order.account");
    assertEq(order.token, address(wbtc), "Alice Order.token");
    assertEq(order.amount, 1 ether, "Alice Order.amount");
    assertEq(order.minOut, 1 ether, "Alice Order.minOut");
    assertEq(order.actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(order.isAdd, true, "Alice Order.isAdd");
    assertEq(order.isNativeOut, false, "Alice Order.isNativeOut");
  }

  function _createRemoveLiquidityOrder() internal returns (uint256 _orderIndex) {
    vm.deal(ALICE, 5 ether);
    hlp.mint(ALICE, 5 ether);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), type(uint256).max);

    // hlpIn 5 ether, executionfee 5
    _orderIndex = liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(
      ALICE,
      SUB_ID,
      address(wbtc),
      5 ether,
      0,
      5 ether,
      false
    );
    vm.stopPrank();

    assertEq(hlp.balanceOf(ALICE), 0, "User HLP Balance");

    ILiquidityHandler02.LiquidityOrder memory order = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );

    assertEq(order.account, ALICE, "Alice Order.account");
    assertEq(order.token, address(wbtc), "Alice Order.token");
    assertEq(order.amount, 5 ether, "Alice HLP Order.amount");
    assertEq(order.minOut, 0, "Alice WBTC Order.minOut");
    assertEq(order.actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(order.isAdd, false, "Alice Order.isAdd");
    assertEq(order.isNativeOut, false, "Alice Order.isNativeOut");
  }

  function _createRemoveLiquidityNativeOrder() internal returns (uint256 _orderIndex) {
    vm.deal(ALICE, 5 ether);
    uint256 _amount = 5 ether;
    hlp.mint(ALICE, _amount);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), type(uint256).max);

    _orderIndex = liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(
      ALICE,
      SUB_ID,
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
    assertEq(hlp.balanceOf(ALICE), 0, "User HLP Balance");

    ILiquidityHandler02.LiquidityOrder memory order = liquidityHandler.getLiquidityOrderOfAccountPerIndex(
      ALICE,
      SUB_ID,
      _orderIndex
    );

    assertEq(order.account, ALICE, "Alice Order.account");
    assertEq(order.token, address(weth), "Alice Order.token");
    assertEq(order.amount, _amount, "Alice HLP Order.amount");
    assertEq(order.minOut, 0, "Alice WBTC Order.minOut");
    assertEq(order.actualAmountOut, 0, "Alice Order.actualAmountOut");
    assertEq(order.isAdd, false, "Alice Order.isAdd");
    assertEq(order.executionFee, 5 ether, "Alice Execute fee");
    assertEq(order.isNativeOut, true, "Alice Order.isNativeOut");
  }

  function test_revert_executeOrder_canceledOrder() external {
    uint256 _orderIndex = _createAddLiquidityWBTCOrder();

    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(ALICE, SUB_ID, _orderIndex);

    ILiquidityHandler02.ExecuteOrdersParam memory params;
    address[] memory accounts = new address[](1);
    uint8[] memory subAccountIds = new uint8[](1);
    uint256[] memory orderIndexes = new uint256[](1);
    accounts[0] = ALICE;
    subAccountIds[0] = SUB_ID;
    orderIndexes[0] = _orderIndex;

    params.accounts = accounts;
    params.subAccountIds = subAccountIds;
    params.orderIndexes = orderIndexes;
    params.feeReceiver = payable(FEEVER);
    params.priceData = priceUpdateData;
    params.publishTimeData = publishTimeUpdateData;
    params.minPublishTime = block.timestamp;
    params.encodedVaas = keccak256("someEncodedVaas");
    params.isRevert = true;

    // Handler executor
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler02_NonExistentOrder()"));
    liquidityHandler.executeOrders(params);

    // Assertion after Executed Order
    ILiquidityHandler02.LiquidityOrder[] memory activeOrders = liquidityHandler.getAllActiveOrders(10, 0);
    ILiquidityHandler02.LiquidityOrder[] memory executedOrders = liquidityHandler.getAllExecutedOrders(10, 0);
    //user have to get refund
    assertEq(activeOrders.length, 0, "Should have none active order");
    assertEq(executedOrders.length, 0, "Should have none executed order");
  }
}
