// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Smoke_Base } from "./Smoke_Base.t.sol";
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { CrossMarginHandler } from "@hmx/handlers/CrossMarginHandler.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { LimitTradeHandler } from "@hmx/handlers/LimitTradeHandler.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { SafeCastUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";

contract Smoke_Trade is ForkEnv {
  using SafeCastUpgradeable for int64;
  uint8 internal constant SUB_ACCOUNT_NO = 0;
  uint256 internal constant MARKET_INDEX = 1;
  // eth | jpy | xag | sol | chf
  uint256[] internal ARRAY_MARKET_INDEX = [0, 1, 15, 20, 21];

  function openClosePosition() external {
    _depositCollateral();
    _createAndExecuteMarketBuyOrder();
    _createAndExecuteMarketSellOrder();
  }

  function _depositCollateral() internal {
    uint8 tokenDecimal = IERC20(address(ForkEnv.usdc_e)).decimals();
    deal(address(usdc_e), ALICE, 1000 * (10 ** tokenDecimal));
    vm.startPrank(ALICE);
    usdc_e.approve(address(ForkEnv.crossMarginHandler), type(uint256).max);
    ForkEnv.crossMarginHandler.depositCollateral(SUB_ACCOUNT_NO, address(usdc_e), 1000 * (10 ** tokenDecimal), false);
    vm.stopPrank();
  }

  function _createAndExecuteMarketBuyOrder() internal {
    // Whitelist limit order executor in LimitTradeHandler
    vm.prank(ForkEnv.proxyAdmin.owner());
    ForkEnv.limitTradeHandler.setWhitelistExecutor(ForkEnv.limitOrderExecutor, true);

    address subAccount = _getSubAccount(ALICE, SUB_ACCOUNT_NO);
    deal(ALICE, 10 ether);

    uint256 _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    uint256[] memory orderIndexes = new uint256[](5);
    address[] memory accounts = new address[](5);
    uint8[] memory subAccountIds = new uint8[](5);
    for (uint i = 0; i < ARRAY_MARKET_INDEX.length; i++) {
      orderIndexes[i] = _orderIndex;
      accounts[i] = ALICE;
      subAccountIds[i] = SUB_ACCOUNT_NO;
      vm.prank(ALICE);
      ForkEnv.limitTradeHandler.createOrder{ value: 0.1 ether }({
        _subAccountId: SUB_ACCOUNT_NO,
        _marketIndex: ARRAY_MARKET_INDEX[i],
        _sizeDelta: 100 * 1e30,
        _triggerPrice: 0,
        _acceptablePrice: type(uint256).max,
        _triggerAboveThreshold: false,
        _executionFee: 0.1 ether,
        _reduceOnly: false,
        _tpToken: address(usdc_e)
      });
      _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    }

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ForkEnv.ecoPythBuilder.build(data);

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    // Execute Long Increase Order
    vm.prank(ForkEnv.limitOrderExecutor);
    ForkEnv.limitTradeHandler.executeOrders({
      _accounts: accounts,
      _subAccountIds: subAccountIds,
      _orderIndexes: orderIndexes,
      _feeReceiver: payable(BOB),
      _priceData: _priceUpdateCalldata,
      _publishTimeData: _publishTimeUpdateCalldata,
      _minPublishTime: _minPublishTime,
      _encodedVaas: keccak256("someEncodedVaas"),
      _isRevert: true
    });

    assertEq(ForkEnv.perpStorage.getNumberOfSubAccountPosition(subAccount), 5, "User must have 5 Long position");

    for (uint i = 0; i < ARRAY_MARKET_INDEX.length; i++) {
      orderIndexes[i] = _orderIndex;
      accounts[i] = ALICE;
      subAccountIds[i] = SUB_ACCOUNT_NO;
      vm.prank(ALICE);
      ForkEnv.limitTradeHandler.createOrder{ value: 0.1 ether }({
        _subAccountId: SUB_ACCOUNT_NO,
        _marketIndex: ARRAY_MARKET_INDEX[i],
        _sizeDelta: -100 * 1e30,
        _triggerPrice: 0,
        _acceptablePrice: 0,
        _triggerAboveThreshold: false,
        _executionFee: 0.1 ether,
        _reduceOnly: true,
        _tpToken: address(usdc_e)
      });
      _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    }

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    // Execute Close Long position
    vm.prank(ForkEnv.limitOrderExecutor);
    ForkEnv.limitTradeHandler.executeOrders({
      _accounts: accounts,
      _subAccountIds: subAccountIds,
      _orderIndexes: orderIndexes,
      _feeReceiver: payable(BOB),
      _priceData: _priceUpdateCalldata,
      _publishTimeData: _publishTimeUpdateCalldata,
      _minPublishTime: _minPublishTime,
      _encodedVaas: keccak256("someEncodedVaas"),
      _isRevert: true
    });

    assertEq(ForkEnv.perpStorage.getNumberOfSubAccountPosition(subAccount), 0, "User must have no position");
  }

  function _createAndExecuteMarketSellOrder() internal {
    // Whitelist limit order executor in LimitTradeHandler
    vm.prank(ForkEnv.proxyAdmin.owner());
    ForkEnv.limitTradeHandler.setWhitelistExecutor(ForkEnv.limitOrderExecutor, true);

    address subAccount = _getSubAccount(ALICE, SUB_ACCOUNT_NO);
    deal(ALICE, 10 ether);

    uint256 _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    uint256[] memory orderIndexes = new uint256[](5);
    address[] memory accounts = new address[](5);
    uint8[] memory subAccountIds = new uint8[](5);
    for (uint i = 0; i < ARRAY_MARKET_INDEX.length; i++) {
      orderIndexes[i] = _orderIndex;
      accounts[i] = ALICE;
      subAccountIds[i] = SUB_ACCOUNT_NO;
      vm.prank(ALICE);
      ForkEnv.limitTradeHandler.createOrder{ value: 0.1 ether }({
        _subAccountId: SUB_ACCOUNT_NO,
        _marketIndex: ARRAY_MARKET_INDEX[i],
        _sizeDelta: -100 * 1e30,
        _triggerPrice: 0,
        _acceptablePrice: 0,
        _triggerAboveThreshold: false,
        _executionFee: 0.1 ether,
        _reduceOnly: false,
        _tpToken: address(usdc_e)
      });
      _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    }

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ForkEnv.ecoPythBuilder.build(data);

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    // Execute Short Increase Order
    vm.prank(ForkEnv.limitOrderExecutor);
    ForkEnv.limitTradeHandler.executeOrders({
      _accounts: accounts,
      _subAccountIds: subAccountIds,
      _orderIndexes: orderIndexes,
      _feeReceiver: payable(BOB),
      _priceData: _priceUpdateCalldata,
      _publishTimeData: _publishTimeUpdateCalldata,
      _minPublishTime: _minPublishTime,
      _encodedVaas: keccak256("someEncodedVaas"),
      _isRevert: true
    });

    assertEq(ForkEnv.perpStorage.getNumberOfSubAccountPosition(subAccount), 5, "User must have 5 Long position");

    for (uint i = 0; i < ARRAY_MARKET_INDEX.length; i++) {
      orderIndexes[i] = _orderIndex;
      accounts[i] = ALICE;
      subAccountIds[i] = SUB_ACCOUNT_NO;
      vm.prank(ALICE);
      ForkEnv.limitTradeHandler.createOrder{ value: 0.1 ether }({
        _subAccountId: SUB_ACCOUNT_NO,
        _marketIndex: ARRAY_MARKET_INDEX[i],
        _sizeDelta: 100 * 1e30,
        _triggerPrice: 0,
        _acceptablePrice: type(uint256).max,
        _triggerAboveThreshold: false,
        _executionFee: 0.1 ether,
        _reduceOnly: true,
        _tpToken: address(usdc_e)
      });
      _orderIndex = ForkEnv.limitTradeHandler.limitOrdersIndex(subAccount);
    }

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    // Execute Close Short position
    vm.prank(ForkEnv.limitOrderExecutor);
    ForkEnv.limitTradeHandler.executeOrders({
      _accounts: accounts,
      _subAccountIds: subAccountIds,
      _orderIndexes: orderIndexes,
      _feeReceiver: payable(BOB),
      _priceData: _priceUpdateCalldata,
      _publishTimeData: _publishTimeUpdateCalldata,
      _minPublishTime: _minPublishTime,
      _encodedVaas: keccak256("someEncodedVaas"),
      _isRevert: true
    });

    assertEq(ForkEnv.perpStorage.getNumberOfSubAccountPosition(subAccount), 0, "User must have no position");
  }
}
