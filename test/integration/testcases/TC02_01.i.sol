// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";

import { BaseIntTest_WithActions } from "@hmx-test/integration/99_BaseIntTest_WithActions.i.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { LimitTradeHelper } from "@hmx/helpers/LimitTradeHelper.sol";

contract TC02_01 is BaseIntTest_WithActions {
  bytes[] internal updatePriceData;
  LimitTradeHelper internal limitTradeHelper;

  // TC02.1 - trader could take profit both long and short position
  // This integration test add position max size limit into test
  function testCorrectness_TC0201_TradeWithLargerPositionThanLimitScenario() external {
    limitTradeHelper = new LimitTradeHelper(address(configStorage), address(perpStorage));

    // Set limit trade of ETHUSD market to trade 300 USD and position size 50_000 usd
    limitTradeHandler.setLimitTradeHelper(address(limitTradeHelper));
    uint256[] memory marketIndexes = new uint256[](1);
    marketIndexes[0] = wethMarketIndex;
    uint256[] memory positionSizeLimits = new uint256[](1);
    positionSizeLimits[0] = 500 * 1e30;
    uint256[] memory tradeSizeLimits = new uint256[](1);
    tradeSizeLimits[0] = 300 * 1e30;
    limitTradeHelper.setLimit(marketIndexes, positionSizeLimits, tradeSizeLimits);

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
    {
      // When Bob provide 1 BTC as liquidity
      assertTokenBalanceOf(BOB, address(wbtc), 99 * 1e8, "T1: ");

      // Then Bob should pay fee for 0.3% = 0.003 BTC

      // Assert HLP Liquidity
      //    BTC = 0.997 (amount - fee)
      assertHLPLiquidity(address(wbtc), 0.997 * 1e8, "T1: ");

      // When HLP Token price is 1$
      // Then HLP Token should Mint = 0.997 btc * 20,000 USD = 19,940 USD
      //                            = 19940 / 1 = 19940 Tokens
      assertHLPTotalSupply(19_940 * 1e18, "T1: ");

      // Assert Fee distribution
      // According from T0
      // Vault's fees has nothing

      // Then after Bob provide liquidity, then Bob pay fees
      //    Add Liquidity fee
      //      BTC - 0.003 btc
      //          - distribute all  protocol fee

      // In Summarize Vault's fees
      //    BTC - protocol fee  = 0 + 0.003 = 0.00309563 btc

      assertVaultsFees({
        _token: address(wbtc),
        _fee: (0.003 * 1e8 * 9000) / 1e4,
        _devFee: 0.003 * 1e7,
        _fundingFeeReserve: 0,
        _str: "T1: "
      });

      // Finally after Bob add liquidity Vault balance should be correct
      // note: token balance is including all liquidity, dev fee and protocol fee
      //    BTC - 1
      assertVaultTokenBalance(address(wbtc), 1 * 1e8, "T1: ");
    }

    // time passed for 60 seconds
    skip(60);

    // T2: alice deposit BTC 200 USD at price 20,000
    // 200 / 20000 = 0.01 BTC
    address _aliceSubAccount0 = getSubAccount(ALICE, 0);
    depositCollateral(ALICE, 0, wbtc, 0.01 * 1e8);
    {
      // When Alice deposit Collateral for 0.01 btc
      assertTokenBalanceOf(ALICE, address(wbtc), 99.99 * 1e8, "T2: ");

      // Then Vault btc's balance should be increased by 0.01
      assertVaultTokenBalance(address(wbtc), 1.01 * 1e8, "T2: ");

      // And Alice's sub-account balances should be correct
      //    BTC - 0.01
      assertSubAccountTokenBalance(_aliceSubAccount0, address(wbtc), true, 0.01 * 1e8, "T2: ");

      // And HLP total supply and Liquidity must not be changed
      // note: data from T1
      assertHLPTotalSupply(19_940 * 1e18, "T2: ");
      assertHLPLiquidity(address(wbtc), 0.997 * 1e8, "T2: ");

      // And Alice should not pay any fee
      // note: vault's fees should be same with T1
      assertVaultsFees({
        _token: address(wbtc),
        _fee: ((0.003 * 1e8) * 9000) / 1e4,
        _devFee: 0.003 * 1e7,
        _fundingFeeReserve: 0,
        _str: "T2: "
      });
    }

    // time passed for 60 seconds
    skip(60);

    // T3: ALICE market buy weth with 301 USD (over trade size limit) at price 20,000 USD
    // should revert Max Position Size
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("LimitTradeHelper_MaxTradeSize()"));
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      int256(301 * 1e30),
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();

    // T4: ALICE market buy weth with 300 USD at price 20,000 USD
    //     Then Alice should has Long Position in WETH market
    // initialPriceFeedDatas is from
    marketBuy(ALICE, 0, wethMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    bytes32 _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    IPerpStorage.Position memory _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    // T5: ALICE market buy BTCUSD with 10_000 USD.
    //     This should work as BTC doesn't has limit
    marketBuy(ALICE, 0, wbtcMarketIndex, 10_000 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wbtcMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 10_000 * 1e30);

    // T6: ALICE try to increase her 300 USD to 501 USD
    // should revert cuz max is 500 USD
    // should revert Max Position Size
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("LimitTradeHelper_MaxPositionSize()"));
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      int256(201 * 1e30),
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();

    // Set max position size to 1 USD
    positionSizeLimits[0] = 1 * 1e30;
    limitTradeHelper.setLimit(marketIndexes, positionSizeLimits, tradeSizeLimits);

    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 300 * 1e30);

    // T7: ALICE try to decrease her 300 USD to 299 USD
    // should revert cuz max is 1 USD
    // should revert Max Position Size
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("LimitTradeHelper_MaxPositionSize()"));
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      -int256(1 * 1e30),
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();

    // T8: ALICE try to fully close her 300 USD position
    // should work
    marketSell(ALICE, 0, wethMarketIndex, 300 * 1e30, address(0), tickPrices, publishTimeDiff, block.timestamp);
    _positionId = keccak256(abi.encodePacked(ALICE, wethMarketIndex));
    _position = perpStorage.getPositionById(_positionId);
    assertEq(_position.positionSizeE30, 0);

    // T9: ALICE try to sell with 400 USD
    // should revert from max trade size
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSignature("LimitTradeHelper_MaxTradeSize()"));
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      -int256(400 * 1e30),
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      false, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();

    // TP/SL order should be creatable
    vm.startPrank(ALICE);
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      type(int256).max,
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      true, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();

    vm.startPrank(ALICE);
    limitTradeHandler.createOrder{ value: executionOrderFee }(
      0,
      wethMarketIndex,
      type(int256).min,
      0, // trigger price always be 0
      type(uint256).max,
      true, // trigger above threshold
      executionOrderFee, // 0.0001 ether
      true, // reduce only (allow flip or not)
      address(0)
    );
    vm.stopPrank();
  }
}
