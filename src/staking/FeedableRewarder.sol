// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeCast } from "@openzeppelin-4.8.1/contracts/utils/math/SafeCast.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { TradingStaking } from "./TradingStaking.sol";
import { IRewarder } from "./interfaces/IRewarder.sol";

contract FeedableRewarder is OwnableUpgradeable, IRewarder {
  using SafeCast for uint256;
  using SafeCast for uint128;
  using SafeCast for int256;
  using SafeERC20Upgradeable for ERC20Upgradeable;

  uint256 public constant MINIMUM_PERIOD = 5 days;
  uint256 public constant MAXIMUM_PERIOD = 365 days;

  string public name;
  address public rewardToken;
  address public staking;
  address public feeder;

  // user address => reward debt
  mapping(address => int256) public userRewardDebts;

  // Reward calculation parameters
  uint64 public lastRewardTime;
  uint128 public accRewardPerShare;
  uint256 public rewardRate;
  uint256 public rewardRateExpiredAt;
  uint256 private constant ACC_REWARD_PRECISION = 1e30;

  // Events
  event LogOnDeposit(address indexed user, uint256 shareAmount);
  event LogOnWithdraw(address indexed user, uint256 shareAmount);
  event LogHarvest(address indexed user, uint256 pendingRewardAmount);
  event LogUpdateRewardCalculationParams(uint64 lastRewardTime, uint256 accRewardPerShare);
  event LogFeed(uint256 feedAmount, uint256 rewardRate, uint256 rewardRateExpiredAt);
  event LogSetFeeder(address oldFeeder, address newFeeder);

  // Error
  error FeedableRewarderError_FeedAmountDecayed();
  error FeedableRewarderError_NotStakingContract();
  error FeedableRewarderError_NotFeeder();
  error FeedableRewarderError_BadDuration();

  modifier onlyStakingContract() {
    if (msg.sender != staking) revert FeedableRewarderError_NotStakingContract();
    _;
  }

  modifier onlyFeeder() {
    if (msg.sender != feeder) revert FeedableRewarderError_NotFeeder();
    _;
  }

  function initialize(string memory name_, address rewardToken_, address staking_) external initializer {
    OwnableUpgradeable.__Ownable_init();

    // Sanity check
    ERC20Upgradeable(rewardToken_).totalSupply();
    TradingStaking(staking_).isRewarder(address(this));

    name = name_;
    rewardToken = rewardToken_;
    staking = staking_;
    lastRewardTime = block.timestamp.toUint64();

    // At initialization, assume the feeder to be the contract owner
    feeder = owner();
  }

  function onDeposit(address user, uint256 shareAmount) external onlyStakingContract {
    _updateRewardCalculationParams();

    userRewardDebts[user] =
      userRewardDebts[user] +
      ((shareAmount * accRewardPerShare) / ACC_REWARD_PRECISION).toInt256();

    emit LogOnDeposit(user, shareAmount);
  }

  function onWithdraw(address user, uint256 shareAmount) external onlyStakingContract {
    _updateRewardCalculationParams();

    userRewardDebts[user] =
      userRewardDebts[user] -
      ((shareAmount * accRewardPerShare) / ACC_REWARD_PRECISION).toInt256();

    emit LogOnWithdraw(user, shareAmount);
  }

  function onHarvest(address user, address receiver) external onlyStakingContract {
    _updateRewardCalculationParams();

    int256 accumulatedRewards = ((_userShare(user) * accRewardPerShare) / ACC_REWARD_PRECISION).toInt256();
    uint256 pendingRewardAmount = (accumulatedRewards - userRewardDebts[user]).toUint256();

    userRewardDebts[user] = accumulatedRewards;

    if (pendingRewardAmount != 0) {
      _harvestToken(receiver, pendingRewardAmount);
    }

    emit LogHarvest(user, pendingRewardAmount);
  }

  function pendingReward(address user) external view returns (uint256) {
    uint256 projectedAccRewardPerShare = accRewardPerShare + _calculateAccRewardPerShare(_totalShare());
    int256 accumulatedRewards = ((_userShare(user) * projectedAccRewardPerShare) / ACC_REWARD_PRECISION).toInt256();

    if (accumulatedRewards < userRewardDebts[user]) return 0;
    return (accumulatedRewards - userRewardDebts[user]).toUint256();
  }

  function feed(uint256 feedAmount, uint256 duration) external onlyFeeder {
    _feed(feedAmount, duration);
  }

  function feedWithExpiredAt(uint256 feedAmount, uint256 expiredAt) external onlyFeeder {
    _feed(feedAmount, expiredAt - block.timestamp);
  }

  function setFeeder(address feeder_) external onlyOwner {
    emit LogSetFeeder(feeder, feeder_);
    feeder = feeder_;
  }

  function _feed(uint256 feedAmount, uint256 duration) internal {
    if (duration < MINIMUM_PERIOD || duration > MAXIMUM_PERIOD) revert FeedableRewarderError_BadDuration();

    uint256 totalShare = _totalShare();
    _forceUpdateRewardCalculationParams(totalShare);

    {
      // Transfer token, with decay check
      uint256 balanceBefore = ERC20Upgradeable(rewardToken).balanceOf(address(this));
      ERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), feedAmount);

      if (ERC20Upgradeable(rewardToken).balanceOf(address(this)) - balanceBefore != feedAmount)
        revert FeedableRewarderError_FeedAmountDecayed();
    }

    uint256 leftOverReward = rewardRateExpiredAt > block.timestamp
      ? (rewardRateExpiredAt - block.timestamp) * rewardRate
      : 0;
    uint256 totalRewardAmount = leftOverReward + feedAmount;

    rewardRate = totalRewardAmount / duration;
    rewardRateExpiredAt = block.timestamp + duration;

    emit LogFeed(feedAmount, rewardRate, rewardRateExpiredAt);
  }

  function _updateRewardCalculationParams() internal {
    uint256 totalShare = _totalShare();
    if (block.timestamp > lastRewardTime && totalShare > 0) {
      _forceUpdateRewardCalculationParams(totalShare);
    }
  }

  function _forceUpdateRewardCalculationParams(uint256 totalShare) internal {
    accRewardPerShare += _calculateAccRewardPerShare(totalShare);
    lastRewardTime = block.timestamp.toUint64();
    emit LogUpdateRewardCalculationParams(lastRewardTime, accRewardPerShare);
  }

  function _calculateAccRewardPerShare(uint256 totalShare) internal view returns (uint128) {
    if (totalShare > 0) {
      uint256 _rewards = _timePast() * rewardRate;
      return ((_rewards * ACC_REWARD_PRECISION) / totalShare).toUint128();
    }
    return 0;
  }

  function _timePast() private view returns (uint256) {
    // Prevent timePast to go over intended reward distribution period.
    // On the other hand, prevent insufficient reward when harvest.
    if (block.timestamp < rewardRateExpiredAt) {
      return block.timestamp - lastRewardTime;
    } else if (rewardRateExpiredAt > lastRewardTime) {
      return rewardRateExpiredAt - lastRewardTime;
    } else {
      return 0;
    }
  }

  function _totalShare() private view returns (uint256) {
    return TradingStaking(staking).calculateTotalShare(address(this));
  }

  function _userShare(address user) private view returns (uint256) {
    return TradingStaking(staking).calculateShare(address(this), user);
  }

  function _harvestToken(address receiver, uint256 pendingRewardAmount) internal virtual {
    ERC20Upgradeable(rewardToken).safeTransfer(receiver, pendingRewardAmount);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
