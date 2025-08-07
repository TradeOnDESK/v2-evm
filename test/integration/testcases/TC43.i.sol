// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { IIntentHandler } from "@hmx/handlers/interfaces/IIntentHandler.sol";
import { IntentHandler } from "@hmx/handlers/IntentHandler.sol";

contract TC43 is BaseIntTest_WithActions {
  event LogBadSignature(bytes32 indexed key);
  event LogIntentReplay(bytes32 indexed key);

  function setUp() public {
    gasService.setWaviedExecutionFeeMinTradeSize(type(uint256).max);

    configStorage.setConfigExecutor(address(this), true);
  }

  function testCorrectness_TC43_intentHandler_executeMarketOrderSuccess() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    usdc.mint(BOB, 100_000 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    {
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC43: after deposit collateral");
    }

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](2);
    executeIntentInputs.cmds = new bytes32[](2);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    IIntentHandler.TradeOrder memory tradeOrder2 = IIntentHandler.TradeOrder({
      marketIndex: wbtcMarketIndex, // marketIndex
      sizeDelta: -100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 18000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (accountAndSubAccountId, cmd) = intentBuilder.buildTradeOrder(tradeOrder2);
    executeIntentInputs.accountAndSubAccountIds[1] = accountAndSubAccountId;
    executeIntentInputs.cmds[1] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](2);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    (v, r, s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder2));
    executeIntentInputs.signatures[1] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("IntentHandler_Unauthorized()"));
    intentHandler.execute(executeIntentInputs);
    vm.stopPrank();

    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 2);

    // Initial collateral = 100,000 usdc
    // 1st trade's trading fee = 100000 - 100 = 99900
    // 1st trade's execution fee = 99900 - 0.1 = 99899.9
    // 2nd trade's trading fee = 99899.9 - 100 = 99799.9
    // 2nd trade's execution fee = 99799.9 - 0.1 = 99799.8
    assertEq(vaultStorage.traderBalances(BOB, address(usdc)), 99799.8 * 1e6);

    vm.warp(block.timestamp + 5 minutes);

    // Test order stale
    // Bob will create an order, but the order took too long to be executed
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    IIntentHandler.TradeOrder memory tradeOrder3 = IIntentHandler.TradeOrder({
      marketIndex: appleMarketIndex, // marketIndex
      sizeDelta: 10_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (accountAndSubAccountId, cmd) = intentBuilder.buildTradeOrder(tradeOrder3);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    (v, r, s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder3));
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    vm.warp(block.timestamp + 10 minutes);

    intentHandler.execute(executeIntentInputs);

    // New position should not be opened, as the order should be stale
    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 2);
  }

  function testCorrectness_TC43_intentHandler_executeMarketOrderSuccess_withDelegation() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    usdc.mint(ALICE, 100_000 * 1e6);
    depositCollateral(ALICE, 0, ERC20(address(usdc)), 100_000 * 1e6);
    {
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC43: after deposit collateral");
    }

    // Long ETH
    vm.deal(ALICE, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(ALICE, 0)), 0);
      assertEq(ALICE.balance, 1 ether);
    }

    // Alice will open two positions on ETH and BTC markets but delegate it to Bob to sign the intents
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](2);
    executeIntentInputs.cmds = new bytes32[](2);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: ALICE,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    IIntentHandler.TradeOrder memory tradeOrder2 = IIntentHandler.TradeOrder({
      marketIndex: wbtcMarketIndex, // marketIndex
      sizeDelta: -100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 18000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: ALICE,
      subAccountId: 0
    });
    (accountAndSubAccountId, cmd) = intentBuilder.buildTradeOrder(tradeOrder2);
    executeIntentInputs.accountAndSubAccountIds[1] = accountAndSubAccountId;
    executeIntentInputs.cmds[1] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](2);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    (v, r, s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder2));
    executeIntentInputs.signatures[1] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    // Alice has not set delegate as Bob, so expect bad signature here
    vm.expectEmit(true, false, false, false, address(intentHandler));
    emit LogBadSignature(
      keccak256(abi.encode(executeIntentInputs.accountAndSubAccountIds[0], executeIntentInputs.cmds[0]))
    );
    emit LogBadSignature(
      keccak256(abi.encode(executeIntentInputs.accountAndSubAccountIds[1], executeIntentInputs.cmds[1]))
    );
    intentHandler.execute(executeIntentInputs);

    // Now, Alice set delegate as Bob, order should be able to be executed
    vm.startPrank(ALICE);
    intentHandler.setDelegate(BOB);
    vm.stopPrank();
    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(ALICE), 2);

    // Initial collateral = 100,000 usdc
    // 1st trade's trading fee = 100000 - 100 = 99900
    // 1st trade's execution fee = 99900 - 0.1 = 99899.9
    // 2nd trade's trading fee = 99899.9 - 100 = 99799.9
    // 2nd trade's execution fee = 99799.9 - 0.1 = 99799.8
    assertEq(vaultStorage.traderBalances(ALICE, address(usdc)), 99799.8 * 1e6);
  }

  function testRevert_TC43_intentHandler_replayIntent() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    usdc.mint(BOB, 100_000 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    {
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC43: after deposit collateral");
    }

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](2);
    executeIntentInputs.cmds = new bytes32[](2);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    IIntentHandler.TradeOrder memory tradeOrder2 = IIntentHandler.TradeOrder({
      marketIndex: wbtcMarketIndex, // marketIndex
      sizeDelta: -100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 18000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (accountAndSubAccountId, cmd) = intentBuilder.buildTradeOrder(tradeOrder2);
    executeIntentInputs.accountAndSubAccountIds[1] = accountAndSubAccountId;
    executeIntentInputs.cmds[1] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](2);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    (v, r, s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder2));
    executeIntentInputs.signatures[1] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("IntentHandler_Unauthorized()"));
    intentHandler.execute(executeIntentInputs);
    vm.stopPrank();

    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 2);

    // Initial collateral = 100,000 usdc
    // 1st trade's trading fee = 100000 - 100 = 99900
    // 1st trade's execution fee = 99900 - 0.1 = 99899.9
    // 2nd trade's trading fee = 99899.9 - 100 = 99799.9
    // 2nd trade's execution fee = 99799.9 - 0.1 = 99799.8
    assertEq(vaultStorage.traderBalances(BOB, address(usdc)), 99799.8 * 1e6);

    // Test intent replay, should revert
    vm.expectEmit(true, false, false, false, address(intentHandler));
    emit LogIntentReplay(
      keccak256(abi.encode(executeIntentInputs.accountAndSubAccountIds[0], executeIntentInputs.cmds[0]))
    );
    intentHandler.execute(executeIntentInputs);
  }

  function testCorrectness_TC43_intentHandler_executeMarketOrderFail() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    usdc.mint(BOB, 100_000 * 1e6);
    depositCollateral(BOB, 0, ERC20(address(usdc)), 100_000 * 1e6);
    {
      assertVaultTokenBalance(address(usdc), 100_000 * 1e6, "TC43: after deposit collateral");
    }

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](2);
    executeIntentInputs.cmds = new bytes32[](2);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 0 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    IIntentHandler.TradeOrder memory tradeOrder2 = IIntentHandler.TradeOrder({
      marketIndex: wbtcMarketIndex, // marketIndex
      sizeDelta: -100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 18000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (accountAndSubAccountId, cmd) = intentBuilder.buildTradeOrder(tradeOrder2);
    executeIntentInputs.accountAndSubAccountIds[1] = accountAndSubAccountId;
    executeIntentInputs.cmds[1] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](2);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    (v, r, s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder2));
    executeIntentInputs.signatures[1] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 1);

    // Initial collateral = 100,000 usdc
    // 1st trade's trading fee = 100000 - 100 = 99900
    // 1st trade's execution fee = 99900 - 0.1 = 99899.9
    // 2nd trade's execution fee = 99899.9 - 0.1 = 99899.8
    assertEq(vaultStorage.traderBalances(BOB, address(usdc)), 99899.8 * 1e6);
  }

  function testCorrectness_TC43_intentHandler_payExecutionFeeWithMultipleToken() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    dai.mint(BOB, 0.1 * 1e18);
    depositCollateral(BOB, 0, ERC20(address(dai)), 0.1 * 1e18);
    wbtc.mint(BOB, 100 * 1e8);
    depositCollateral(BOB, 0, ERC20(address(wbtc)), 1 * 1e8);
    {
      assertVaultTokenBalance(address(dai), 0.1 * 1e18, "TC43: after deposit collateral");
      assertVaultTokenBalance(address(wbtc), 101 * 1e8, "TC43: after deposit collateral");
    }

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](1);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 1);

    // Initial collateral = 0.1 DAI
    //                    = 1 WBTC (WBTC @ $19,998.3457779) = $19,998.3457779
    // 1st trade's execution fee = 0.1 DAI - 0.1 = 0 DAI
    // 1st trade's trading fee = 19998.3457779 - 100 = 19898.3457779 => 19898.3457779/19,998.3457779 = 0.99499959 WBTC

    assertEq(vaultStorage.traderBalances(BOB, address(dai)), 0 * 1e18);
    assertEq(vaultStorage.traderBalances(BOB, address(wbtc)), 0.99499959 * 1e8);
  }

  function testRevert_TC43_intentHandler_badSignature() external {
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);
    uint256 anotherPivateKey = uint256(keccak256(bytes("2")));

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    dai.mint(BOB, 0.1 * 1e18);
    depositCollateral(BOB, 0, ERC20(address(dai)), 0.1 * 1e18);
    wbtc.mint(BOB, 1 * 1e8);
    depositCollateral(BOB, 0, ERC20(address(wbtc)), 1 * 1e8);
    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(anotherPivateKey, intentHandler.getDigest(tradeOrder1)); // sign the message with other private key that is not BOB
    executeIntentInputs.signatures = new bytes[](1);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    vm.expectEmit(true, false, false, false, address(intentHandler));
    emit LogBadSignature(
      keccak256(abi.encode(executeIntentInputs.accountAndSubAccountIds[0], executeIntentInputs.cmds[0]))
    );
    intentHandler.execute(executeIntentInputs);

    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 0);

    // No execution fee should be collected
    assertEq(vaultStorage.traderBalances(BOB, address(dai)), 0.1 * 1e18);
    assertEq(vaultStorage.traderBalances(BOB, address(wbtc)), 1 * 1e8);
  }

  // This test function is depreceated. Because we have moved the execution fee collection to be after everything
  // in order to calculate the actual gas usage of the transaction. Therefore, it cannot trigger a trade to fail due to insufficient collateral.
  // function testCorrectness_TC43_intentHandler_notEnoughCollateralForExecutionFee() external {
  //   uint256 privateKey = uint256(keccak256(bytes("1")));
  //   BOB = vm.addr(privateKey);

  //   // T0: Initialized state
  //   // ALICE as liquidity provider
  //   // BOB as trader
  //   IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

  // uint256[] memory marketIndexes = new uint256[](1);
  // marketIndexes[0] = wbtcMarketIndex;
  // uint256[] memory maxLongPositionSizes = new uint256[](1);
  // maxLongPositionSizes[0] = 20_000_000 * 1e30;
  // uint256[] memory maxShortPositionSizes = new uint256[](1);
  // maxShortPositionSizes[0] = 20_000_000 * 1e30;
  // configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

  //   // T1: Add liquidity in pool USDC 100_000 , WBTC 100
  //   vm.deal(ALICE, executionOrderFee);
  //   wbtc.mint(ALICE, 100 * 1e8);

  //   addLiquidity(
  //     ALICE,
  //     ERC20(address(wbtc)),
  //     100 * 1e8,
  //     executionOrderFee,
  //     tickPrices,
  //     publishTimeDiff,
  //     block.timestamp,
  //     true
  //   );

  //   // T2: Create market order
  //   {
  //     assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
  //   }
  //   dai.mint(BOB, 1205 * 1e18);
  //   depositCollateral(BOB, 0, ERC20(address(dai)), 1205 * 1e18);

  //   // Long ETH
  //   vm.deal(BOB, 1 ether);

  //   {
  //     // before create order, must be empty
  //     assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
  //     assertEq(BOB.balance, 1 ether);
  //   }

  //   // Bob will open two positions on ETH and BTC markets
  //   IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
  //   executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
  //   executeIntentInputs.cmds = new bytes32[](1);

  //   IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
  //     marketIndex: wethMarketIndex, // marketIndex
  //     sizeDelta: 100_000 * 1e30, // sizeDelta
  //     triggerPrice: 0, // triggerPrice
  //     acceptablePrice: 4000 * 1e30, // acceptablePrice
  //     triggerAboveThreshold: true, // triggerAboveThreshold
  //     reduceOnly: false, // reduceOnly
  //     tpToken: address(usdc), // tpToken
  //     createdTimestamp: block.timestamp, // createdTimestamp
  //     expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
  //     account: BOB,
  //     subAccountId: 0
  //   });
  //   (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
  //   executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
  //   executeIntentInputs.cmds[0] = cmd;

  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
  //   executeIntentInputs.signatures = new bytes[](1);
  //   executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

  //   executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
  //   executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
  //   executeIntentInputs.minPublishTime = block.timestamp;
  //   executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

  //   intentHandler.execute(executeIntentInputs);

  //   // The order failed to executed here because collateral is short by 0.1 usd for the exection fee.
  //   // Therefore, no position will be opened.
  //   assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 0);

  //   // Initial collateral = 1205 DAI
  //   // 1st trade's execution fee = 1205 - 0.1 = 1204.9 DAI
  //   // execution fee is deducted even if the order failed
  //   assertEq(vaultStorage.traderBalances(BOB, address(dai)), 1204.9 * 1e18);
  // }

  function testCorrectness_TC43_intentHandler_subsidizeExecutionFee() external {
    gasService.setWaviedExecutionFeeMinTradeSize(0);
    gasService.setGasPremiumBps(500); // 5% premium

    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    dai.mint(BOB, 1205 * 1e18);
    depositCollateral(BOB, 0, ERC20(address(dai)), 1205 * 1e18);

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 100_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](1);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    intentHandler.execute(executeIntentInputs);

    // The order will execute successfully.
    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 1);

    // Initial collateral = 1205 DAI
    // Trading Fee = 100 USD
    // = 1205 - 100 = 1105 DAI
    assertEq(vaultStorage.traderBalances(BOB, address(dai)), 1105 * 1e18);

    // Test adjust subsidized execution fee
    configStorage.setServiceExecutor(address(gasService), address(this), true);
    assertEq(gasService.subsidizedExecutionFeeValue(), 0.1e30);
    gasService.adjustSubsidizedExecutionFeeValue(-int256(gasService.subsidizedExecutionFeeValue()));
    assertEq(gasService.subsidizedExecutionFeeValue(), 0);
  }

  function testCorrectness_TC43_intentHandler_subsidizeExecutionFee_belowWaiveSize() external {
    gasService.setWaviedExecutionFeeMinTradeSize(200_000 * 1e30);
    uint256 privateKey = uint256(keccak256(bytes("1")));
    BOB = vm.addr(privateKey);

    // T0: Initialized state
    // ALICE as liquidity provider
    // BOB as trader
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(wbtcMarketIndex);

    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wbtcMarketIndex;
    uint256[] memory maxLongPositionSizes = new uint256[](1);
    maxLongPositionSizes[0] = 20_000_000 * 1e30;
    uint256[] memory maxShortPositionSizes = new uint256[](1);
    maxShortPositionSizes[0] = 20_000_000 * 1e30;
    configStorage.setMarketMaxOI(marketIndexes, maxLongPositionSizes, maxShortPositionSizes);

    // T1: Add liquidity in pool USDC 100_000 , WBTC 100
    vm.deal(ALICE, executionOrderFee);
    wbtc.mint(ALICE, 100 * 1e8);

    addLiquidity(
      ALICE,
      ERC20(address(wbtc)),
      100 * 1e8,
      executionOrderFee,
      tickPrices,
      publishTimeDiff,
      block.timestamp,
      true
    );

    // T2: Create market order
    {
      assertVaultTokenBalance(address(usdc), 0, "TC43: before deposit collateral");
    }
    dai.mint(BOB, 1205 * 1e18);
    depositCollateral(BOB, 0, ERC20(address(dai)), 1205 * 1e18);

    // Long ETH
    vm.deal(BOB, 1 ether);

    {
      // before create order, must be empty
      assertEq(limitTradeHandler.limitOrdersIndex(getSubAccount(BOB, 0)), 0);
      assertEq(BOB.balance, 1 ether);
    }

    // Bob will open two positions on ETH and BTC markets
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    IIntentHandler.TradeOrder memory tradeOrder1 = IIntentHandler.TradeOrder({
      marketIndex: wethMarketIndex, // marketIndex
      sizeDelta: 10_000 * 1e30, // sizeDelta
      triggerPrice: 0, // triggerPrice
      acceptablePrice: 4000 * 1e30, // acceptablePrice
      triggerAboveThreshold: true, // triggerAboveThreshold
      reduceOnly: false, // reduceOnly
      tpToken: address(usdc), // tpToken
      createdTimestamp: block.timestamp, // createdTimestamp
      expiryTimestamp: block.timestamp + 5 minutes, // expiryTimestamp
      account: BOB,
      subAccountId: 0
    });
    (bytes32 accountAndSubAccountId, bytes32 cmd) = intentBuilder.buildTradeOrder(tradeOrder1);
    executeIntentInputs.accountAndSubAccountIds[0] = accountAndSubAccountId;
    executeIntentInputs.cmds[0] = cmd;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHandler.getDigest(tradeOrder1));
    executeIntentInputs.signatures = new bytes[](1);
    executeIntentInputs.signatures[0] = abi.encodePacked(r, s, v);

    executeIntentInputs.priceData = pyth.buildPriceUpdateData(tickPrices);
    executeIntentInputs.publishTimeData = pyth.buildPublishTimeUpdateData(publishTimeDiff);
    executeIntentInputs.minPublishTime = block.timestamp;
    executeIntentInputs.encodedVaas = keccak256("someEncodedVaas");

    intentHandler.execute(executeIntentInputs);

    // The order will execute successfully.
    assertEq(perpStorage.getNumberOfSubAccountPosition(BOB), 1);

    // Initial collateral = 1205 DAI
    // Trading Fee = 10 USD
    // Execution Fee = 0.1 USD
    // = 1205 - 10 - 0.1 = 1194.9 DAI
    assertEq(vaultStorage.traderBalances(BOB, address(dai)), 1194.9 * 1e18);
  }
}
