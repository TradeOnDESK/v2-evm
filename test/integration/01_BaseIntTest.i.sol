// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// Forge-std
import { TestBase } from "forge-std/Base.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

// Pyth
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { MockPyth } from "pyth-sdk-solidity/MockPyth.sol";
import { EcoPyth } from "@hmx/oracles/EcoPyth.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";

// Openzeppelin
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
// Libs
import { Deployer } from "@hmx-test/libs/Deployer.sol";

// Mock
import { MockWNative } from "@hmx-test/mocks/MockWNative.sol";
import { MockErc20 } from "@hmx-test/mocks/MockErc20.sol";
import { MockGmxRewardRouterV2 } from "@hmx-test/mocks/MockGmxRewardRouterV2.sol";

// Interfaces
import { IWNative } from "@hmx/interfaces/IWNative.sol";

import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";

import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { IPythAdapter } from "@hmx/oracles/interfaces/IPythAdapter.sol";

import { IBotHandler } from "@hmx/handlers/interfaces/IBotHandler.sol";
import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IExt01Handler } from "@hmx/handlers/interfaces/IExt01Handler.sol";

import { ConvertedGlpStrategy } from "@hmx/strategies/ConvertedGlpStrategy.sol";
import { IConvertedGlpStrategy } from "@hmx/strategies/interfaces/IConvertedGlpStrategy.sol";

import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { ILiquidityService } from "@hmx/services/interfaces/ILiquidityService.sol";
import { ILiquidationService } from "@hmx/services/interfaces/ILiquidationService.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";

import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";

import { ITradeHelper } from "@hmx/helpers/interfaces/ITradeHelper.sol";

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { LiquidityTester } from "@hmx-test/testers/LiquidityTester.sol";
import { CrossMarginTester } from "@hmx-test/testers/CrossMarginTester.sol";
import { LimitOrderTester } from "@hmx-test/testers/LimitOrderTester.sol";
import { PositionTester } from "@hmx-test/testers/PositionTester.sol";
import { MarketTester } from "@hmx-test/testers/MarketTester.sol";
import { PositionTester02 } from "@hmx-test/testers/PositionTester02.sol";
import { TradeTester } from "@hmx-test/testers/TradeTester.sol";

import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { AdaptiveFeeCalculator } from "@hmx/contracts/AdaptiveFeeCalculator.sol";
import { OrderbookOracle } from "@hmx/oracles/OrderbookOracle.sol";

import { ITradeOrderHelper } from "@hmx/helpers/interfaces/ITradeOrderHelper.sol";
import { IIntentHandler } from "@hmx/handlers/interfaces/IIntentHandler.sol";
import { IntentBuilder } from "@hmx-test/libs/IntentBuilder.sol";
import { IGasService } from "@hmx/services/interfaces/IGasService.sol";

abstract contract BaseIntTest is TestBase, StdCheats {
  /* Constants */
  uint256 internal constant executionOrderFee = 0.0001 ether;
  uint256 internal constant maxExecutionChuck = 10; // 10 orders per time
  uint256 internal constant minExecutionTimestamp = 60 * 5; // 5 minutes
  uint256 internal constant maxTrustPriceAge = type(uint32).max;

  uint256 internal constant SECONDS = 1;
  uint256 internal constant MINUTES = SECONDS * 60;
  uint256 internal constant HOURS = MINUTES * 60;
  uint256 internal constant DAYS = HOURS * 24;

  address internal ALICE;
  address internal BOB;
  address internal CAROL;
  address internal DAVE;
  address internal EVE;
  address internal FEEVER;
  address internal ORDER_EXECUTOR;
  address internal BOT;

  address internal constant EXT01_EXECUTOR = 0x7FDD623c90a0097465170EdD352Be27A9f3ad817;

  /* CONTRACTS */
  IOracleMiddleware oracleMiddleWare;
  IConfigStorage configStorage;
  IPerpStorage perpStorage;
  IVaultStorage vaultStorage;
  ICalculator calculator;

  // handlers
  IBotHandler botHandler;
  ICrossMarginHandler crossMarginHandler;
  ILimitTradeHandler limitTradeHandler;
  ILiquidityHandler liquidityHandler;

  // services
  ICrossMarginService crossMarginService;
  ILiquidityService liquidityService;
  ILiquidationService liquidationService;
  ITradeService tradeService;

  //GMX
  IGmxRewardRouterV2 gmxRewardRouterV2;

  //strategies
  IConvertedGlpStrategy convertedGlpStrategy;

  // helpers
  ITradeHelper tradeHelper;

  /* TOKENS */

  //LP tokens
  ERC20Upgradeable glp;
  IHLP hlpV2;

  MockErc20 wbtc; // decimals 8
  MockErc20 usdc; // decimals 6
  MockErc20 usdt; // decimals 6
  MockErc20 dai; // decimals 18
  MockErc20 sglp; //decimals 18

  IWNative weth; //for native

  /* PYTH */
  IEcoPyth internal pyth;
  IPythAdapter internal pythAdapter;

  /* Tester */

  CrossMarginTester crossMarginTester;
  MarketTester globalMarketTester;
  LimitOrderTester limitOrderTester;
  LiquidityTester liquidityTester;
  PositionTester positionTester;
  PositionTester02 positionTester02;
  TradeTester tradeTester;

  ProxyAdmin proxyAdmin;

  AdaptiveFeeCalculator adaptiveFeeCalculator;
  OrderbookOracle orderbookOracle;
  IExt01Handler ext01Handler;

  ITradeOrderHelper tradeOrderHelper;
  IIntentHandler intentHandler;
  IntentBuilder intentBuilder;
  IGasService gasService;

  constructor() {
    ALICE = makeAddr("Alice");
    BOB = makeAddr("BOB");
    CAROL = makeAddr("CAROL");
    DAVE = makeAddr("DAVE");
    EVE = makeAddr("EVE");
    FEEVER = makeAddr("FEEVER");
    ORDER_EXECUTOR = makeAddr("ORDER_EXECUTOR");
    BOT = makeAddr("BOT");

    /* DEPLOY PART */

    proxyAdmin = new ProxyAdmin();

    // deploy MOCK weth
    weth = IWNative(new MockWNative());
    vm.label(address(weth), "WETH");

    pyth = Deployer.deployEcoPyth(address(proxyAdmin));

    gmxRewardRouterV2 = new MockGmxRewardRouterV2();
    pythAdapter = Deployer.deployPythAdapter(address(proxyAdmin), address(pyth));

    // deploy oracleMiddleWare
    oracleMiddleWare = Deployer.deployOracleMiddleware(address(proxyAdmin), maxTrustPriceAge);

    // deploy configStorage
    configStorage = Deployer.deployConfigStorage(address(proxyAdmin));

    // deploy perpStorage
    perpStorage = Deployer.deployPerpStorage(address(proxyAdmin));

    // deploy vaultStorage
    vaultStorage = Deployer.deployVaultStorage(address(proxyAdmin));

    // Tokens
    // deploy hlp
    hlpV2 = Deployer.deployHLP(address(proxyAdmin));

    wbtc = new MockErc20("Wrapped Bitcoin", "WBTC", 8);
    dai = new MockErc20("DAI Stablecoin", "DAI", 18);
    usdc = new MockErc20("USD Coin", "USDC", 6);
    usdt = new MockErc20("USD Tether", "USDT", 6);
    sglp = new MockErc20("StakedGlp", "sGLP", 18);

    // labels
    vm.label(address(wbtc), "WBTC");
    vm.label(address(dai), "DAI");
    vm.label(address(usdc), "USDC");
    vm.label(address(usdt), "USDT");
    vm.label(address(sglp), "SGLP");

    // deploy calculator
    calculator = Deployer.deployCalculator(
      address(proxyAdmin),
      address(oracleMiddleWare),
      address(vaultStorage),
      address(perpStorage),
      address(configStorage)
    );

    // deploy handler and service
    tradeHelper = Deployer.deployTradeHelper(
      address(proxyAdmin),
      address(perpStorage),
      address(vaultStorage),
      address(configStorage)
    );

    // deploy Strategies
    convertedGlpStrategy = Deployer.deployConvertedGlpStrategy(
      address(proxyAdmin),
      IERC20Upgradeable(address(sglp)),
      IGmxRewardRouterV2(gmxRewardRouterV2),
      IVaultStorage(vaultStorage)
    );

    // deploy Services
    liquidityService = Deployer.deployLiquidityService(
      address(proxyAdmin),
      address(perpStorage),
      address(vaultStorage),
      address(configStorage)
    );
    liquidationService = Deployer.deployLiquidationService(
      address(proxyAdmin),
      address(perpStorage),
      address(vaultStorage),
      address(configStorage),
      address(tradeHelper)
    );
    crossMarginService = Deployer.deployCrossMarginService(
      address(proxyAdmin),
      address(configStorage),
      address(vaultStorage),
      address(perpStorage),
      address(calculator),
      address(convertedGlpStrategy)
    );
    tradeService = Deployer.deployTradeService(
      address(proxyAdmin),
      address(perpStorage),
      address(vaultStorage),
      address(configStorage),
      address(tradeHelper)
    );

    botHandler = Deployer.deployBotHandler(
      address(proxyAdmin),
      address(tradeService),
      address(liquidationService),
      address(crossMarginService),
      address(pyth)
    );
    crossMarginHandler = Deployer.deployCrossMarginHandler(
      address(proxyAdmin),
      address(crossMarginService),
      address(pyth),
      executionOrderFee,
      maxExecutionChuck
    );

    limitTradeHandler = Deployer.deployLimitTradeHandler(
      address(proxyAdmin),
      address(weth),
      address(tradeService),
      address(pyth),
      uint64(executionOrderFee),
      uint32(minExecutionTimestamp)
    );
    limitTradeHandler.setGuaranteeLimitPrice(true);

    liquidityHandler = Deployer.deployLiquidityHandler(
      address(proxyAdmin),
      address(liquidityService),
      address(pyth),
      executionOrderFee,
      maxExecutionChuck
    );

    // deploy executor
    ext01Handler = Deployer.deployExt01Handler(
      address(proxyAdmin),
      address(crossMarginService),
      address(liquidationService),
      address(liquidityService),
      address(tradeService),
      address(pyth)
    );

    tradeOrderHelper = Deployer.deployTradeOrderHelper(
      address(configStorage),
      address(perpStorage),
      address(oracleMiddleWare),
      address(tradeService)
    );

    gasService = Deployer.deployGasService(
      address(proxyAdmin),
      address(vaultStorage),
      address(configStorage),
      0.1 * 1e30,
      FEEVER,
      "WETHUSD"
    );

    intentHandler = Deployer.deployIntentHandler(
      address(proxyAdmin),
      address(pyth),
      address(configStorage),
      address(tradeOrderHelper),
      address(gasService)
    );

    intentBuilder = new IntentBuilder(address(configStorage));

    ext01Handler.setOrderExecutor(EXT01_EXECUTOR, true);
    ext01Handler.setMinExecutionFee(2, 0.1 * 1e9);
    pyth.setUpdater(address(ext01Handler), true);
    address[] memory _handlers = new address[](1);
    _handlers[0] = address(ext01Handler);
    address[] memory _services = new address[](1);
    _services[0] = address(crossMarginService);
    bool[] memory _isAllows = new bool[](1);
    _isAllows[0] = true;
    configStorage.setServiceExecutors(_services, _handlers, _isAllows);

    vm.label(address(ext01Handler), "ext01Handler");

    // testers
    crossMarginTester = new CrossMarginTester(vaultStorage, perpStorage, address(crossMarginHandler));
    globalMarketTester = new MarketTester(perpStorage);
    limitOrderTester = new LimitOrderTester(limitTradeHandler);
    liquidityTester = new LiquidityTester(hlpV2, vaultStorage, perpStorage, FEEVER);
    positionTester = new PositionTester(perpStorage, vaultStorage, oracleMiddleWare);
    positionTester02 = new PositionTester02(perpStorage);

    address[] memory interestTokens = new address[](1);
    interestTokens[0] = address(0);
    tradeTester = new TradeTester(vaultStorage, perpStorage, address(limitTradeHandler), interestTokens);
    /* Setup part */
    // Setup ConfigStorage
    {
      configStorage.setOracle(address(oracleMiddleWare));
      configStorage.setCalculator(address(calculator));

      // Set whitelists for executors
      configStorage.setServiceExecutor(address(crossMarginService), address(crossMarginHandler), true);
      configStorage.setServiceExecutor(address(crossMarginService), address(botHandler), true);
      configStorage.setServiceExecutor(address(tradeHelper), address(liquidationService), true);
      configStorage.setServiceExecutor(address(tradeHelper), address(tradeService), true);

      configStorage.setWeth(address(weth));
      configStorage.setHLP(address(hlpV2));

      configStorage.setConfigExecutor(address(botHandler), true);
    }

    {
      // Reload config after calculator was set on ConfigStorage
      tradeHelper.reloadConfig();
      tradeService.reloadConfig();
      liquidationService.reloadConfig();
    }

    // Setup VaultStorage
    {
      vaultStorage.setServiceExecutors(address(crossMarginService), true);
      vaultStorage.setServiceExecutors(address(tradeService), true);
      vaultStorage.setServiceExecutors(address(tradeHelper), true);
      vaultStorage.setServiceExecutors(address(liquidityService), true);
      vaultStorage.setServiceExecutors(address(liquidationService), true);
      vaultStorage.setServiceExecutors(address(botHandler), true);
      vaultStorage.setServiceExecutors(address(gasService), true);
    }

    // Setup PerpStorage
    {
      perpStorage.setServiceExecutors(address(crossMarginService), true);
      perpStorage.setServiceExecutors(address(tradeService), true);
      perpStorage.setServiceExecutors(address(tradeHelper), true);
      perpStorage.setServiceExecutors(address(liquidityService), true);
      perpStorage.setServiceExecutors(address(liquidationService), true);
    }

    // Setup Bot Handler
    {
      address[] memory _positionManagers = new address[](2);
      _positionManagers[0] = address(this);
      _positionManagers[1] = BOT;

      // set Tester as position managers
      botHandler.setPositionManagers(_positionManagers, true);
    }

    // Setup Limit Trade Handler
    {
      limitTradeHandler.setOrderExecutor(address(this), true);
    }

    // Setup Cross Margin Handler
    {
      crossMarginHandler.setOrderExecutor(address(this), true);
    }

    // Setup Intent Handler
    {
      tradeOrderHelper.setWhitelistedCaller(address(intentHandler));
      intentHandler.setIntentExecutor(address(this), true);
      configStorage.setServiceExecutor(address(gasService), address(intentHandler), true);
    }
    adaptiveFeeCalculator = new AdaptiveFeeCalculator(15000, 500);
    orderbookOracle = new OrderbookOracle();

    tradeHelper.setAdaptiveFeeCalculator(address(adaptiveFeeCalculator));
    tradeHelper.setOrderbookOracle(address(orderbookOracle));
    tradeHelper.setMaxAdaptiveFeeBps(500);

    calculator.setTradeHelper(address(tradeHelper));
  }
}
