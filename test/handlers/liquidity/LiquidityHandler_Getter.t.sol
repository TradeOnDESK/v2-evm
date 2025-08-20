// // SPDX-License-Identifier: BUSL-1.1
// // This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// // The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

// pragma solidity 0.8.18;

// import { LiquidityHandler_Base, IConfigStorage, IPerpStorage } from "./LiquidityHandler_Base.t.sol";
// import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";

// contract LiquidityHandler_Getter is LiquidityHandler_Base {
//   bytes32[] internal priceUpdateData;
//   bytes32[] internal publishTimeUpdateData;

//   function setUp() public override {
//     super.setUp();

//     liquidityHandler.setOrderExecutor(address(this), true);
//   }

//   function _createOrder() internal {
//     vm.deal(ALICE, 5 ether);
//     wbtc.mint(ALICE, 1 ether);

//     vm.prank(ALICE);
//     wbtc.approve(address(liquidityHandler), 1 ether);
//     vm.prank(ALICE);
//     liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);
//   }

//   function _executeOrder(uint256 count) internal {
//     liquidityHandler.executeOrder(
//       liquidityHandler.nextExecutionOrderIndex() + count - 1,
//       payable(FEEVER),
//       priceUpdateData,
//       publishTimeUpdateData,
//       block.timestamp,
//       keccak256("someEncodedVaas")
//     );
//   }

//   function testCorrectness_getActiveLiquidityOrders() external {
//     assertEq(liquidityHandler.getActiveLiquidityOrders(10, 0).length, 0);

//     _createOrder();
//     _createOrder();
//     _createOrder();
//     assertEq(liquidityHandler.getActiveLiquidityOrders(10, 0).length, 3);

//     _executeOrder(3);
//     assertEq(liquidityHandler.getActiveLiquidityOrders(10, 0).length, 0);

//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     assertEq(liquidityHandler.getActiveLiquidityOrders(20, 0).length, 11);

//     assertEq(liquidityHandler.getActiveLiquidityOrders(4, 0).length, 4);
//     assertEq(liquidityHandler.getActiveLiquidityOrders(4, 4).length, 4);
//     assertEq(liquidityHandler.getActiveLiquidityOrders(4, 8).length, 3);

//     // Check order id
//     {
//       ILiquidityHandler.LiquidityOrder[] memory _orders;
//       _orders = liquidityHandler.getActiveLiquidityOrders(7, 0);
//       for (uint256 i = 0; i < _orders.length; i++) {
//         assertEq(_orders[i].orderId, liquidityHandler.nextExecutionOrderIndex() + i);
//       }
//     }
//   }

//   function testCorrectness_getExecutedLiquidityOrders() external {
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 10, 0).length, 0);

//     _createOrder();
//     _createOrder();
//     _createOrder();
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 10, 0).length, 0);

//     _executeOrder(3);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 10, 3).length, 0);

//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     _createOrder();
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 20, 0).length, 3);

//     _executeOrder(11);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 20, 0).length, 13);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 4, 0).length, 4);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 4, 4).length, 4);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 4, 8).length, 4);
//     assertEq(liquidityHandler.getExecutedLiquidityOrders(ALICE, 4, 12).length, 1);

//     // Check order id
//     {
//       ILiquidityHandler.LiquidityOrder[] memory _orders;
//       _orders = liquidityHandler.getExecutedLiquidityOrders(ALICE, 20, 0);
//       for (uint256 i = 0; i < _orders.length; i++) {
//         assertEq(_orders[i].orderId, i);
//         assertEq(uint(_orders[i].status), 1);
//         assertEq(_orders[i].actualAmountOut > 0, true);
//       }
//     }
//   }

//   function testCorrectness_getOrders_timestampCorrectness() external {
//     vm.warp(block.timestamp + 100);

//     // Open 2 orders
//     _createOrder(); // Intention: success
//     _createOrder(); // Intention: fail

//     // assert timestamp and status
//     {
//       ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getActiveLiquidityOrders(2, 0);

//       assertEq(_orders[0].orderId, 0);
//       assertEq(_orders[0].createdTimestamp, 101);
//       assertEq(_orders[0].executedTimestamp, 0);
//       assertEq(uint(_orders[0].status), 0); // pending

//       assertEq(_orders[1].orderId, 1);
//       assertEq(_orders[1].createdTimestamp, 101);
//       assertEq(_orders[1].executedTimestamp, 0);
//       assertEq(uint(_orders[1].status), 0); // pending
//     }

//     vm.warp(block.timestamp + 100);

//     // Execute
//     _executeOrder(1);
//     mockLiquidityService.setReverted(true);
//     _executeOrder(1); // make the second order fail

//     // assert timestamp and status
//     {
//       ILiquidityHandler.LiquidityOrder[] memory _orders = liquidityHandler.getExecutedLiquidityOrders(ALICE, 2, 0);

//       assertEq(_orders[0].orderId, 0);
//       assertEq(_orders[0].createdTimestamp, 101);
//       assertEq(_orders[0].executedTimestamp, 201);
//       assertEq(uint(_orders[0].status), 1); // success

//       assertEq(_orders[1].orderId, 1);
//       assertEq(_orders[1].createdTimestamp, 101);
//       assertEq(_orders[1].executedTimestamp, 201);
//       assertEq(uint(_orders[1].status), 2); // fail
//     }
//   }
// }
