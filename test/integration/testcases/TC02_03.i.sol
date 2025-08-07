// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { LimitTradeHelper } from "@hmx/helpers/LimitTradeHelper.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract TC02_03 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;
  LimitTradeHelper internal limitTradeHelper;

  // TC02.3 - trader could take profit both long and short position
  // This integration test will test the step min profit duration during increase and decrease position
  function testCorrectness_TC02_03_tradeWithMinProfitDuration() external {
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
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    skip(2 minutes);

    // T5: Time has passed for 2 minutes. Min Profit Duration of 1 minute has already expired.
    // ALICE market buy weth with 100 USD at price 1622.83582907 USD.
    // This would pass as the min profit duration has already expired.
    // But ALICE position will be under min profit duration again for 1 minute with this trade.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
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
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_400 * 1e30);

    // T8: Time has not passed.
    // ALICE market sell ETH to decrease position for 100 USD at price 1622.83582907 USD under Min Profit Duration.
    // This would fail because min profit duration is still active and the position is profitable.
    // Decrease is also not allowed during Min Profit Duration.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketSell(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_400 * 1e30);

    // T9: Time has not passed. But ETH price drop to 1528.33381234 USD. The position is not profitable.
    // ALICE market sell ETH to decrease position for 100 USD at price 1528.33381234 USD under Min Profit Duration.
    // This should be possible because the position is not profitable. Hence, the Min Profit Duration is not active.
    tickPrices[0] = 73323; // ETHUSD = 1528.33381234
    marketSell(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_300 * 1e30);

    skip(1 minutes);

    // T10: Time has passed for 2 minutes. ETH price increase to 1622.83582907 USD. Alice position is profitable.
    // Alice increase position by 89,699 USD to make the current Long ETH = 99,999 USD in size.
    // If the position is profitable, this position will be under the Min Profit Duration of 3 minutes.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketBuy(ALICE, 0, wethMarketIndex, 89699 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 99_999 * 1e30);

    skip(1 minutes);

    // T11: Time has passed for 2 minutes. ETH price drop to 1528.33381234 USD. Alice position is NOT profitable.
    // Alice can interact with their position because Min Profit Duration is not active.
    // Alice market sell ETH for 100,010 USD to flip the position in to Short ETH 11 USD in size.
    // This trade should put this position for under 1 minutes of Min Profit Duration from the 11 increase size to 11 USD Short.
    tickPrices[0] = 73323; // ETHUSD = 1528.33381234
    marketSell(ALICE, 0, wethMarketIndex, 100_010 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, -11 * 1e30);

    skip(30 seconds);

    // T12: Time has passed for 30 seconds. ETH price drop to 1513.12739333 USD. Alice position is profitable. (The position is short now.)
    // Alice cannot interact with their position because Min Profit Duration is active.
    tickPrices[0] = 73223; // ETHUSD = 1513.12739333
    marketBuy(ALICE, 0, wethMarketIndex, 11 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, -11 * 1e30);

    skip(30 seconds);

    // T12: Time has passed for 1 minute. Alice position is profitable.
    // Alice can interact with their position because Min Profit Duration of 1 minute has expired.
    // Alice fully close the position.
    tickPrices[0] = 73223; // ETHUSD = 1513.12739333
    marketBuy(ALICE, 0, wethMarketIndex, 11 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 0 * 1e30);
  }

  function testCorrectness_TC02_03_tradeWithChangedMinProfitDuration() external {
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
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    skip(2 minutes);

    // T5: Time has passed for 2 minutes. Min Profit Duration of 1 minute has already expired.
    // ALICE market buy weth with 100 USD at price 1622.83582907 USD.
    // This would pass as the min profit duration has already expired.
    // But ALICE position will be under min profit duration again for 1 minute with this trade.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 400 * 1e30);

    skip(2 minutes);

    // T6: Time has passed for 2 minutes. Min Profit Duration of 1 minute has already expired.
    // ALICE market buy weth with 110,000 USD at price 1622.83582907 USD
    // This would pass as the min profit duration has already expired.
    // But ALICE position will be under min profit duration again for 10 minutes.
    tickPrices[0] = 73923; // ETHUSD = 1622.83582907
    marketBuy(ALICE, 0, wethMarketIndex, 110_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 110_400 * 1e30);

    skip(3 minutes);

    // T7: Time has passed for 3 minutes. The position is profitable.
    // ALICE will not be able to interact with the position due to min profit duration of 3 minutes.
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 110_400 * 1e30);

    // Step Min Profit Duration
    // Change from:
    // 0 - 10k = 1 minute
    // 10k - 100k = 3 minutes
    // 100k~ = 10 minutes
    // To:
    // 0 - 10k = 1 minute
    // 10k - 100k = 3 minutes
    // 100k - 200k = 5 minutes
    // 200k~ = 10 minutes
    configStorage.removeLastStepMinProfitDuration();
    steps = new IConfigStorage.StepMinProfitDuration[](2);
    steps[0] = IConfigStorage.StepMinProfitDuration({
      fromSize: 100_000 * 1e30,
      toSize: 100_000 * 1e30, // intentionally wrong here to test revert
      minProfitDuration: 5 minutes
    });
    steps[1] = IConfigStorage.StepMinProfitDuration({
      fromSize: 100_000 * 1e30, // intentionally wrong here to test setStepMinProfitDuration
      toSize: type(uint256).max,
      minProfitDuration: 10 minutes
    });
    vm.expectRevert(abi.encodeWithSignature("IConfigStorage_BadArgs()"));
    configStorage.addStepMinProfitDuration(steps);

    steps[0] = IConfigStorage.StepMinProfitDuration({
      fromSize: 100_000 * 1e30,
      toSize: 200_000 * 1e30, // change to the correct value
      minProfitDuration: 1 minutes
    });
    configStorage.addStepMinProfitDuration(steps);

    uint256[] memory indexes = new uint256[](1);
    indexes[0] = 3;
    steps = new IConfigStorage.StepMinProfitDuration[](1);
    steps[0] = IConfigStorage.StepMinProfitDuration({
      fromSize: 200_000 * 1e30, // change to the correct value
      toSize: type(uint256).max,
      minProfitDuration: 10 minutes
    });
    configStorage.setStepMinProfitDuration(indexes, steps);

    skip(3 minutes);

    // T8: Time has passed for 5 minutes. The position is profitable.
    // ALICE will be able to interact with the position due to min profit duration has changed from 10 minutes to 5 minutes.
    marketBuy(ALICE, 0, wethMarketIndex, 100 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 110_500 * 1e30);
  }
}
