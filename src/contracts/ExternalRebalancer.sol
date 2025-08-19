// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

// interfaces
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";

/// @title ExternalRebalancer
/// @notice This contract handles external rebalancing operations by removing liquidity from one token
/// and replacing it with another token while ensuring AUM doesn't drop below a specified percentage.
contract ExternalRebalancer is OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /**
   * Events
   */
  event LogRebalanceStarted(
    address indexed tokenToRemove,
    uint256 amountToRemove,
    address indexed recipient,
    uint256 initialAUM
  );
  event LogRebalanceCompleted(
    address indexed tokenToRemove,
    address indexed replacementToken,
    uint256 replacementAmount,
    uint256 finalAUM,
    uint256 aumDropPercentage
  );
  event LogSetMaxAUMDropPercentage(uint16 oldPercentage, uint16 newPercentage);
  event LogSetVaultStorage(address indexed oldVaultStorage, address indexed newVaultStorage);
  event LogSetCalculator(address indexed oldCalculator, address indexed newCalculator);
  event LogSetWhitelistedExecutor(address indexed executor, bool isWhitelisted);

  /**
   * States
   */
  IVaultStorage public vaultStorage;
  ICalculator public calculator;
  uint16 public maxAUMDropPercentage; // in basis points (1% = 100 BPS)
  mapping(address => bool) public whitelistedExecutors;

  /**
   * Modifiers
   */
  modifier onlyWhitelistedExecutor() {
    if (!whitelistedExecutors[msg.sender]) revert ExternalRebalancer_NotWhitelisted();
    _;
  }

  /**
   * Errors
   */
  error ExternalRebalancer_NotWhitelisted();
  error ExternalRebalancer_InvalidAddress();
  error ExternalRebalancer_InvalidAmount();
  error ExternalRebalancer_InsufficientLiquidity();
  error ExternalRebalancer_AUMDropExceeded();
  error ExternalRebalancer_NoReplacementToken();
  error ExternalRebalancer_InsufficientReplacementAmount();
  error ExternalRebalancer_InvalidPercentage();
  error ExternalRebalancer_AUMChanged();

  function initialize(address _vaultStorage, address _calculator, uint16 _maxAUMDropPercentage) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    if (_vaultStorage == address(0) || _calculator == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }

    vaultStorage = IVaultStorage(_vaultStorage);
    calculator = ICalculator(_calculator);
    maxAUMDropPercentage = _maxAUMDropPercentage;
  }

  /**
   * @notice Start a rebalance operation by removing liquidity from a token and putting it on hold
   * @param _tokenToRemove The token to remove from HLP liquidity
   * @param _amountToRemove The amount to remove
   * @param _recipient The address to receive the removed tokens
   */
  function startRebalance(
    address _tokenToRemove,
    uint256 _amountToRemove,
    address _recipient
  ) external onlyWhitelistedExecutor nonReentrant {
    if (_tokenToRemove == address(0) || _recipient == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    if (_amountToRemove == 0) {
      revert ExternalRebalancer_InvalidAmount();
    }

    // Check if there's enough liquidity to remove
    uint256 currentLiquidity = vaultStorage.hlpLiquidity(_tokenToRemove);
    if (currentLiquidity < _amountToRemove) {
      revert ExternalRebalancer_InsufficientLiquidity();
    }

    // Get initial AUM for comparison
    uint256 initialAUM = calculator.getAUME30(false);

    // Remove liquidity and put on hold
    vaultStorage.removeHLPLiquidityOnHold(_tokenToRemove, _amountToRemove);

    // Transfer tokens to recipient
    vaultStorage.pushToken(_tokenToRemove, _recipient, _amountToRemove);

    // Validate AUM must not change
    uint256 finalAUM = calculator.getAUME30(false);
    if (finalAUM != initialAUM) {
      revert ExternalRebalancer_AUMChanged();
    }

    emit LogRebalanceStarted(_tokenToRemove, _amountToRemove, _recipient, initialAUM);
  }

  /**
   * @notice Complete a rebalance operation by clearing on-hold liquidity and adding replacement tokens
   * @param _tokenToRemove The token that was removed (to clear on-hold)
   * @param _replacementToken The token to add as replacement
   * @param _replacementAmount The amount of replacement token to add
   */
  function completeRebalance(
    address _tokenToRemove,
    address _replacementToken,
    uint256 _replacementAmount
  ) external onlyWhitelistedExecutor nonReentrant {
    if (_tokenToRemove == address(0) || _replacementToken == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    if (_replacementAmount == 0) {
      revert ExternalRebalancer_InvalidAmount();
    }

    // Get the amount that was put on hold
    uint256 onHoldAmount = vaultStorage.hlpLiquidityOnHold(_tokenToRemove);
    if (onHoldAmount == 0) {
      revert ExternalRebalancer_NoReplacementToken();
    }

    // Get initial AUM for comparison
    uint256 initialAUM = calculator.getAUME30(false);

    // Clear the on-hold amount
    vaultStorage.clearOnHold(_tokenToRemove, onHoldAmount);

    // Transfer replacement tokens from caller to vault
    IERC20Upgradeable(_replacementToken).safeTransferFrom(msg.sender, address(vaultStorage), _replacementAmount);

    // Add replacement tokens to HLP liquidity
    vaultStorage.addHLPLiquidity(_replacementToken, _replacementAmount);

    // Get final AUM and calculate drop percentage
    uint256 finalAUM = calculator.getAUME30(false);
    uint256 aumDropPercentage = 0;

    if (finalAUM <= initialAUM) {
      aumDropPercentage = ((initialAUM - finalAUM) * 10000) / initialAUM; // in basis points

      // Check if AUM drop exceeds maximum allowed
      if (aumDropPercentage > maxAUMDropPercentage) {
        revert ExternalRebalancer_AUMDropExceeded();
      }
    }

    emit LogRebalanceCompleted(_tokenToRemove, _replacementToken, _replacementAmount, finalAUM, aumDropPercentage);
  }

  /**
   * @notice Set the maximum allowed AUM drop percentage
   * @param _maxAUMDropPercentage The maximum AUM drop percentage in basis points
   */
  function setMaxAUMDropPercentage(uint16 _maxAUMDropPercentage) external onlyOwner {
    if (_maxAUMDropPercentage > 10000) {
      // 100%
      revert ExternalRebalancer_InvalidPercentage();
    }
    emit LogSetMaxAUMDropPercentage(maxAUMDropPercentage, _maxAUMDropPercentage);
    maxAUMDropPercentage = _maxAUMDropPercentage;
  }

  /**
   * @notice Set the vault storage address
   * @param _vaultStorage The new vault storage address
   */
  function setVaultStorage(address _vaultStorage) external onlyOwner {
    if (_vaultStorage == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    emit LogSetVaultStorage(address(vaultStorage), _vaultStorage);
    vaultStorage = IVaultStorage(_vaultStorage);
  }

  /**
   * @notice Set the calculator address
   * @param _calculator The new calculator address
   */
  function setCalculator(address _calculator) external onlyOwner {
    if (_calculator == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    emit LogSetCalculator(address(calculator), _calculator);
    calculator = ICalculator(_calculator);
  }

  /**
   * @notice Add an executor to the whitelist
   * @param _executor The address to whitelist
   */
  function addWhitelistedExecutor(address _executor) external onlyOwner {
    if (_executor == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    whitelistedExecutors[_executor] = true;
    emit LogSetWhitelistedExecutor(_executor, true);
  }

  /**
   * @notice Remove an executor from the whitelist
   * @param _executor The address to remove from whitelist
   */
  function removeWhitelistedExecutor(address _executor) external onlyOwner {
    if (_executor == address(0)) {
      revert ExternalRebalancer_InvalidAddress();
    }
    whitelistedExecutors[_executor] = false;
    emit LogSetWhitelistedExecutor(_executor, false);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
