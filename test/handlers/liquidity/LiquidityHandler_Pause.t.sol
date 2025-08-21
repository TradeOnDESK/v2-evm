// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { LiquidityHandler_Base, IConfigStorage, IPerpStorage } from "./LiquidityHandler_Base.t.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";

contract LiquidityHandler_Pause is LiquidityHandler_Base {
  function setUp() public override {
    super.setUp();

    liquidityHandler.setOrderExecutor(address(this), true);
  }

  /**
   * PAUSE ACCESS CONTROL TESTS
   */

  function test_pause_onlyOwner() external {
    // Only owner can pause
    vm.prank(address(this)); // this contract is the owner
    liquidityHandler.pause();

    assertTrue(liquidityHandler.paused());
  }

  function test_revert_pause_notOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityHandler.pause();
  }

  function test_unpause_onlyOwner() external {
    // First pause the contract
    vm.prank(address(this));
    liquidityHandler.pause();

    // Only owner can unpause
    vm.prank(address(this));
    liquidityHandler.unpause();

    assertFalse(liquidityHandler.paused());
  }

  function test_revert_unpause_notOwner() external {
    // First pause the contract
    vm.prank(address(this));
    liquidityHandler.pause();

    // Non-owner cannot unpause
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidityHandler.unpause();
  }

  /**
   * PAUSE STATE AND EVENTS TESTS
   */

  function test_pause_emitsEvent() external {
    vm.expectEmit(true, false, false, false);
    emit LogPaused(address(this));

    liquidityHandler.pause();
  }

  function test_unpause_emitsEvent() external {
    // First pause
    liquidityHandler.pause();

    vm.expectEmit(true, false, false, false);
    emit LogUnpaused(address(this));

    liquidityHandler.unpause();
  }

  function test_pause_stateChange() external {
    // Initially not paused
    assertFalse(liquidityHandler.paused());

    // Pause the contract
    liquidityHandler.pause();
    assertTrue(liquidityHandler.paused());

    // Unpause the contract
    liquidityHandler.unpause();
    assertFalse(liquidityHandler.paused());
  }

  /**
   * BLOCKED FUNCTIONS WHEN PAUSED TESTS
   */

  function test_revert_createAddLiquidityOrder_whenPaused() external {
    // Pause the contract
    liquidityHandler.pause();

    wbtc.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 1 ether);

    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_ContractPaused()"));
    liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);

    vm.stopPrank();
  }

  function test_revert_createAddLiquidityOrder_withAutoStake_whenPaused() external {
    // Pause the contract
    liquidityHandler.pause();

    wbtc.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 1 ether);

    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_ContractPaused()"));
    liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);

    vm.stopPrank();
  }

  function test_revert_createRemoveLiquidityOrder_whenPaused() external {
    // Pause the contract
    liquidityHandler.pause();

    hlp.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), 1 ether);

    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_ContractPaused()"));
    liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);

    vm.stopPrank();
  }

  /**
   * ALLOWED FUNCTIONS WHEN PAUSED TESTS
   */

  function test_createAddLiquidityOrder_worksWhenNotPaused() external {
    // Ensure contract is not paused
    assertFalse(liquidityHandler.paused());

    wbtc.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 1 ether);

    // Should work when not paused
    uint256 orderId = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );
    assertEq(orderId, 0);

    vm.stopPrank();
  }

  function test_createRemoveLiquidityOrder_worksWhenNotPaused() external {
    // Ensure contract is not paused
    assertFalse(liquidityHandler.paused());

    hlp.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    hlp.approve(address(liquidityHandler), 1 ether);

    // Should work when not paused
    uint256 orderId = liquidityHandler.createRemoveLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );
    assertEq(orderId, 0);

    vm.stopPrank();
  }

  function test_cancelLiquidityOrder_worksWhenPaused() external {
    // Create an order first
    wbtc.mint(ALICE, 1 ether);
    vm.deal(ALICE, 10 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 1 ether);
    uint256 orderId = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );
    vm.stopPrank();

    // Pause the contract
    liquidityHandler.pause();

    // Should still be able to cancel orders when paused
    vm.prank(ALICE);
    liquidityHandler.cancelLiquidityOrder(orderId);

    // Verify order was cancelled (amount should be 0)
    ILiquidityHandler.LiquidityOrder memory order = liquidityHandler.getLiquidityOrders()[0];
    assertEq(order.amount, 0);
  }

  function test_executeOrder_worksWhenPaused() external {
    // Create an order first
    _createAddLiquidityOrder();

    // Pause the contract
    liquidityHandler.pause();

    // Should still be able to execute orders when paused
    bytes32[] memory priceData = new bytes32[](1);
    bytes32[] memory publishTimeData = new bytes32[](1);

    liquidityHandler.executeOrder(0, payable(address(this)), priceData, publishTimeData, block.timestamp, bytes32(0));

    // Verify order was executed
    assertEq(liquidityHandler.nextExecutionOrderIndex(), 1);
  }

  function test_getters_workWhenPaused() external {
    // Create an order first
    _createAddLiquidityOrder();

    // Pause the contract
    liquidityHandler.pause();

    // Should still be able to call getter functions when paused
    uint256 length = liquidityHandler.getLiquidityOrderLength();
    assertEq(length, 1);

    ILiquidityHandler.LiquidityOrder[] memory orders = liquidityHandler.getLiquidityOrders();
    assertEq(orders.length, 1);

    ILiquidityHandler.LiquidityOrder[] memory activeOrders = liquidityHandler.getActiveLiquidityOrders(10, 0);
    assertEq(activeOrders.length, 1);
  }

  function test_setters_workWhenPaused() external {
    // Pause the contract
    liquidityHandler.pause();

    // Should still be able to call setter functions when paused (as owner)
    liquidityHandler.setMinExecutionFee(6 ether);
    liquidityHandler.setMaxExecutionChunk(20);
    liquidityHandler.setOrderExecutor(ALICE, true);
  }

  /**
   * INTEGRATION TESTS
   */

  function test_pauseUnpause_integration() external {
    // 1. Create order when not paused - should work
    wbtc.mint(ALICE, 2 ether); // Mint enough for both orders
    vm.deal(ALICE, 10 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 2 ether); // Approve enough for both orders
    liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);
    vm.stopPrank();

    // 2. Pause contract
    liquidityHandler.pause();

    // 3. Try to create order when paused - should fail
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("ILiquidityHandler_ContractPaused()"));
    liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);
    vm.stopPrank();

    // 4. Execute existing order when paused - should work
    bytes32[] memory priceData = new bytes32[](1);
    bytes32[] memory publishTimeData = new bytes32[](1);

    liquidityHandler.executeOrder(0, payable(address(this)), priceData, publishTimeData, block.timestamp, bytes32(0));

    // 5. Unpause contract
    liquidityHandler.unpause();

    // 6. Create order when unpaused - should work again
    vm.startPrank(ALICE);
    uint256 orderId2 = liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(
      address(wbtc),
      1 ether,
      1 ether,
      5 ether,
      false
    );
    assertEq(orderId2, 1);
    vm.stopPrank();
  }

  /**
   * HELPER FUNCTIONS
   */

  function _createAddLiquidityOrder() internal {
    wbtc.mint(ALICE, 1 ether);
    vm.deal(ALICE, 5 ether);

    vm.startPrank(ALICE);
    wbtc.approve(address(liquidityHandler), 1 ether);
    liquidityHandler.createAddLiquidityOrder{ value: 5 ether }(address(wbtc), 1 ether, 1 ether, 5 ether, false);
    vm.stopPrank();
  }

  /**
   * EVENTS
   */
  event LogPaused(address account);
  event LogUnpaused(address account);
}
