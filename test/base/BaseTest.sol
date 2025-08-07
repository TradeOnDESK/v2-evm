// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { TestBase } from "forge-std/Base.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheatsSafe } from "forge-std/StdCheats.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

/**
 * Libraries
 */
import { Deployer } from "@hmx-test/libs/Deployer.sol";

import { ERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/ERC20.sol";
import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

// Mocks
import { MockErc20 } from "../mocks/MockErc20.sol";
import { MockWNative } from "../mocks/MockWNative.sol";
import { MockPyth } from "pyth-sdk-solidity/MockPyth.sol";
import { MockCalculator } from "../mocks/MockCalculator.sol";
import { MockPerpStorage } from "../mocks/MockPerpStorage.sol";
import { MockVaultStorage } from "../mocks/MockVaultStorage.sol";
import { MockOracleMiddleware } from "../mocks/MockOracleMiddleware.sol";
import { MockLiquidityService } from "../mocks/MockLiquidityService.sol";
import { MockTradeService } from "../mocks/MockTradeService.sol";
import { MockCrossMarginService } from "../mocks/MockCrossMarginService.sol";
import { MockLiquidationService } from "../mocks/MockLiquidationService.sol";
import { MockGlpManager } from "../mocks/MockGlpManager.sol";
import { MockGmxRewardRouterV2 } from "../mocks/MockGmxRewardRouterV2.sol";

// Interfaces
import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";

import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IPythAdapter } from "@hmx/oracles/interfaces/IPythAdapter.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";

import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";
import { console } from "forge-std/console.sol";
import { EcoPyth } from "@hmx/oracles/EcoPyth.sol";

import { IConvertedGlpStrategy } from "@hmx/strategies/interfaces/IConvertedGlpStrategy.sol";
import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";

abstract contract BaseTest is TestBase, StdAssertions, StdCheatsSafe {
  address internal ALICE;
  address internal BOB;
  address internal CAROL;
  address internal DAVE;
  address internal FEEVER;
  address internal BOT;

  // storages
  IConfigStorage internal configStorage;
  IPerpStorage internal perpStorage;
  IVaultStorage internal vaultStorage;

  // other contracts
  IHLP internal hlp;
  ICalculator internal calculator;

  // oracle
  IPythAdapter pythAdapter;
  IOracleMiddleware oracleMiddleware;
  IEcoPyth internal ecoPyth;

  // mock
  MockPyth internal mockPyth;
  MockCalculator internal mockCalculator;
  MockPerpStorage internal mockPerpStorage;
  MockVaultStorage internal mockVaultStorage;
  MockOracleMiddleware internal mockOracle;
  MockLiquidityService internal mockLiquidityService;
  MockTradeService internal mockTradeService;
  MockLiquidationService internal mockLiquidationService;
  MockCrossMarginService internal mockCrossMarginService;
  MockGlpManager internal mockGlpManager;
  MockGmxRewardRouterV2 internal mockGmxRewardRouterv2;

  // strategy
  IConvertedGlpStrategy convertedGlpStrategy;

  MockWNative internal weth;
  MockErc20 internal wbtc;
  MockErc20 internal dai;
  MockErc20 internal usdc;
  MockErc20 internal usdt;
  MockErc20 internal sglp;

  MockErc20 internal bad;

  ProxyAdmin internal proxyAdmin;

  // market indexes
  uint256 ethMarketIndex;
  uint256 btcMarketIndex;

  // Crypto
  bytes32 internal constant wethPriceId = 0x0000000000000000000000000000000000000000000000000000000000000001;
  bytes32 internal constant wbtcPriceId = 0x0000000000000000000000000000000000000000000000000000000000000002;
  bytes32 internal constant daiPriceId = 0x0000000000000000000000000000000000000000000000000000000000000003;
  bytes32 internal constant usdcPriceId = 0x0000000000000000000000000000000000000000000000000000000000000004;
  bytes32 internal constant usdtPriceId = 0x0000000000000000000000000000000000000000000000000000000000000005;
  // Fx
  bytes32 internal constant jpyPriceId = 0x0000000000000000000000000000000000000000000000000000000000000101;
  bytes32 internal constant eurPriceId = 0x0000000000000000000000000000000000000000000000000000000000000102;
  bytes32 internal constant gbpPriceId = 0x0000000000000000000000000000000000000000000000000000000000000103;
  bytes32 internal constant cadPriceId = 0x0000000000000000000000000000000000000000000000000000000000000104;
  bytes32 internal constant sekPriceId = 0x0000000000000000000000000000000000000000000000000000000000000105;
  bytes32 internal constant chfPriceId = 0x0000000000000000000000000000000000000000000000000000000000000106;
  // CIX
  bytes32 internal constant cix1PriceId = 0x0000000000000000000000000000000000000000000000000000000000000201;

  bytes32 internal constant wethAssetId = "WETH";
  bytes32 internal constant wbtcAssetId = "WBTC";
  bytes32 internal constant daiAssetId = "DAI";
  bytes32 internal constant usdcAssetId = "USDC";
  bytes32 internal constant usdtAssetId = "USDT";
  bytes32 internal constant sglpAssetId = "SGLP";
  bytes32 internal constant jpyAssetId = "JPY";
  bytes32 internal constant eurAssetId = "EUR";
  bytes32 internal constant gbpAssetId = "GBP";
  bytes32 internal constant cadAssetId = "CAD";
  bytes32 internal constant sekAssetId = "SEK";
  bytes32 internal constant chfAssetId = "CHF";
  bytes32 internal constant cix1AssetId = "CIX1";

  constructor() {
    ALICE = makeAddr("Alice");
    BOB = makeAddr("BOB");
    CAROL = makeAddr("CAROL");
    DAVE = makeAddr("DAVE");
    FEEVER = makeAddr("FEEVER");

    weth = new MockWNative();
    wbtc = new MockErc20("Wrapped Bitcoin", "WBTC", 8);
    dai = new MockErc20("DAI Stablecoin", "DAI", 18);
    usdc = new MockErc20("USD Coin", "USDC", 6);
    usdt = new MockErc20("USD Tether", "USDT", 6);
    sglp = new MockErc20("Staked GLP", "sGLP", 18);
    bad = new MockErc20("Bad Coin", "BAD", 2);

    proxyAdmin = new ProxyAdmin();

    // Creating a mock Pyth instance with 60 seconds valid time period
    // and 1 wei for updating price.
    mockPyth = new MockPyth(60, 1);
    ecoPyth = Deployer.deployEcoPyth(address(proxyAdmin));

    hlp = Deployer.deployHLP(address(proxyAdmin));

    configStorage = Deployer.deployConfigStorage(address(proxyAdmin));
    perpStorage = Deployer.deployPerpStorage(address(proxyAdmin));
    vaultStorage = Deployer.deployVaultStorage(address(proxyAdmin));

    mockOracle = new MockOracleMiddleware();
    mockCalculator = new MockCalculator(address(mockOracle));

    mockPerpStorage = new MockPerpStorage();
    mockVaultStorage = new MockVaultStorage();
    mockOracle = new MockOracleMiddleware();
    mockTradeService = new MockTradeService();
    mockLiquidationService = new MockLiquidationService();
    mockLiquidityService = new MockLiquidityService(
      address(configStorage),
      address(perpStorage),
      address(vaultStorage)
    );

    mockGlpManager = new MockGlpManager();
    mockGmxRewardRouterv2 = new MockGmxRewardRouterV2();

    pythAdapter = Deployer.deployPythAdapter(address(proxyAdmin), address(mockPyth));
    oracleMiddleware = Deployer.deployOracleMiddleware(address(proxyAdmin), 365 days);

    convertedGlpStrategy = Deployer.deployConvertedGlpStrategy(
      address(proxyAdmin),
      IERC20Upgradeable(address(sglp)),
      IGmxRewardRouterV2(mockGmxRewardRouterv2),
      IVaultStorage(vaultStorage)
    );

    // configStorage setup
    _setUpAssetConfigs();
    _setUpLiquidityConfig();
    // _setUpSwapConfig();
    _setUpTradingConfig();
    _setUpAssetClassConfigs();
    _setUpMarketConfigs();
    _setUpHlpTokenConfigs();
    _setUpCollateralTokenConfigs();
    _setUpLiquidationConfig();

    // set general config
    configStorage.setCalculator(address(mockCalculator));
    configStorage.setOracle(address(mockOracle));
    configStorage.setWeth(address(weth));
  }

  /// @notice set up liquidity config
  function _setUpLiquidityConfig() private {
    configStorage.setLiquidityConfig(
      IConfigStorage.LiquidityConfig({
        depositFeeRateBPS: 0,
        withdrawFeeRateBPS: 0,
        maxHLPUtilizationBPS: 0.8 * 1e4,
        hlpTotalTokenWeight: 0,
        hlpSafetyBufferBPS: 0.6 * 1e4,
        taxFeeRateBPS: 0.005 * 1e4, // 0.5%
        flashLoanFeeRateBPS: 0,
        dynamicFeeEnabled: false,
        enabled: true
      })
    );
  }

  /// @notice set up swap config
  // function _setUpSwapConfig() private {
  //   configStorage.setSwapConfig(IConfigStorage.SwapConfig({ stablecoinSwapFeeRateBPS: 0, swapFeeRateBPS: 0 }));
  // }

  /// @notice set up trading config
  function _setUpTradingConfig() private {
    configStorage.setTradingConfig(
      IConfigStorage.TradingConfig({
        fundingInterval: 1,
        devFeeRateBPS: 0.15 * 1e4,
        minProfitDuration: 0,
        maxPosition: 5
      })
    );
  }

  /// @notice set up all asset class configs in Perp
  function _setUpAssetClassConfigs() private {
    IConfigStorage.AssetClassConfig memory _cryptoConfig = IConfigStorage.AssetClassConfig({
      baseBorrowingRate: 0.0001 * 1e18 // 0.01% per fundingInterval
    });
    IConfigStorage.AssetClassConfig memory _forexConfig = IConfigStorage.AssetClassConfig({
      baseBorrowingRate: 0.0002 * 1e18 // 0.02% per fundingInterval
    });
    configStorage.addAssetClassConfig(_cryptoConfig);
    configStorage.addAssetClassConfig(_forexConfig);
  }

  /// @notice set up all market configs in Perp
  function _setUpMarketConfigs() private {
    // add market config
    IConfigStorage.MarketConfig memory _ethConfig = IConfigStorage.MarketConfig({
      assetId: wethAssetId,
      maxLongPositionSize: 10_000_000 * 1e30,
      maxShortPositionSize: 10_000_000 * 1e30,
      assetClass: 0,
      maxProfitRateBPS: 9 * 1e4,
      initialMarginFractionBPS: 0.01 * 1e4,
      maintenanceMarginFractionBPS: 0.005 * 1e4,
      increasePositionFeeRateBPS: 0,
      decreasePositionFeeRateBPS: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: IConfigStorage.FundingRate({ maxFundingRate: 0, maxSkewScaleUSD: 0 })
    });

    IConfigStorage.MarketConfig memory _btcConfig = IConfigStorage.MarketConfig({
      assetId: wbtcAssetId,
      maxLongPositionSize: 10_000_000 * 1e30,
      maxShortPositionSize: 10_000_000 * 1e30,
      assetClass: 0,
      maxProfitRateBPS: 9 * 1e4,
      initialMarginFractionBPS: 0.01 * 1e4,
      maintenanceMarginFractionBPS: 0.005 * 1e4,
      increasePositionFeeRateBPS: 0,
      decreasePositionFeeRateBPS: 0,
      allowIncreasePosition: true,
      active: true,
      fundingRate: IConfigStorage.FundingRate({ maxFundingRate: 0, maxSkewScaleUSD: 0 })
    });

    ethMarketIndex = configStorage.addMarketConfig(_ethConfig, false);
    btcMarketIndex = configStorage.addMarketConfig(_btcConfig, false);
  }

  /// @notice set up all hlp token configs in Perp
  function _setUpHlpTokenConfigs() private {
    // set HLP token
    configStorage.setHLP(address(hlp));

    // add Accepted Token for LP config
    IConfigStorage.HLPTokenConfig[] memory _hlpTokenConfig = new IConfigStorage.HLPTokenConfig[](5);
    // WETH
    _hlpTokenConfig[0] = IConfigStorage.HLPTokenConfig({
      targetWeight: 2e17,
      bufferLiquidity: 0,
      maxWeightDiff: 1e18,
      accepted: true
    });
    // WBTC
    _hlpTokenConfig[1] = IConfigStorage.HLPTokenConfig({
      targetWeight: 2e17,
      bufferLiquidity: 0,
      maxWeightDiff: 1e18,
      accepted: true
    });
    // DAI
    _hlpTokenConfig[2] = IConfigStorage.HLPTokenConfig({
      targetWeight: 1e17,
      bufferLiquidity: 0,
      maxWeightDiff: 1e18,
      accepted: true
    });
    // USDC
    _hlpTokenConfig[3] = IConfigStorage.HLPTokenConfig({
      targetWeight: 3e17,
      bufferLiquidity: 0,
      maxWeightDiff: 1e18,
      accepted: true
    });
    // USDT
    _hlpTokenConfig[4] = IConfigStorage.HLPTokenConfig({
      targetWeight: 2e17,
      bufferLiquidity: 0,
      maxWeightDiff: 1e18,
      accepted: true
    });

    address[] memory _tokens = new address[](5);
    _tokens[0] = address(weth);
    _tokens[1] = address(wbtc);
    _tokens[2] = address(dai);
    _tokens[3] = address(usdc);
    _tokens[4] = address(usdt);

    configStorage.addOrUpdateAcceptedToken(_tokens, _hlpTokenConfig);
  }

  /// @notice set up all collateral token configs in Perp
  function _setUpCollateralTokenConfigs() private {
    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigWeth = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 0.8 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(wethAssetId, _collatTokenConfigWeth);

    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigWbtc = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 0.9 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(wbtcAssetId, _collatTokenConfigWbtc);

    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigUsdt = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 1 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(usdtAssetId, _collatTokenConfigUsdt);

    IConfigStorage.CollateralTokenConfig memory _collatTokenConfigUsdc = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 1 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(usdcAssetId, _collatTokenConfigUsdc);
  }

  function _setUpLiquidationConfig() private {
    IConfigStorage.LiquidationConfig memory _liquidationConfig = IConfigStorage.LiquidationConfig({
      liquidationFeeUSDE30: 5 * 1e30
    });

    configStorage.setLiquidationConfig(_liquidationConfig);
  }

  function _setUpAssetConfigs() private {
    IConfigStorage.AssetConfig memory _assetConfigWeth = IConfigStorage.AssetConfig({
      tokenAddress: address(weth),
      assetId: wethAssetId,
      decimals: 18,
      isStableCoin: false
    });
    configStorage.setAssetConfig(wethAssetId, _assetConfigWeth);

    IConfigStorage.AssetConfig memory _assetConfigWbtc = IConfigStorage.AssetConfig({
      tokenAddress: address(wbtc),
      assetId: wbtcAssetId,
      decimals: 8,
      isStableCoin: false
    });
    configStorage.setAssetConfig(wbtcAssetId, _assetConfigWbtc);

    IConfigStorage.AssetConfig memory _assetConfigUsdt = IConfigStorage.AssetConfig({
      tokenAddress: address(usdt),
      assetId: usdtAssetId,
      decimals: 6,
      isStableCoin: true
    });
    configStorage.setAssetConfig(usdtAssetId, _assetConfigUsdt);

    IConfigStorage.AssetConfig memory _assetConfigUsdc = IConfigStorage.AssetConfig({
      tokenAddress: address(usdc),
      assetId: usdcAssetId,
      decimals: 6,
      isStableCoin: true
    });
    configStorage.setAssetConfig(usdcAssetId, _assetConfigUsdc);

    IConfigStorage.AssetConfig memory _assetConfigDai = IConfigStorage.AssetConfig({
      tokenAddress: address(dai),
      assetId: daiAssetId,
      decimals: 18,
      isStableCoin: true
    });
    configStorage.setAssetConfig(daiAssetId, _assetConfigDai);
  }

  function abs(int256 x) external pure returns (uint256) {
    return uint256(x >= 0 ? x : -x);
  }
}
