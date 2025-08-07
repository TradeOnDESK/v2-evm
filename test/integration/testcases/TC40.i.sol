// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

// import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { MockErc20 } from "@hmx-test/mocks/MockErc20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";

contract TC40 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;

  function testCorrectness_TC40_TransferCollateralSubAccount_WETH() external {
    address _tokenAddress = address(weth);

    vm.startPrank(EXT01_EXECUTOR);
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[2] = 0; // USDC tick price $1
    tickPrices[6] = 48285; // JPY tick price $125
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    bytes32[] memory _priceData = pyth.buildPriceUpdateData(tickPrices);
    address[] memory accounts = new address[](1);
    accounts[0] = ALICE;
    uint8[] memory subAccountIds = new uint8[](1);
    vm.stopPrank();

    // T0: Initialized state
    {
      //deal with out of gas
      vm.deal(BOB, 10 ether);
      vm.deal(BOT, 10 ether);

      // Mint liquidity for BOB
      usdc.mint(BOB, 10_000_000 * 1e6);

      // Mint collateral and gas for ALICE
      vm.deal(ALICE, 20 ether);
    }

    // BOB add liquidity
    addLiquidity(BOB, usdc, 10_000_000 * 1e6, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    // Deposit Collateral
    depositCollateral(ALICE, 0, ERC20(_tokenAddress), 10 ether, true);

    // Try transfer bad amount (0)
    {
      vm.expectRevert(abi.encodeWithSignature("IExt01Handler_BadAmount()"));
      transferCollateralSubAccount(ALICE, 0, 1, _tokenAddress, 0);
    }

    // Try transfer too much amount
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 0, 1, _tokenAddress, 30 ether);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 0;
      // Expect Revert from insufficient collateral
      vm.expectRevert();
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Try transfer to self
    {
      vm.expectRevert(abi.encodeWithSignature("IExt01Handler_SelfTransfer()"));
      transferCollateralSubAccount(ALICE, 0, 0, _tokenAddress, 10 ether);
    }

    // Try transfer collateral btw. subAccount
    {
      address _aliceSubAccount0 = getSubAccount(ALICE, 0);
      address _aliceSubAccount1 = getSubAccount(ALICE, 1);
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 0, 1, _tokenAddress, 10 ether);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 0;
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
      assertSubAccountTokenBalance(_aliceSubAccount0, _tokenAddress, false, 0);
      assertSubAccountTokenBalance(_aliceSubAccount1, _tokenAddress, true, 10 ether);
    }

    // Market order long
    {
      marketBuy(ALICE, 1, wethMarketIndex, 10_000 * 1e30, _tokenAddress, tickPrices, publishTimeDiff, block.timestamp);
    }

    // Try transfer collteral
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _tokenAddress, 5 ether);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Try transfer collateral exceeds IMR
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _tokenAddress, 4.9 ether);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      // Expect Revert from withdraw balance below IMR
      vm.expectRevert();
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Close current position
    {
      marketSell(ALICE, 1, wethMarketIndex, 10_000 * 1e30, _tokenAddress, tickPrices, publishTimeDiff, block.timestamp);
    }

    // Transfer leftover collateral to subAccount 0
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _tokenAddress, 4.9 ether);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }
  }

  function testCorrectness_TC40_TransferCollateralSubAccount_WBTC() external {
    wbtc.mint(ALICE, 0.5 * 1e8);
    _testTransferCollateralSubAccountERC20Helper(address(wbtc), 0.5 * 1e8, 100_000 * 1e30, 0.25 * 1e8, 0.23 * 1e8);
  }

  function testCorrectness_TC40_TransferCollateralSubAccount_USDC() external {
    usdc.mint(ALICE, 10_000 * 1e6);
    _testTransferCollateralSubAccountERC20Helper(address(usdc), 10_000 * 1e6, 100_000 * 1e30, 5_000 * 1e6, 4_500 * 1e6);
  }

  function _testTransferCollateralSubAccountERC20Helper(
    address _token,
    uint256 _deltAmount,
    uint256 _sizeDelta,
    uint256 _transfer1,
    uint256 _transfer2
  ) internal {
    tickPrices[1] = 99039; // WBTC tick price $20,000
    tickPrices[2] = 0; // USDC tick price $1
    tickPrices[6] = 48285; // JPY tick price $125
    bytes32[] memory _publishTimeData = new bytes32[](3);
    _publishTimeData[0] = bytes32(0);
    _publishTimeData[1] = bytes32(0);
    _publishTimeData[2] = bytes32(0);
    bytes32[] memory _priceData = pyth.buildPriceUpdateData(tickPrices);
    address[] memory accounts = new address[](1);
    accounts[0] = ALICE;
    uint8[] memory subAccountIds = new uint8[](1);

    // T0: Initialized state
    {
      //deal with out of gas
      vm.deal(BOB, 10 ether);
      vm.deal(BOT, 10 ether);

      // Mint liquidity for BOB
      usdc.mint(BOB, 1_000_000 * 1e6);

      // Mint collateral and gas for ALICE
      vm.deal(ALICE, 10 ether);
    }

    // BOB add liquidity
    addLiquidity(BOB, usdc, 1_000_000 * 1e6, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    // Deposit Collateral
    depositCollateral(ALICE, 0, ERC20(_token), _deltAmount);

    // Try transfer bad amount (0)
    {
      vm.expectRevert(abi.encodeWithSignature("IExt01Handler_BadAmount()"));
      transferCollateralSubAccount(ALICE, 0, 1, _token, 0);
    }

    // Try transfer too much amount
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 0, 1, _token, 1e30);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 0;
      // Expect Revert from Insufficient Balance
      vm.expectRevert();
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Try transfer to self
    {
      vm.expectRevert(abi.encodeWithSignature("IExt01Handler_SelfTransfer()"));
      transferCollateralSubAccount(ALICE, 0, 0, _token, _deltAmount);
    }

    // Try transfer collateral btw. subAccount
    {
      // Get SubAccount address
      address _aliceSubAccount0 = getSubAccount(ALICE, 0);
      address _aliceSubAccount1 = getSubAccount(ALICE, 1);
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 0, 1, _token, _deltAmount);
      subAccountIds[0] = 0;
      vm.startPrank(EXT01_EXECUTOR);
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
      assertSubAccountTokenBalance(_aliceSubAccount0, _token, false, 0);
      assertSubAccountTokenBalance(_aliceSubAccount1, _token, true, _deltAmount);
    }

    // Market order long
    {
      marketBuy(ALICE, 1, wethMarketIndex, _sizeDelta, _token, tickPrices, publishTimeDiff, block.timestamp);
    }

    // Try transfer collteral
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _token, _transfer1);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Try transfer collateral exceeds IMR
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _token, _transfer2);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      // Expect Revert from withdraw balance below IMR
      vm.expectRevert();
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }

    // Close current position
    {
      marketSell(ALICE, 1, wethMarketIndex, _sizeDelta, _token, tickPrices, publishTimeDiff, block.timestamp);
    }

    // Transfer leftover collateral to subAccount 0
    {
      uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 1, 0, _token, _transfer2);
      vm.startPrank(EXT01_EXECUTOR);
      subAccountIds[0] = 1;
      ext01Handler.executeOrders(
        accounts,
        subAccountIds,
        _orderIndexes,
        payable(EXT01_EXECUTOR),
        _priceData,
        _publishTimeData,
        block.timestamp,
        "",
        true
      );
      vm.stopPrank();
    }
  }

  function testCorrectness_CancelTransferCollateralOrder() external {
    usdc.mint(ALICE, 10_000 * 1e6);
    vm.deal(ALICE, 10 ether);
    uint256[] memory _orderIndexes = transferCollateralSubAccount(ALICE, 0, 1, address(usdc), 100 * 1e6);
    vm.startPrank(ALICE);
    assertEq(ext01Handler.getAllActiveOrders(3, 0).length, 1);
    // cancel order, should have 0 active, 0 execute.
    uint256 balanceBefore = ALICE.balance;

    ext01Handler.cancelOrder(ALICE, 0, _orderIndexes[0]);
    vm.stopPrank();

    assertEq(ALICE.balance - balanceBefore, 100 * 1e6);
    assertEq(ext01Handler.getAllActiveOrders(3, 0).length, 0);
    assertEq(ext01Handler.getAllExecutedOrders(3, 0).length, 0);
  }
}
