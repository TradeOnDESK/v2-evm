// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { VaultStorage_Base } from "./VaultStorage_Base.t.sol";
import { MockErc20 } from "@hmx-test/mocks/MockErc20.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";

contract VaultStorage_FeedAndRewardDebtTest is VaultStorage_Base {
  MockErc20 testToken;
  address testTokenAddress;
  uint256 constant FEED_AMOUNT = 1000 * 1e18;
  uint256 constant DURATION = 86400; // 1 day in seconds

  function setUp() public override {
    super.setUp();

    // Deploy a test token
    testToken = new MockErc20("Test Token", "TEST", 18);
    testTokenAddress = address(testToken);

    // Set up the vault storage as a service executor
    vaultStorage.setServiceExecutors(address(this), true);

    // Mint tokens to this contract for testing
    testToken.mint(address(this), FEED_AMOUNT * 10);
  }

  function testCorrectness_WhenFeedWithValidParameters() external {
    uint256 initialBalance = testToken.balanceOf(address(this));
    uint256 initialHlpLiquidity = vaultStorage.hlpLiquidity(testTokenAddress);
    uint256 initialRewardDebt = vaultStorage.rewardDebt(testTokenAddress);

    // Approve tokens for vault storage
    testToken.approve(address(vaultStorage), FEED_AMOUNT);

    // Call feed function
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);

    // Verify HLP liquidity increased
    assertEq(
      vaultStorage.hlpLiquidity(testTokenAddress),
      initialHlpLiquidity + FEED_AMOUNT,
      "HLP liquidity should increase by feed amount"
    );

    // Verify reward debt is set ly
    assertEq(vaultStorage.rewardDebt(testTokenAddress), FEED_AMOUNT, "Reward debt should equal amount initially");

    // Verify reward debt start time
    assertEq(
      vaultStorage.rewardDebtStartAt(testTokenAddress),
      block.timestamp,
      "Reward debt start time should be current timestamp"
    );

    // Verify reward debt expired time
    assertEq(
      vaultStorage.rewardDebtExpiredAt(testTokenAddress),
      block.timestamp + DURATION,
      "Reward debt expired time should be current timestamp + duration"
    );

    // Verify tokens were transferred
    assertEq(testToken.balanceOf(address(this)), initialBalance - FEED_AMOUNT, "Tokens should be transferred to vault");
  }

  function testCorrectness_WhenFeedWithExpiredAt() external {
    uint256 expiredAt = block.timestamp + DURATION;

    // Approve tokens for vault storage
    testToken.approve(address(vaultStorage), FEED_AMOUNT);

    // Call feedWithExpiredAt function
    vaultStorage.feedWithExpiredAt(testTokenAddress, FEED_AMOUNT, expiredAt);

    // Verify reward debt expired time
    assertEq(
      vaultStorage.rewardDebtExpiredAt(testTokenAddress),
      expiredAt,
      "Reward debt expired time should match provided expiredAt"
    );
  }

  function testCorrectness_WhenGetPendingRewardDebtBeforeExpiry() external {
    // First feed some tokens
    testToken.approve(address(vaultStorage), FEED_AMOUNT);
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);

    // Move time forward by half the duration
    vm.warp(block.timestamp + DURATION / 2);

    // Get pending reward debt
    uint256 pendingRewardDebt = vaultStorage.getPendingRewardDebt(testTokenAddress);

    // Should be approximately half of the original amount
    assertApproxEqRel(
      pendingRewardDebt,
      FEED_AMOUNT / 2,
      0.01e18, // 1% tolerance
      "Pending reward debt should be approximately half after half duration"
    );
  }

  function testCorrectness_WhenGetPendingRewardDebtAfterExpiry() external {
    // First feed some tokens
    testToken.approve(address(vaultStorage), FEED_AMOUNT);
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);

    // Move time forward beyond the expiry
    vm.warp(block.timestamp + DURATION + 1);

    // Get pending reward debt
    uint256 pendingRewardDebt = vaultStorage.getPendingRewardDebt(testTokenAddress);

    // Should be zero after expiry
    assertEq(pendingRewardDebt, 0, "Pending reward debt should be zero after expiry");
  }

  function testCorrectness_WhenGetPendingRewardDebtAtExpiry() external {
    // First feed some tokens
    testToken.approve(address(vaultStorage), FEED_AMOUNT);
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);

    // Move time to exactly the expiry
    vm.warp(block.timestamp + DURATION);

    // Get pending reward debt
    uint256 pendingRewardDebt = vaultStorage.getPendingRewardDebt(testTokenAddress);

    // Should be zero at expiry
    assertEq(pendingRewardDebt, 0, "Pending reward debt should be zero at expiry");
  }

  function testCorrectness_WhenGetPendingRewardDebtWithMultipleFeeds() external {
    uint256 feedAmount1 = 500 * 1e18;
    uint256 feedAmount2 = 300 * 1e18;
    uint256 duration1 = 86400; // 1 day
    uint256 duration2 = 43200; // 12 hours

    // First feed
    testToken.approve(address(vaultStorage), feedAmount1 + feedAmount2);
    vaultStorage.feed(testTokenAddress, feedAmount1, duration1);

    // Check pending reward debt at different times
    uint256 pendingRewardDebt1 = vaultStorage.getPendingRewardDebt(testTokenAddress);
    assertGt(pendingRewardDebt1, 0, "Should have pending reward debt after feeds");

    // Move time forward and add second feed
    vm.warp(block.timestamp + 3600); // 1 hour later
    vaultStorage.feed(testTokenAddress, feedAmount2, duration2);

    // Move to after first expiry but before second
    vm.warp(block.timestamp + duration2 / 10);
    uint256 pendingRewardDebt2 = vaultStorage.getPendingRewardDebt(testTokenAddress);
    assertGt(pendingRewardDebt2, 0, "Should still have pending reward debt from second feed");

    // Move to after both expiries
    vm.warp(block.timestamp + duration2);
    uint256 pendingRewardDebt3 = vaultStorage.getPendingRewardDebt(testTokenAddress);
    assertEq(pendingRewardDebt3, 0, "Should have no pending reward debt after all expiries");
  }

  function testCorrectness_WhenGetPendingRewardDebtWithZeroRewardDebt() external {
    uint256 pendingRewardDebt = vaultStorage.getPendingRewardDebt(testTokenAddress);
    assertEq(pendingRewardDebt, 0, "Pending reward debt should be zero when no reward debt exists");
  }

  function testRevert_WhenFeedWithZeroAmount() external {
    testToken.approve(address(vaultStorage), FEED_AMOUNT);

    vm.expectRevert(IVaultStorage.IVaultStorage_FeedAmountZero.selector);
    vaultStorage.feed(testTokenAddress, 0, DURATION);
  }

  function testRevert_WhenFeedWithZeroDuration() external {
    testToken.approve(address(vaultStorage), FEED_AMOUNT);

    vm.expectRevert(IVaultStorage.IVaultStorage_DurationZero.selector);
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, 0);
  }

  function testRevert_WhenFeedWithoutApproval() external {
    vm.expectRevert("ERC20: insufficient allowance");
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);
  }

  function testRevert_WhenFeedByNonExecutor() external {
    // Remove this contract as executor
    vaultStorage.setServiceExecutors(address(this), false);

    testToken.approve(address(vaultStorage), FEED_AMOUNT);

    vm.expectRevert(IVaultStorage.IVaultStorage_NotWhiteListed.selector);
    vaultStorage.feed(testTokenAddress, FEED_AMOUNT, DURATION);
  }

  function testRevert_WhenFeedWithoutEnoughTokens() external {
    // Approve more tokens than we actually have
    testToken.approve(address(vaultStorage), testToken.balanceOf(address(this)) + 1);

    // Try to feed more tokens than we have
    uint256 amountToFeed = testToken.balanceOf(address(this)) + 1;

    vm.expectRevert("ERC20: transfer amount exceeds balance");
    vaultStorage.feed(testTokenAddress, amountToFeed, DURATION);
  }

  function testCorrectness_WhenFeedWithExpiredAtCalculation() external {
    uint256 expiredAt = block.timestamp + DURATION;

    testToken.approve(address(vaultStorage), FEED_AMOUNT);
    vaultStorage.feedWithExpiredAt(testTokenAddress, FEED_AMOUNT, expiredAt);

    // Verify the duration calculation is correct
    assertEq(
      vaultStorage.rewardDebtExpiredAt(testTokenAddress) - vaultStorage.rewardDebtStartAt(testTokenAddress),
      DURATION,
      "Duration should match the calculated duration from expiredAt"
    );
  }
}
