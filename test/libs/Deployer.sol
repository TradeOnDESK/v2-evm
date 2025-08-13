// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// OZ
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Forge
import { Vm } from "forge-std/Vm.sol";

// Interfaces
import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IDLP } from "@hmx/contracts/interfaces/IDLP.sol";

import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IEcoPythCalldataBuilder3 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder3.sol";
import { IPyth } from "@hmx/oracles/interfaces/IPyth.sol";
import { IPythAdapter } from "@hmx/oracles/interfaces/IPythAdapter.sol";
import { ICIXPriceAdapter } from "@hmx/oracles/interfaces/ICIXPriceAdapter.sol";
import { ILeanPyth } from "@hmx/oracles/interfaces/ILeanPyth.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";

import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";

import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { ICrossMarginHandler02 } from "@hmx/handlers/interfaces/ICrossMarginHandler02.sol";
import { IBotHandler } from "@hmx/handlers/interfaces/IBotHandler.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { ILiquidityHandler02 } from "@hmx/handlers/interfaces/ILiquidityHandler02.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";
import { IRebalanceHLPHandler } from "@hmx/handlers/interfaces/IRebalanceHLPHandler.sol";
import { IRebalanceHLPv2Handler } from "@hmx/handlers/interfaces/IRebalanceHLPv2Handler.sol";

import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";
import { ILiquidationService } from "@hmx/services/interfaces/ILiquidationService.sol";
import { ILiquidityService } from "@hmx/services/interfaces/ILiquidityService.sol";
import { IRebalanceHLPService } from "@hmx/services/interfaces/IRebalanceHLPService.sol";
import { ITradingStaking } from "@hmx/staking/interfaces/ITradingStaking.sol";
import { ITradeServiceHook } from "@hmx/services/interfaces/ITradeServiceHook.sol";
import { IRewarder } from "@hmx/staking/interfaces/IRewarder.sol";

import { ITradeHelper } from "@hmx/helpers/interfaces/ITradeHelper.sol";
import { ITraderLoyaltyCredit } from "@hmx/tokens/interfaces/ITraderLoyaltyCredit.sol";
import { ITLCStaking } from "@hmx/staking/interfaces/ITLCStaking.sol";
import { IEpochRewarder } from "@hmx/staking/interfaces/IEpochRewarder.sol";

import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";
import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";
import { IGmxRewardTracker } from "@hmx/interfaces/gmx/IGmxRewardTracker.sol";

import { IStakedGlpStrategy } from "@hmx/strategies/interfaces/IStakedGlpStrategy.sol";
import { IConvertedGlpStrategy } from "@hmx/strategies/interfaces/IConvertedGlpStrategy.sol";

import { IDexter } from "@hmx/extensions/dexters/interfaces/IDexter.sol";
import { ISwitchCollateralRouter } from "@hmx/extensions/switch-collateral/interfaces/ISwitchCollateralRouter.sol";

import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import { IRebalanceHLPv2Service } from "@hmx/services/interfaces/IRebalanceHLPv2Service.sol";

import { IOrderReader } from "@hmx/readers/interfaces/IOrderReader.sol";
import { IDistributeSTIPARBStrategy } from "@hmx/strategies/interfaces/IDistributeSTIPARBStrategy.sol";
import { IERC20ApproveStrategy } from "@hmx/strategies/interfaces/IERC20ApproveStrategy.sol";
import { IIntentHandler } from "@hmx/handlers/interfaces/IIntentHandler.sol";
import { ITradeOrderHelper } from "@hmx/helpers/interfaces/ITradeOrderHelper.sol";
import { IGasService } from "@hmx/services/interfaces/IGasService.sol";

library Deployer {
  Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  /**
   * General Contracts
   */

  function deployHLP(address _proxyAdmin) internal returns (IHLP) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/HLP.sol/HLP.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IHLP(payable(_proxy));
  }

  function deployCalculator(
    address _proxyAdmin,
    address _oracle,
    address _vaultStorage,
    address _perpStorage,
    address _configStorage
  ) internal returns (ICalculator) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/Calculator.sol/Calculator.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _oracle,
      _vaultStorage,
      _perpStorage,
      _configStorage
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ICalculator(payable(_proxy));
  }

  /**
   * Oracles
   */

  function deployEcoPyth(address _proxyAdmin) internal returns (IEcoPyth) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/EcoPyth.sol/EcoPyth.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IEcoPyth(payable(_proxy));
  }

  function deployEcoPythCalldataBuilder(
    address _ecoPyth,
    address _glpManager,
    address _sGlp
  ) internal returns (IEcoPythCalldataBuilder) {
    return
      IEcoPythCalldataBuilder(
        deployContractWithArguments("EcoPythCalldataBuilder", abi.encode(_ecoPyth, _sGlp, _glpManager))
      );
  }

  function deployEcoPythCalldataBuilder3(
    address _ecoPyth,
    address _ocLens,
    address _cLens,
    bool _l2BlockNumber
  ) internal returns (IEcoPythCalldataBuilder3) {
    return
      IEcoPythCalldataBuilder3(
        deployContractWithArguments("EcoPythCalldataBuilder3", abi.encode(_ecoPyth, _ocLens, _cLens, _l2BlockNumber))
      );
  }

  function deployPythAdapter(address _proxyAdmin, address _pyth) internal returns (IPythAdapter) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/PythAdapter.sol/PythAdapter.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), _pyth);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IPythAdapter(payable(_proxy));
  }

  function deployCIXPriceAdapter() internal returns (ICIXPriceAdapter) {
    return ICIXPriceAdapter(deployContract("CIXPriceAdapter"));
  }

  function deployStakedGlpOracleAdapter(
    address _proxyAdmin,
    IERC20Upgradeable _sGlp,
    IGmxGlpManager _glpManager,
    bytes32 _sGlpAssetId
  ) internal returns (IOracleAdapter) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/StakedGlpOracleAdapter.sol/StakedGlpOracleAdapter.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,bytes32)")),
      _sGlp,
      _glpManager,
      _sGlpAssetId
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IOracleAdapter(payable(_proxy));
  }

  function deployOracleMiddleware(address _proxyAdmin, uint256 _maxTrustPriceAge) internal returns (IOracleMiddleware) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/OracleMiddleware.sol/OracleMiddleware.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(uint256)")), _maxTrustPriceAge);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IOracleMiddleware(payable(_proxy));
  }

  function deployLeanPyth(address _proxyAdmin, IPyth _pyth) internal returns (ILeanPyth) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LeanPyth.sol/LeanPyth.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), _pyth);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILeanPyth(payable(_proxy));
  }

  /**
   * Storages
   */

  function deployConfigStorage(address _proxyAdmin) internal returns (IConfigStorage) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/ConfigStorage.sol/ConfigStorage.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IConfigStorage(payable(_proxy));
  }

  function deployPerpStorage(address _proxyAdmin) internal returns (IPerpStorage) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/PerpStorage.sol/PerpStorage.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IPerpStorage(payable(_proxy));
  }

  function deployVaultStorage(address _proxyAdmin) internal returns (IVaultStorage) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/VaultStorage.sol/VaultStorage.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IVaultStorage(payable(_proxy));
  }

  /**
   * Handlers
   */

  function deployCrossMarginHandler(
    address _proxyAdmin,
    address _crossMarginService,
    address _pyth,
    uint256 _executionOrderFee,
    uint256 _maxExecutionChuck
  ) internal returns (ICrossMarginHandler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/CrossMarginHandler.sol/CrossMarginHandler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256,uint256)")),
      _crossMarginService,
      _pyth,
      _executionOrderFee,
      _maxExecutionChuck
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ICrossMarginHandler(payable(_proxy));
  }

  function deployCrossMarginHandler02(
    address _proxyAdmin,
    address _crossMarginService,
    address _pyth,
    uint256 _executionOrderFee
  ) internal returns (ICrossMarginHandler02) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/CrossMarginHandler02.sol/CrossMarginHandler02.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256)")),
      _crossMarginService,
      _pyth,
      _executionOrderFee
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ICrossMarginHandler02(payable(_proxy));
  }

  function deployLiquidityHandler(
    address _proxyAdmin,
    address _liquidityService,
    address _pyth,
    uint256 _executionOrderFee,
    uint256 _maxExecutionChuck
  ) internal returns (ILiquidityHandler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LiquidityHandler.sol/LiquidityHandler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256,uint256)")),
      _liquidityService,
      _pyth,
      _executionOrderFee,
      _maxExecutionChuck
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILiquidityHandler(payable(_proxy));
  }

  function deployLiquidityHandler02(
    address _proxyAdmin,
    address _liquidityService,
    address _pyth,
    uint256 _executionOrderFee
  ) internal returns (ILiquidityHandler02) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LiquidityHandler02.sol/LiquidityHandler02.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256)")),
      _liquidityService,
      _pyth,
      _executionOrderFee
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILiquidityHandler02(payable(_proxy));
  }

  function deployLimitTradeHandler(
    address _proxyAdmin,
    address _weth,
    address _tradeService,
    address _pyth,
    uint64 _minExecutionFee,
    uint32 _minExecutionTimestamp
  ) internal returns (ILimitTradeHandler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LimitTradeHandler.sol/LimitTradeHandler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,uint64,uint32)")),
      _weth,
      _tradeService,
      _pyth,
      _minExecutionFee,
      _minExecutionTimestamp
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILimitTradeHandler(payable(_proxy));
  }

  function deployExt01Handler(
    address _proxyAdmin,
    address _crossMarginService,
    address _liquidationService,
    address _liquidityService,
    address _tradeService,
    address _pyth
  ) internal returns (IExt01Handler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/Ext01Handler.sol/Ext01Handler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address,address)")),
      _crossMarginService,
      _liquidationService,
      _liquidityService,
      _tradeService,
      _pyth
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IExt01Handler(payable(_proxy));
  }

  function deployBotHandler(
    address _proxyAdmin,
    address _tradeService,
    address _liquidationService,
    address _crossMarginService,
    address _pyth
  ) internal returns (IBotHandler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/BotHandler.sol/BotHandler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _tradeService,
      _liquidationService,
      _crossMarginService,
      _pyth
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IBotHandler(payable(_proxy));
  }

  function deployRebalanceHLPHandler(
    address _proxyAdmin,
    address _rebalanceHLPService,
    address _pyth
  ) internal returns (IRebalanceHLPHandler) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/RebalanceHLPHandler.sol/RebalanceHLPHandler.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _rebalanceHLPService,
      _pyth
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IRebalanceHLPHandler(payable(_proxy));
  }

  /**
   * Staking
   */

  function deployTradingStaking(address _proxyAdmin) internal returns (ITradingStaking) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TradingStaking.sol/TradingStaking.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITradingStaking(payable(_proxy));
  }

  function deployTradingStakingHook(
    address _proxyAdmin,
    address _tradingStaking,
    address _tradeService
  ) internal returns (ITradeServiceHook) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TradingStakingHook.sol/TradingStakingHook.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _tradingStaking,
      _tradeService
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITradeServiceHook(payable(_proxy));
  }

  function deployFeedableRewarder(
    address _proxyAdmin,
    string memory _name,
    address _rewardToken,
    address _staking
  ) internal returns (IRewarder) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/FeedableRewarder.sol/FeedableRewarder.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(string,address,address)")),
      _name,
      _rewardToken,
      _staking
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IRewarder(payable(_proxy));
  }

  function deployTLCStaking(address _proxyAdmin, address _stakingToken) internal returns (ITLCStaking) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TLCStaking.sol/TLCStaking.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), _stakingToken);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITLCStaking(payable(_proxy));
  }

  function deployTLCHook(
    address _proxyAdmin,
    address _tradeService,
    address _tlc,
    address _tlcStaking
  ) internal returns (ITradeServiceHook) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TLCHook.sol/TLCHook.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      _tradeService,
      _tlc,
      _tlcStaking
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITradeServiceHook(payable(_proxy));
  }

  function deployEpochFeedableRewarder(
    address _proxyAdmin,
    string memory _name,
    address _rewardToken,
    address _staking
  ) internal returns (IEpochRewarder) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/EpochFeedableRewarder.sol/EpochFeedableRewarder.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(string,address,address)")),
      _name,
      _rewardToken,
      _staking
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IEpochRewarder(payable(_proxy));
  }

  /**
   * Services
   */

  function deployCrossMarginService(
    address _proxyAdmin,
    address _configStorage,
    address _vaultStorage,
    address _perpStorage,
    address _calculator,
    address _convertedGlpStrategy
  ) internal returns (ICrossMarginService) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/CrossMarginService.sol/CrossMarginService.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address,address)")),
      _configStorage,
      _vaultStorage,
      _perpStorage,
      _calculator,
      _convertedGlpStrategy
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ICrossMarginService(payable(_proxy));
  }

  function deployTradeService(
    address _proxyAdmin,
    address _perpStorage,
    address _vaultStorage,
    address _configStorage,
    address _tradeHelper
  ) internal returns (ITradeService) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TradeService.sol/TradeService.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _perpStorage,
      _vaultStorage,
      _configStorage,
      _tradeHelper
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITradeService(payable(_proxy));
  }

  function deployLiquidationService(
    address _proxyAdmin,
    address _perpStorage,
    address _vaultStorage,
    address _configStorage,
    address _tradeHelper
  ) internal returns (ILiquidationService) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LiquidationService.sol/LiquidationService.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _perpStorage,
      _vaultStorage,
      _configStorage,
      _tradeHelper
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILiquidationService(payable(_proxy));
  }

  function deployLiquidityService(
    address _proxyAdmin,
    address _perpStorage,
    address _vaultStorage,
    address _configStorage
  ) internal returns (ILiquidityService) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/LiquidityService.sol/LiquidityService.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      _perpStorage,
      _vaultStorage,
      _configStorage
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ILiquidityService(payable(_proxy));
  }

  function deployRebalanceHLPService(
    address _proxyAdmin,
    address _sglp,
    address _rewardsRouter,
    address _glpManager,
    address _vaultStorage,
    address _configStorage,
    address _calculator,
    address _switchCollateralRouter,
    uint16 _minHLPValueLossBPS
  ) internal returns (IRebalanceHLPService) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/RebalanceHLPService.sol/RebalanceHLPService.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address,address,address,address,uint16)")),
      _sglp,
      _rewardsRouter,
      _glpManager,
      _vaultStorage,
      _configStorage,
      _calculator,
      _switchCollateralRouter,
      _minHLPValueLossBPS
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IRebalanceHLPService(payable(_proxy));
  }

  /**
   * Helpers
   */

  function deployTradeHelper(
    address _proxyAdmin,
    address _perpStorage,
    address _vaultStorage,
    address _configStorage
  ) internal returns (ITradeHelper) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/TradeHelper.sol/TradeHelper.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      _perpStorage,
      _vaultStorage,
      _configStorage
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITradeHelper(payable(_proxy));
  }

  /**
   * Tokens
   */

  function deployTLCToken(address _proxyAdmin) internal returns (ITraderLoyaltyCredit) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/TraderLoyaltyCredit.sol/TraderLoyaltyCredit.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return ITraderLoyaltyCredit(payable(_proxy));
  }

  /*
   * Strategies
   */

  function deployStakedGlpStrategy(
    address _proxyAdmin,
    IERC20Upgradeable _sGlp,
    IStakedGlpStrategy.StakedGlpStrategyConfig memory _stakedGlpStrategyConfig,
    address _treasury,
    uint16 _strategyBps
  ) internal returns (IStakedGlpStrategy) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/StakedGlpStrategy.sol/StakedGlpStrategy.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,(address,address,address,address,address),address,uint16)")),
      _sGlp,
      _stakedGlpStrategyConfig,
      _treasury,
      _strategyBps
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IStakedGlpStrategy(payable(_proxy));
  }

  function deployConvertedGlpStrategy(
    address _proxyAdmin,
    IERC20Upgradeable _sGlp,
    IGmxRewardRouterV2 _rewardRouter,
    IVaultStorage _vaultStorage
  ) internal returns (IConvertedGlpStrategy) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/ConvertedGlpStrategy.sol/ConvertedGlpStrategy.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      _sGlp,
      _rewardRouter,
      _vaultStorage
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IConvertedGlpStrategy(payable(_proxy));
  }

  function deployRebalanceHLPv2Handler(
    address _proxyAdmin,
    address _rebalanceHLPv2Service,
    address _weth,
    uint256 _minExecutionFee
  ) internal returns (IRebalanceHLPv2Handler) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/RebalanceHLPv2Handler.sol/RebalanceHLPv2Handler.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256)")),
      _rebalanceHLPv2Service,
      _weth,
      _minExecutionFee
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IRebalanceHLPv2Handler(payable(_proxy));
  }

  function deployRebalanceHLPv2Service(
    address _proxyAdmin,
    address _weth,
    address _vaultStorage,
    address _configStorage,
    address _exchangeRouter,
    address _depositVault,
    address _depositHandler,
    address _withdrawalVault,
    address _withdrawalHandler
  ) internal returns (IRebalanceHLPv2Service) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/RebalanceHLPv2Service.sol/RebalanceHLPv2Service.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address,address,address,address,address)")),
      _weth,
      _vaultStorage,
      _configStorage,
      _exchangeRouter,
      _depositVault,
      _depositHandler,
      _withdrawalVault,
      _withdrawalHandler
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IRebalanceHLPv2Service(payable(_proxy));
  }

  /**
   * Extensions
   */

  function deploySwitchCollateralRouter() internal returns (ISwitchCollateralRouter) {
    return ISwitchCollateralRouter(deployContract("SwitchCollateralRouter"));
  }

  function deployUniswapDexter(address _permit2, address _universalRouter) internal returns (IDexter) {
    return IDexter(deployContractWithArguments("UniswapDexter", abi.encode(_permit2, _universalRouter)));
  }

  function deployCurveDexter(address _weth) internal returns (IDexter) {
    return IDexter(deployContractWithArguments("CurveDexter", abi.encode(_weth)));
  }

  function deployGlpDexter(
    address _weth,
    address _sGlp,
    address _glpManager,
    address _gmxVault,
    address _gmxRewardRouter
  ) internal returns (IDexter) {
    return
      IDexter(
        deployContractWithArguments("GlpDexter", abi.encode(_weth, _sGlp, _glpManager, _gmxVault, _gmxRewardRouter))
      );
  }

  function deployOrderReader(
    address _configStorage,
    address _perpStorage,
    address _oracleMiddleware,
    address _limitTradeHandler
  ) internal returns (IOrderReader) {
    return
      IOrderReader(
        deployContractWithArguments(
          "OrderReader",
          abi.encode(_configStorage, _perpStorage, _oracleMiddleware, _limitTradeHandler)
        )
      );
  }

  function deployDistributeSTIPARBStrategy(
    address _proxyAdmin,
    address _vaultStorage,
    address _rewarder,
    address _arb,
    uint256 _devFeeBps,
    address _treasury,
    address _approveStrat
  ) internal returns (IDistributeSTIPARBStrategy) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/DistributeSTIPARBStrategy.sol/DistributeSTIPARBStrategy.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,uint256,address,address)")),
      _vaultStorage,
      _rewarder,
      _arb,
      _devFeeBps,
      _treasury,
      _approveStrat
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IDistributeSTIPARBStrategy(payable(_proxy));
  }

  function deployERC20ApproveStrategy(
    address _proxyAdmin,
    address _vaultStorage
  ) internal returns (IERC20ApproveStrategy) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/ERC20ApproveStrategy.sol/ERC20ApproveStrategy.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), _vaultStorage);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IERC20ApproveStrategy(payable(_proxy));
  }

  function deployTradeOrderHelper(
    address _configStorage,
    address _perpStorage,
    address _oracle,
    address _tradeService
  ) internal returns (ITradeOrderHelper) {
    return
      ITradeOrderHelper(
        deployContractWithArguments(
          "TradeOrderHelper",
          abi.encode(_configStorage, _perpStorage, _oracle, _tradeService)
        )
      );
  }

  function deployIntentHandler(
    address _proxyAdmin,
    address _pyth,
    address _configStorage,
    address _tradeOrderHelper,
    address _gasService
  ) internal returns (IIntentHandler) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/IntentHandler.sol/IntentHandler.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _pyth,
      _configStorage,
      _tradeOrderHelper,
      _gasService
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IIntentHandler(payable(_proxy));
  }

  function deployGasService(
    address _proxyAdmin,
    address _vaultStorage,
    address _configStorage,
    uint256 _executionFeeInUsd,
    address _executionFeeTreasury,
    bytes32 _gasTokenAssetId
  ) internal returns (IGasService) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/GasService.sol/GasService.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,uint256,address,bytes32)")),
      _vaultStorage,
      _configStorage,
      _executionFeeInUsd,
      _executionFeeTreasury,
      _gasTokenAssetId
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IGasService(payable(_proxy));
  }

  function deployDLP(address _proxyAdmin, address _asset) internal returns (IDLP) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/DLP.sol/DLP.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), _asset);
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer, _proxyAdmin);
    return IDLP(payable(_proxy));
  }

  /**
   * Private Functions
   */

  function deployContract(string memory _name) internal returns (address _deployedAddress) {
    string memory _jsonFile = string.concat("./out/", _name, ".sol/", _name, ".json");

    bytes memory _logicBytecode = abi.encodePacked(vm.getCode(_jsonFile));

    assembly {
      _deployedAddress := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_deployedAddress)) {
        revert(0, 0)
      }
    }
  }

  function deployContractWithArguments(
    string memory _name,
    bytes memory _args
  ) internal returns (address _deployedAddress) {
    string memory _jsonFile = string.concat("./out/", _name, ".sol/", _name, ".json");

    bytes memory _logicBytecode = abi.encodePacked(vm.getCode(_jsonFile), _args);

    assembly {
      _deployedAddress := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_deployedAddress)) {
        revert(0, 0)
      }
    }
  }

  function upgrade(string memory _contractName, address _proxyAdmin, address _proxy) internal {
    address _newImpl = deployContract(_contractName);
    ProxyAdmin(_proxyAdmin).upgrade(TransparentUpgradeableProxy(payable(_proxy)), _newImpl);
  }

  function upgradeAndCall(
    string memory _contractName,
    address _proxyAdmin,
    address _proxy,
    bytes memory data
  ) internal {
    address _newImpl = deployContract(_contractName);
    ProxyAdmin(_proxyAdmin).upgradeAndCall(TransparentUpgradeableProxy(payable(_proxy)), _newImpl, data);
  }

  function _setupUpgradeable(
    bytes memory _logicBytecode,
    bytes memory _initializer,
    address _proxyAdmin
  ) internal returns (address) {
    bytes memory _proxyBytecode = abi.encodePacked(
      vm.getCode("./out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json")
    );

    address _logic;
    assembly {
      _logic := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
    }

    _proxyBytecode = abi.encodePacked(_proxyBytecode, abi.encode(_logic, _proxyAdmin, _initializer));

    address _proxy;
    assembly {
      _proxy := create(0, add(_proxyBytecode, 0x20), mload(_proxyBytecode))
      if iszero(extcodesize(_proxy)) {
        revert(0, 0)
      }
    }

    return _proxy;
  }
}
