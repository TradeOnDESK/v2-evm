// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { MockErc20 } from "../../mocks/MockErc20.sol";
import { TradeService_Base } from "./TradeService_Base.t.sol";

import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";

import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { ITradingStaking } from "@hmx/staking/interfaces/ITradingStaking.sol";
import { IRewarder } from "@hmx/staking/interfaces/IRewarder.sol";
import { ITradeServiceHook } from "@hmx/services/interfaces/ITradeServiceHook.sol";
import { ITraderLoyaltyCredit } from "@hmx/tokens/interfaces/ITraderLoyaltyCredit.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { ITLCStaking } from "@hmx/staking/interfaces/ITLCStaking.sol";
import { IEpochRewarder } from "@hmx/staking/interfaces/IEpochRewarder.sol";
import { console } from "forge-std/console.sol";
import { ITLCHook } from "@hmx/services/interfaces/ITLCHook.sol";

contract TradeService_Hooks is TradeService_Base {
  MockErc20 internal rewardToken;
  ITraderLoyaltyCredit internal tlc;
  ITradingStaking internal tradingStaking;
  ITradeServiceHook internal tradingStakingHook;
  ITradeServiceHook internal tlcHook;
  IRewarder internal ethMarketRewarder;
  ITLCStaking internal tlcStaking;
  IEpochRewarder internal tlcRewarder;

  function setUp() public virtual override {
    super.setUp();

    rewardToken = new MockErc20("Reward Token", "RWD", 18);
    tradingStaking = Deployer.deployTradingStaking(address(proxyAdmin));
    tradingStakingHook = Deployer.deployTradingStakingHook(
      address(proxyAdmin),
      address(tradingStaking),
      address(tradeService)
    );
    tlc = Deployer.deployTLCToken(address(proxyAdmin));
    tlcStaking = Deployer.deployTLCStaking(address(proxyAdmin), address(tlc));
    tlcHook = Deployer.deployTLCHook(address(proxyAdmin), address(tradeService), address(tlc), address(tlcStaking));

    address[] memory _hooks = new address[](2);
    _hooks[0] = address(tradingStakingHook);
    _hooks[1] = address(tlcHook);
    configStorage.setTradeServiceHooks(_hooks);

    ethMarketRewarder = Deployer.deployFeedableRewarder(
      address(proxyAdmin),
      "Gov",
      address(rewardToken),
      address(tradingStaking)
    );
    tlcRewarder = Deployer.deployEpochFeedableRewarder(
      address(proxyAdmin),
      "TLC",
      address(rewardToken),
      address(tlcStaking)
    );

    uint256[] memory _marketIndices = new uint256[](1);
    _marketIndices[0] = ethMarketIndex;
    tradingStaking.addRewarder(address(ethMarketRewarder), _marketIndices);
    tradingStaking.setWhitelistedCaller(address(tradingStakingHook));

    tlcStaking.addRewarder(address(tlcRewarder));
    tlcStaking.setWhitelistedCaller(address(tlcHook));

    rewardToken.mint(address(this), 100 ether);
    rewardToken.approve(address(ethMarketRewarder), 100 ether);
    ethMarketRewarder.feed(100 ether, 365 days);

    tlc.setMinter(address(tlcHook), true);

    address[] memory whitelistedCallers = new address[](1);
    whitelistedCallers[0] = address(tradeService);
    bool[] memory isWhitelisteds = new bool[](1);
    isWhitelisteds[0] = true;

    tlcHook.setWhitelistedCallers(whitelistedCallers, isWhitelisteds);
    tradingStakingHook.setWhitelistedCallers(whitelistedCallers, isWhitelisteds);
  }

  function testRevert_TradingStaking_UnknownMarketIndex() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    uint256 price = 1_600 * 1e30;
    mockOracle.setPrice(price);

    // input
    int256 sizeDelta = 1_000_000 * 1e30;

    tradeService.increasePosition(ALICE, 0, btcMarketIndex, sizeDelta, 0);
  }

  function testRevert_TradingStaking_Forbidden() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    uint256 price = 1_600 * 1e30;
    mockOracle.setPrice(price);

    // input
    int256 sizeDelta = 1_000_000 * 1e30;

    tradingStaking.setWhitelistedCaller(address(ALICE));
    vm.expectRevert(abi.encodeWithSignature("TradingStaking_Forbidden()"));
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, sizeDelta, 0);
  }

  function testRevert_TradingStakingHook_Forbidden() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    uint256 price = 1_600 * 1e30;
    mockOracle.setPrice(price);

    // input
    int256 sizeDelta = 1_000_000 * 1e30;

    vm.expectRevert(abi.encodeWithSignature("TradingStakingHook_Forbidden()"));
    tradingStakingHook.onIncreasePosition(ALICE, 0, ethMarketIndex, uint256(sizeDelta), "");
  }

  function testCorrectness_hookOnIncreaseAndDecreasePosition() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    uint256 price = 1_600 * 1e30;
    mockOracle.setPrice(price);

    // input
    int256 sizeDelta = 1_000_000 * 1e30;

    // Alice increase a position with $1,000,000
    // TLC should be minted for 1,000,000 TLC and staked for Alice
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, sizeDelta, 0);
    // assert that Trading Staking balance increased
    assertEq(tradingStaking.getUserTokenAmount(ethMarketIndex, ALICE), uint256(sizeDelta) / 1e12);
    // assert that TLC balance increased
    assertEq(tlcStaking.getUserTokenAmount(tlcRewarder.getCurrentEpochTimestamp(), ALICE), 1_000_000 * 1e18);

    // Decreaseing position should not mint new TLC
    tradeService.decreasePosition(ALICE, 0, ethMarketIndex, 300 * 1e30, address(wbtc), price);
    // assert that Trading Staking balance decreased
    assertEq(tradingStaking.getUserTokenAmount(ethMarketIndex, ALICE), uint256(sizeDelta - 300 * 1e30) / 1e12);
    // assert that TLC balance remain the same
    assertEq(tlcStaking.getUserTokenAmount(tlcRewarder.getCurrentEpochTimestamp(), ALICE), 1_000_000 * 1e18);
  }

  function testCorrectness_pendingRewardAndClaim() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    uint256 price = 1_600 * 1e30;
    mockOracle.setPrice(price);

    // Alice open a position with $1,000,000 in size
    // Bob open a position with $400,000 in size
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30, 0);
    tradeService.increasePosition(BOB, 0, ethMarketIndex, 400_000 * 1e30, 0);

    // Pending reward for both trading staking and TLC should be zero.
    // because time has not passed.
    assertEq(ethMarketRewarder.pendingReward(ALICE), 0 ether);
    assertEq(ethMarketRewarder.pendingReward(BOB), 0 ether);
    assertEq(tlcRewarder.pendingReward(0, 1, ALICE), 0 ether);
    assertEq(tlcRewarder.pendingReward(0, 1, BOB), 0 ether);

    vm.warp(block.timestamp + 3 days);
    // timePast = 60 * 60 * 24 * 3 = 259200
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Alice's share = 1,000,000 * 1e30
    // totalShare = 1,400,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare)
    //               = (259200 / 31536000) * 100 * 1e18 * ((1000000 * 1e30)/(1400000 * 1e30))
    //               = 0.587084148727899428
    assertEq(ethMarketRewarder.pendingReward(ALICE), 0.587084148727899428 ether);
    // timePast = 60 * 60 * 24 * 3 = 259200
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Bob's share = 400,000 * 1e30
    // totalShare = 1,400,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare)
    //               = (259200 / 31536000) * 100 * 1e18 * ((400000 * 1e30)/(1400000 * 1e30))
    //               = 0.234833659491159771
    assertEq(ethMarketRewarder.pendingReward(BOB), 0.234833659491159771 ether);
    // TLC pending reward will remain at zero, because a week (epoch length) has not passed.
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, ALICE), 0 ether);
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, BOB), 0 ether);

    // Forward to the end of the week
    vm.warp(block.timestamp + 4 days);
    // Feed TLC reward at the end of the epoch
    rewardToken.mint(address(this), 300 ether);
    rewardToken.approve(address(tlcRewarder), 300 ether);
    tlcRewarder.feed(0, 300 ether);
    // timePast = 60 * 60 * 24 * 7 = 604800
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Alice's share = 1,000,000 * 1e30
    // totalShare = 1,400,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare)
    //               = (604800 / 31536000) * 100 * 1e18 * ((1000000 * 1e30)/(1400000 * 1e30))
    //               = 1.369863013698432000
    assertEq(ethMarketRewarder.pendingReward(ALICE), 1.369863013698432000 ether);
    // timePast = 60 * 60 * 24 * 7 = 604800
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Bob's share = 400,000 * 1e30
    // totalShare = 1,400,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare)
    //               = (604800 / 31536000) * 100 * 1e18 * ((400000 * 1e30)/(1400000 * 1e30))
    //               = 0.547945205479372800
    assertEq(tradingStaking.calculateTotalShare(address(ethMarketRewarder)), 1_400_000 ether);
    assertEq(ethMarketRewarder.pendingReward(BOB), 0.547945205479372800 ether);
    // Alice's TLC pending reward
    // = Alice Share / Total Share * Total Reward
    // = 1,000,000 * 300 / 1,400,000 = 214.285714285714285714
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, ALICE), 214.285714285714285714 ether);
    // Bob's TLC pending reward
    // = Alice Share / Total Share * Total Reward
    // = 400,000 * 300 / 1,400,000 = 85.714285714285714285
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, BOB), 85.714285714285714285 ether);

    // Start of a new epoch (new week)
    // Alice trade for $700,000, but Bob did nothing
    // Decrease position must not affect TLC balance
    assertEq(tradingStaking.calculateTotalShare(address(ethMarketRewarder)), 1_400_000 ether);
    tradeService.decreasePosition(ALICE, 0, ethMarketIndex, 700_000 * 1e30, address(0), 0);
    // Then increase again for $250,000
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 250_000 * 1e30, 0);

    // Forward to the next week
    vm.warp(block.timestamp + 8 days);
    // Feed 144 TLC reward for this week
    rewardToken.mint(address(this), 144 ether);
    rewardToken.approve(address(tlcRewarder), 144 ether);
    tlcRewarder.feed(1 weeks, 144 ether);
    // timePast = 60 * 60 * 24 * 8 = 691200
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Alice's share = 550,000 * 1e30
    // totalShare = 950,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare) + previousReward
    //               = (691200 / 31536000) * 100 * 1e18 * ((550000 * 1e30)/(950000 * 1e30)) + 1369863013698000000
    //               = 2.638788752703295326
    assertEq(tradingStaking.getUserTokenAmount(ethMarketIndex, ALICE), 550_000 ether);
    assertEq(tradingStaking.calculateTotalShare(address(ethMarketRewarder)), 950_000 ether);
    assertEq(ethMarketRewarder.pendingReward(ALICE), 2.638788752703295326 ether, "alice reward 4");
    // timePast = 60 * 60 * 24 * 7 = 691200
    // feedDuration = 60 * 60 * 24 * 365 = 31536000
    // Bob's share = 400,000 * 1e30
    // totalShare = 700,000 * 1e30
    // totalReward = 100 * 1e18
    // pendingReward = (timePast / feedDuration) * totalReward * (aliceShare / totalShare)
    //               = (691200 / 31536000) * 100 * 1e18 * ((400000 * 1e30)/(950000 * 1e30)) + 547945205479200000
    //               = 1.470800288392000673
    assertEq(ethMarketRewarder.pendingReward(BOB), 1.470800288392000673 ether);
    // Alice's TLC pending reward
    // = Alice Share / Total Share * Total Reward
    // = 250,000 * 144 / 250,000 = 144
    // Include last week reward = 214.28571428571428 + 144 = 358.285714285714285714
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, ALICE), 358.285714285714285714 ether);
    // Bob's TLC pending reward should remain the same as Bob did not make any new trade this week.
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, BOB), 85.714285714285714285 ether);

    // Claim trading staking reward
    address[] memory rewarders = new address[](1);
    rewarders[0] = address(ethMarketRewarder);

    // Alice should receive 2.638788752703295326 reward token
    uint256 rewardBalanceBeforeAlice = rewardToken.balanceOf(ALICE);
    vm.prank(ALICE);
    tradingStaking.harvest(rewarders);
    uint256 rewardBalanceAfterAlice = rewardToken.balanceOf(ALICE);
    assertEq(rewardBalanceAfterAlice - rewardBalanceBeforeAlice, 2.638788752703295326 ether);

    // Bob should receive 1.470800288392000673 reward token
    uint256 rewardBalanceBeforeBob = rewardToken.balanceOf(BOB);
    vm.prank(BOB);
    tradingStaking.harvest(rewarders);
    uint256 rewardBalanceAfterBob = rewardToken.balanceOf(BOB);
    assertEq(rewardBalanceAfterBob - rewardBalanceBeforeBob, 1.470800288392000673 ether);

    // Claim TLC Reward
    rewarders[0] = address(tlcRewarder);
    // Alice should receive 358.285714285714285714 reward token
    assertEq(tlcStaking.getUserTokenAmount(0, ALICE), 1_000_000 ether);
    assertEq(tlcStaking.getUserTokenAmount(1 weeks, ALICE), 250_000 ether);
    rewardBalanceBeforeAlice = rewardToken.balanceOf(ALICE);
    vm.prank(ALICE);
    tlcStaking.harvest(0, type(uint256).max, rewarders);
    rewardBalanceAfterAlice = rewardToken.balanceOf(ALICE);
    assertEq(rewardBalanceAfterAlice - rewardBalanceBeforeAlice, 358.285714285714285714 ether);
    // assert that after harvest, TLC balance should remain the same; no burning of TLC
    assertEq(tlcStaking.getUserTokenAmount(0, ALICE), 1_000_000 ether);
    assertEq(tlcStaking.getUserTokenAmount(1 weeks, ALICE), 250_000 ether);

    // Bob should receive 85.714285714285714285 reward token
    assertEq(tlcStaking.getUserTokenAmount(0, BOB), 400_000 ether);
    assertEq(tlcStaking.getUserTokenAmount(1 weeks, BOB), 0 ether);
    rewardBalanceBeforeBob = rewardToken.balanceOf(BOB);
    vm.prank(BOB);
    tlcStaking.harvest(0, type(uint256).max, rewarders);
    rewardBalanceAfterBob = rewardToken.balanceOf(BOB);
    assertEq(rewardBalanceAfterBob - rewardBalanceBeforeBob, 85.714285714285714285 ether);
    // assert that after harvest, TLC balance should remain the same; no burning of TLC
    assertEq(tlcStaking.getUserTokenAmount(0, BOB), 400_000 ether);
    assertEq(tlcStaking.getUserTokenAmount(1 weeks, BOB), 0 ether);

    // Pending reward of ALICE and BOB should be zero after claimed
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, ALICE), 0);
    assertEq(tlcRewarder.pendingReward(0, type(uint256).max, BOB), 0);
  }

  function testCorrectness_mintWeightedTLC() external {
    // setup
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setHLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    ITLCHook _tlcHook = ITLCHook(address(tlcHook));
    assertEq(_tlcHook.marketWeights(ethMarketIndex), 0);

    // Alice open pos
    uint256 tlcBefore = tlcStaking.getUserTokenAmount(0, ALICE);
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 25 * 1e30, 0);
    uint256 tlcAfter = tlcStaking.getUserTokenAmount(0, ALICE);
    uint256 receivedTLCOnDefaultWeight = tlcAfter - tlcBefore;

    // SET WEIGHT
    uint256 newWeight = 18_640;
    _tlcHook.setMarketWeight(ethMarketIndex, newWeight);
    assertEq(_tlcHook.marketWeights(ethMarketIndex), newWeight);

    uint256 _tlcBefore = tlcStaking.getUserTokenAmount(0, ALICE);
    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 25 * 1e30, 0);
    uint256 _tlcAfter = tlcStaking.getUserTokenAmount(0, ALICE);
    uint256 receivedTLCOnNewWeight = _tlcAfter - _tlcBefore;
    assertEq(receivedTLCOnNewWeight / receivedTLCOnDefaultWeight, newWeight / 10_000); // weight.div(BPS)
  }
}
