// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { LimitTradeHelper } from "@hmx/helpers/LimitTradeHelper.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { Deployer, IOrderReader } from "@hmx-test/libs/Deployer.sol";

// TC44: Test order reader with step min profit duration

contract TC44 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;
  LimitTradeHelper internal limitTradeHelper;
  IOrderReader internal orderReader;

  function testCorrectness_TC44_tradeWithMinProfitDuration() external {
    limitTradeHandler.setGuaranteeLimitPrice(false);
    orderReader = Deployer.deployOrderReader(
      address(configStorage),
      address(perpStorage),
      address(oracleMiddleWare),
      address(limitTradeHandler)
    );
    limitTradeHelper = new LimitTradeHelper(address(configStorage), address(perpStorage));

    // Set min profit duration for ETHUSD and BTCUSD as 300 seconds
    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = 0;
    uint256[] memory minProfitDurations = new uint256[](1);
    minProfitDurations[0] = 300;
    configStorage.setMinProfitDurations(marketIndexes, minProfitDurations);

    bool[] memory isEnabledStepMinProfit = new bool[](1);
    isEnabledStepMinProfit[0] = true;
    configStorage.setIsStepMinProfitEnabledByMarketIndex(marketIndexes, isEnabledStepMinProfit);

    IConfigStorage.StepMinProfitDuration[] memory steps = new IConfigStorage.StepMinProfitDuration[](3);

    // Step Min Profit Duration
    // 0 - 10k = 1 minute
    // 10k - 100k = 3 minutes
    // 100k~ = 10 minutes
    steps[0] = IConfigStorage.StepMinProfitDuration({
      fromSize: 0,
      toSize: 10_000 * 1e30,
      minProfitDuration: 1 minutes
    });
    steps[1] = IConfigStorage.StepMinProfitDuration({
      fromSize: 10_000 * 1e30,
      toSize: 100_000 * 1e30,
      minProfitDuration: 3 minutes
    });
    steps[2] = IConfigStorage.StepMinProfitDuration({
      fromSize: 100_000 * 1e30,
      toSize: type(uint256).max,
      minProfitDuration: 10 minutes
    });
    configStorage.addStepMinProfitDuration(steps);

    // prepare token for wallet
    // mint native token
    vm.deal(BOB, 1 ether);
    vm.deal(ALICE, 1 ether);
    vm.deal(FEEVER, 1 ether);

    // mint BTC
    wbtc.mint(ALICE, 100 * 1e8);
    wbtc.mint(BOB, 100 * 1e8);

    // warp to block timestamp 1000
    vm.warp(1000);

    // T1: BOB provide liquidity as WBTC 1 token
    // note: price has no changed0
    addLiquidity(BOB, wbtc, 1 * 1e8, executionOrderFee, tickPrices, publishTimeDiff, block.timestamp, true);

    // time passed for 60 seconds
    skip(60);

    // T2: alice deposit 1 BTC @$20,000
    depositCollateral(ALICE, 0, wbtc, 1 * 1e8);

    // time passed for 60 seconds
    skip(60);

    // T3: ALICE market buy weth with 300 USD at price 1574.87614416 USD
    // Then Alice should has Long Position in WETH market
    // If the position is profitable, Min Profit Duration will be 1 minute.
    tickPrices[0] = 73623; // ETHUSD = 1574.87614416
    marketBuy(ALICE, 0, wethMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    bytes32 _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    IPerpStorage.Position memory _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    // T4: ETH price increase to 1622.83582907 USD. Alice position is profitable.
    // Time has not passed. Min Profit Duration is active.
    // ALICE market buy weth with 100 USD while under Min Profit Duration
    // This would fail because min profit duration is still active and the position is profitable.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    createLimitTradeOrder(
      ALICE,
      0,
      wethMarketIndex,
      100 * 1e30,
      1622 * 1e30,
      type(uint256).max,
      true,
      executionOrderFee,
      false,
      address(usdc)
    );

    uint64[] memory orderReaderPrices = new uint64[](1);
    orderReaderPrices[0] = 1622.83582907 * 1e8;
    bool[] memory shouldInverts = new bool[](1);
    shouldInverts[0] = false;
    ILimitTradeHandler.LimitOrder[] memory executableOrders = orderReader.getExecutableOrders(
      800,
      0,
      orderReaderPrices,
      shouldInverts
    );
    assertEq(executableOrders[0].account, address(0));
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    skip(2 minutes);

    // T5: Time has passed for 2 minutes. Min Profit Duration of 1 minute has already expired.
    // ALICE market buy weth with 100 USD at price 1622.83582907 USD.
    // This would pass as the min profit duration has already expired.
    // But ALICE position will be under min profit duration again for 1 minute with this trade.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    executableOrders = orderReader.getExecutableOrders(800, 0, orderReaderPrices, shouldInverts);
    assertEq(executableOrders[0].account, ALICE);
    executeLimitTradeOrder(
      executableOrders[0].account,
      executableOrders[0].subAccountId,
      executableOrders[0].orderIndex,
      payable(FEEVER),
      tickPrices,
      publishTimeDiff,
      block.timestamp
    );
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 400 * 1e30);

    skip(2 minutes);

    // T6: Time has passed for 2 minutes. Min Profit Duration of 1 minute has already expired.
    // ALICE market buy weth with 10,000 USD at price 1622.83582907 USD
    // This would pass as the min profit duration has already expired.
    // But ALICE position will be under min profit duration again for 3 minutes.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketBuy(ALICE, 0, wethMarketIndex, 10_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_400 * 1e30);

    skip(2 minutes);

    // T7: Time has passed for 2 minutes. The position is profitable.
    // ALICE will not be able to interact with the position due to min profit duration of 3 minutes.
    createLimitTradeOrder(
      ALICE,
      0,
      wethMarketIndex,
      type(int256).min,
      1900 * 1e30,
      0,
      false,
      executionOrderFee,
      true,
      address(usdc)
    );
    executableOrders = orderReader.getExecutableOrders(800, 0, orderReaderPrices, shouldInverts);
    assertEq(executableOrders[0].account, address(0));
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_400 * 1e30);

    // T8: Time has not passed.
    // ALICE market sell ETH to decrease position for 100 USD at price 1622.83582907 USD under Min Profit Duration.
    // This would fail because min profit duration is still active and the position is profitable.
    // Decrease is also not allowed during Min Profit Duration.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    executableOrders = orderReader.getExecutableOrders(800, 0, orderReaderPrices, shouldInverts);
    assertEq(executableOrders[0].account, address(0));
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_400 * 1e30);

    // T9: Time has not passed. But ETH price drop to 1528.33381234 USD. The position is not profitable.
    // ALICE market sell ETH to decrease position for 100 USD at price 1528.33381234 USD under Min Profit Duration.
    // This should be possible because the position is not profitable. Hence, the Min Profit Duration is not active.
    tickPrices[0] = 73323; // ETHUSD = 1528.33381234
    orderReaderPrices = new uint64[](1);
    orderReaderPrices[0] = 1528.33381234 * 1e8;
    executableOrders = orderReader.getExecutableOrders(800, 0, orderReaderPrices, shouldInverts);
    assertEq(executableOrders[0].account, ALICE);
    executeLimitTradeOrder(
      executableOrders[0].account,
      executableOrders[0].subAccountId,
      executableOrders[0].orderIndex,
      payable(FEEVER),
      tickPrices,
      publishTimeDiff,
      block.timestamp
    );
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 0);
  }
}
