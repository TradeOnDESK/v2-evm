// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

/// Forge
import { stdJson } from "forge-std/StdJson.sol";
import { Test } from "forge-std/Test.sol";

/// OZ
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// HMX Tests
import { MockEcoPyth } from "@hmx-test/mocks/MockEcoPyth.sol";

/// Oracles
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPythAdapter } from "@hmx/oracles/interfaces/IPythAdapter.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { OnChainPriceLens } from "@hmx/oracles/OnChainPriceLens.sol";

/// Readers
import { IOrderReader } from "@hmx/readers/interfaces/IOrderReader.sol";
import { ILiquidationReader } from "@hmx/readers/interfaces/ILiquidationReader.sol";
import { IPositionReader } from "@hmx/readers/interfaces/IPositionReader.sol";

/// Handlers
import { CrossMarginHandler } from "@hmx/handlers/CrossMarginHandler.sol";
import { LimitTradeHandler } from "@hmx/handlers/LimitTradeHandler.sol";
import { LiquidityHandler } from "@hmx/handlers/LiquidityHandler.sol";
import { IBotHandler } from "@hmx/handlers/interfaces/IBotHandler.sol";
import { RebalanceHLPHandler } from "@hmx/handlers/RebalanceHLPHandler.sol";

/// Services
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { LiquidationService } from "@hmx/services/LiquidationService.sol";
import { LiquidityService } from "@hmx/services/LiquidityService.sol";
import { TradeService } from "@hmx/services/TradeService.sol";
import { RebalanceHLPService } from "@hmx/services/RebalanceHLPService.sol";

/// Storages
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";
import { VaultStorage } from "@hmx/storages/VaultStorage.sol";

/// Helpers
import { ITradeHelper } from "@hmx/helpers/interfaces/ITradeHelper.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";

/// Staking
import { IHLPStaking } from "@hmx/staking/interfaces/IHLPStaking.sol";
import { ITradingStaking } from "@hmx/staking/interfaces/ITradingStaking.sol";

/// Dexter
import { UniswapDexter } from "@hmx/extensions/dexters/UniswapDexter.sol";

/// SwitchRouter
import { SwitchCollateralRouter } from "@hmx/extensions/switch-collateral/SwitchCollateralRouter.sol";

/// Vendors
/// Uniswap
import { IPermit2 } from "@hmx/interfaces/uniswap/IPermit2.sol";
import { IUniversalRouter } from "@hmx/interfaces/uniswap/IUniversalRouter.sol";
/// GMX
import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { IGmxVault } from "@hmx/interfaces/gmx/IGmxVault.sol";
/// GMXv2
import { IGmxV2Reader } from "@hmx/interfaces/gmx-v2/IGmxV2Reader.sol";
import { IGmxV2DepositHandler } from "@hmx/interfaces/gmx-v2/IGmxV2DepositHandler.sol";
import { IGmxV2WithdrawalHandler } from "@hmx/interfaces/gmx-v2/IGmxV2WithdrawalHandler.sol";
import { IGmxV2ExchangeRouter } from "@hmx/interfaces/gmx-v2/IGmxV2ExchangeRouter.sol";
import { IGmxV2RoleStore } from "@hmx/interfaces/gmx-v2/IGmxV2RoleStore.sol";
/// Curve
import { IStableSwap } from "@hmx/interfaces/curve/IStableSwap.sol";

import { ITradeHelper } from "@hmx/helpers/interfaces/ITradeHelper.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";

import { AdaptiveFeeCalculator } from "@hmx/contracts/AdaptiveFeeCalculator.sol";
import { OrderbookOracle } from "@hmx/oracles/OrderbookOracle.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";
import { HMXLib } from "@hmx/libraries/HMXLib.sol";
import { UncheckedEcoPythCalldataBuilder } from "@hmx/oracles/UncheckedEcoPythCalldataBuilder.sol";
import { IOrderReader } from "@hmx/readers/interfaces/IOrderReader.sol";
import { LimitTradeHelper } from "@hmx/helpers/LimitTradeHelper.sol";

abstract contract ForkEnv is Test {
  using stdJson for string;

  string json = vm.readFile("configs/arbitrum.mainnet.json");

  function getAddress(string memory key) internal view returns (address _value) {
    return abi.decode(json.parseRaw(key), (address));
  }

  /// Account
  address internal constant deployer = 0x6a5D2BF8ba767f7763cd342Cb62C5076f9924872;
  address internal constant multiSig = 0x6409ba830719cd0fE27ccB3051DF1b399C90df4a;
  address internal constant glpWhale = 0x39aB5960c21578b9ced6a6A6Ed6ceb0547df20A7;
  address internal constant liquidityOrderExecutor = 0xd7BfD4F9de8016C0A28FD1AA8A3AcbA460563492;
  address internal constant crossMarginOrderExecutor = 0xd7BfD4F9de8016C0A28FD1AA8A3AcbA460563492;
  address internal constant positionManager = 0xd7BfD4F9de8016C0A28FD1AA8A3AcbA460563492;
  address internal constant limitOrderExecutor = 0x7FDD623c90a0097465170EdD352Be27A9f3ad817;

  address public ALICE = makeAddr("Alice");
  address public BOB = makeAddr("Bob");

  /// Proxy
  ProxyAdmin internal proxyAdmin = ProxyAdmin(getAddress(".proxyAdmin"));

  /// Protocol
  /// Oracles
  IEcoPyth internal ecoPyth2 = IEcoPyth(getAddress(".oracles.ecoPyth2"));
  IEcoPythCalldataBuilder internal ecoPythBuilder =
    IEcoPythCalldataBuilder(getAddress(".oracles.unsafeEcoPythCalldataBuilder")); // UnsafeEcoPythCalldataBuilder
  IPythAdapter internal pythAdapter = IPythAdapter(getAddress(".oracles.pythAdapter"));
  IOracleMiddleware internal oracleMiddleware = IOracleMiddleware(getAddress(".oracles.middleware"));
  OnChainPriceLens internal onChainPriceLens = OnChainPriceLens(getAddress(".oracles.onChainPriceLens"));
  /// Handlers
  CrossMarginHandler internal crossMarginHandler = CrossMarginHandler(payable(getAddress(".handlers.crossMargin")));
  LimitTradeHandler internal limitTradeHandler = LimitTradeHandler(payable(getAddress(".handlers.limitTrade")));
  LiquidityHandler internal liquidityHandler = LiquidityHandler(payable(getAddress(".handlers.liquidity")));
  IBotHandler internal botHandler = IBotHandler(getAddress(".handlers.bot"));
  RebalanceHLPHandler internal rebalanceHLPHandler = RebalanceHLPHandler(getAddress(".handlers.rebalanceHLP"));
  // Readers
  ILiquidationReader internal liquidationReader = ILiquidationReader(getAddress(".reader.liquidation"));
  IPositionReader internal positionReader = IPositionReader(getAddress(".reader.position"));
  IOrderReader internal orderReader = IOrderReader(getAddress(".reader.order"));
  /// Services
  CrossMarginService internal crossMarginService = CrossMarginService(getAddress(".services.crossMargin"));
  LiquidationService internal liquidationService = LiquidationService(getAddress(".services.liquidation"));
  LiquidityService internal liquidityService = LiquidityService(getAddress(".services.liquidity"));
  TradeService internal tradeService = TradeService(getAddress(".services.trade"));
  RebalanceHLPService internal rebalanceHLPService = RebalanceHLPService(getAddress(".services.rebalanceHLP"));
  /// Storages
  ConfigStorage internal configStorage = ConfigStorage(getAddress(".storages.config"));
  PerpStorage internal perpStorage = PerpStorage(getAddress(".storages.perp"));
  VaultStorage internal vaultStorage = VaultStorage(getAddress(".storages.vault"));
  /// Helpers
  LimitTradeHelper internal limitTradeHelper = LimitTradeHelper(getAddress(".helpers.limitTrade"));
  ICalculator internal calculator = ICalculator(getAddress(".calculator"));
  /// Staking
  IHLPStaking internal hlpStaking = IHLPStaking(getAddress(".staking.hlp"));
  /// Dexter
  UniswapDexter internal uniswapDexter = UniswapDexter(getAddress(".extension.dexter.uniswapV3"));
  /// SwitchRouter
  SwitchCollateralRouter internal switchCollateralRouter =
    SwitchCollateralRouter(getAddress(".extension.switchCollateralRouter"));

  /// Vendors
  /// Uniswap
  IUniversalRouter internal uniswapUniversalRouter = IUniversalRouter(getAddress(".vendors.uniswap.universalRouter"));
  IPermit2 internal uniswapPermit2 = IPermit2(getAddress(".vendors.uniswap.permit2"));
  /// GMX
  IGmxGlpManager internal glpManager = IGmxGlpManager(getAddress(".vendors.gmx.glpManager"));
  IGmxRewardRouterV2 internal gmxRewardRouterV2 = IGmxRewardRouterV2(getAddress(".vendors.gmx.rewardRouterV2"));
  IGmxVault internal gmxVault = IGmxVault(getAddress(".vendors.gmx.gmxVault"));
  /// GMXv2
  address internal gmxV2Admin = 0xE7BfFf2aB721264887230037940490351700a068;
  address internal gmxV2Timelock = 0xf32b417A93Acc039B236F1eCC86B56bd3cB8E698;
  address internal gmxV2Oracle = address(getAddress(".vendors.gmxV2.oracle"));
  IGmxV2Reader internal gmxV2Reader = IGmxV2Reader(getAddress(".vendors.gmxV2.reader"));
  IGmxV2ExchangeRouter internal gmxV2ExchangeRouter = IGmxV2ExchangeRouter(getAddress(".vendors.gmxV2.exchangeRouter"));
  address internal gmxV2DepositVault = address(getAddress(".vendors.gmxV2.depositVault"));
  address internal gmxV2DepositUtils = address(getAddress(".vendors.gmxV2.depositUtils"));
  address internal gmxV2DepositStoreUtils = address(getAddress(".vendors.gmxV2.depositStoreUtils"));
  address internal gmxV2ExecuteDepositUtils = address(getAddress(".vendors.gmxV2.executeDepositUtils"));
  IGmxV2DepositHandler internal gmxV2DepositHandler = IGmxV2DepositHandler(getAddress(".vendors.gmxV2.depositHandler"));
  address internal gmxV2WithdrawalVault = address(getAddress(".vendors.gmxV2.withdrawalVault"));
  address internal gmxV2WithdrawalUtils = address(getAddress(".vendors.gmxV2.withdrawalUtils"));
  address internal gmxV2WithdrawalStoreUtils = address(getAddress(".vendors.gmxV2.withdrawalStoreUtils"));
  address internal gmxV2ExecuteWithdrawalUtils = address(getAddress(".vendors.gmxV2.executeWithdrawalUtils"));
  IGmxV2WithdrawalHandler internal gmxV2WithdrawalHandler =
    IGmxV2WithdrawalHandler(getAddress(".vendors.gmxV2.withdrawalHandler"));
  address internal gmxV2MarketUtils = address(getAddress(".vendors.gmxV2.marketUtils"));
  address internal gmxV2MarketStoreUtils = address(getAddress(".vendors.gmxV2.marketStoreUtils"));
  address internal gmxV2DataStore = address(getAddress(".vendors.gmxV2.dataStore"));
  IGmxV2RoleStore internal gmxV2RoleStore = IGmxV2RoleStore(getAddress(".vendors.gmxV2.roleStore"));
  address internal gmxV2OracleProvider = 0x83cBb05AA78014305194450c4AADAc887fe5DF7F;
  /// Curve
  IStableSwap internal curveWstEthPool = IStableSwap(getAddress(".vendors.curve.wstEthEthPool"));
  /// OneInch
  address internal oneInchRouter = getAddress(".vendors.oneInch.router");

  ITradeHelper internal tradeHelper = ITradeHelper(getAddress(".helpers.trade"));

  /// Tokens
  IERC20 internal usdc_e = IERC20(getAddress(".tokens.usdc"));
  IERC20 internal usdc = IERC20(getAddress(".tokens.usdcNative"));
  IERC20 internal weth = IERC20(getAddress(".tokens.weth"));
  IERC20 internal wbtc = IERC20(getAddress(".tokens.wbtc"));
  IERC20 internal usdt = IERC20(getAddress(".tokens.usdt"));
  IERC20 internal dai = IERC20(getAddress(".tokens.dai"));
  IERC20 internal constant pendle = IERC20(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
  IERC20 internal arb = IERC20(getAddress(".tokens.arb"));
  IERC20 internal sglp = IERC20(getAddress(".tokens.sglp"));
  IERC20 internal wstEth = IERC20(getAddress(".tokens.wstEth"));
  IERC20 internal hlp = IERC20(getAddress(".tokens.hlp"));

  AdaptiveFeeCalculator adaptiveFeeCalculator = AdaptiveFeeCalculator(getAddress(".adaptiveFeeCalculator"));
  OrderbookOracle orderbookOracle = OrderbookOracle(getAddress(".oracles.orderbook"));
  IERC20 internal gmBTCUSD = IERC20(getAddress(".tokens.gmBTCUSD"));
  IERC20 internal gmETHUSD = IERC20(getAddress(".tokens.gmETHUSD"));

  address internal deskVault = 0x255659CaC93868AAf7AFcfB3F862AC300E3697B4;

  function _buildDataForPrice() public view returns (IEcoPythCalldataBuilder.BuildData[] memory data) {
    bytes32[] memory pythRes = ForkEnv.ecoPyth2.getAssetIds();

    uint256 len = pythRes.length; // 35 - 1(index 0) = 34

    data = new IEcoPythCalldataBuilder.BuildData[](len - 1);

    for (uint i = 1; i < len; i++) {
      PythStructs.Price memory _ecoPythPrice = ForkEnv.ecoPyth2.getPriceUnsafe(pythRes[i]);
      data[i - 1].assetId = pythRes[i];
      data[i - 1].priceE8 = _ecoPythPrice.price;
      data[i - 1].publishTime = uint160(block.timestamp);
      data[i - 1].maxDiffBps = 15_000;
    }
  }

  function _getSubAccount(address primary, uint8 subAccountId) public pure returns (address) {
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function _setPriceData(
    uint64 _priceE8
  ) public view returns (bytes32[] memory assetIds, uint64[] memory prices, bool[] memory shouldInverts) {
    bytes32[] memory pythRes = ForkEnv.ecoPyth2.getAssetIds();
    uint256 len = pythRes.length; // 35 - 1(index 0) = 34
    assetIds = new bytes32[](len - 1);
    prices = new uint64[](len - 1);
    shouldInverts = new bool[](len - 1);

    for (uint i = 1; i < len; i++) {
      assetIds[i - 1] = pythRes[i];
      prices[i - 1] = _priceE8 * 1e8;
      if (i == 4) {
        shouldInverts[i - 1] = true; // JPY
      } else {
        shouldInverts[i - 1] = false;
      }
    }
  }

  function _setPriceDataForReader(
    uint64 _priceE8
  ) public view returns (bytes32[] memory assetIds, uint64[] memory prices, bool[] memory shouldInverts) {
    bytes32[] memory pythRes = ForkEnv.ecoPyth2.getAssetIds();
    uint256 len = pythRes.length; // 35 - 1(index 0) = 34
    assetIds = new bytes32[](len);
    prices = new uint64[](len);
    shouldInverts = new bool[](len);

    for (uint i = 1; i < len; i++) {
      assetIds[i - 1] = pythRes[i];
      prices[i - 1] = _priceE8 * 1e8;
      if (i == 4) {
        shouldInverts[i - 1] = true; // JPY
      } else {
        shouldInverts[i - 1] = false;
      }
    }

    assetIds[len - 1] = 0x555344432d4e4154495645000000000000000000000000000000000000000000; // USDC-NATIVE
    prices[len - 1] = _priceE8 * 1e8;
    shouldInverts[len - 1] = false;
  }

  function _setTickPriceZero()
    public
    view
    returns (bytes32[] memory priceUpdateData, bytes32[] memory publishTimeUpdateData)
  {
    bytes32[] memory pythRes = ForkEnv.ecoPyth2.getAssetIds();
    uint256 len = pythRes.length; // 35 - 1(index 0) = 34
    int24[] memory tickPrices = new int24[](len - 1);
    uint24[] memory publishTimeDiffs = new uint24[](len - 1);
    for (uint i = 1; i < len; i++) {
      tickPrices[i - 1] = 0;
      publishTimeDiffs[i - 1] = 0;
    }

    priceUpdateData = ForkEnv.ecoPyth2.buildPriceUpdateData(tickPrices);
    publishTimeUpdateData = ForkEnv.ecoPyth2.buildPublishTimeUpdateData(publishTimeDiffs);
  }

  function _buildDataForPriceWithSpecificPrice(
    bytes32 assetId,
    int64 priceE8
  ) public view returns (IEcoPythCalldataBuilder.BuildData[] memory data) {
    bytes32[] memory assetIds = ForkEnv.ecoPyth2.getAssetIds();

    uint256 len = assetIds.length; // 35 - 1(index 0) = 34

    data = new IEcoPythCalldataBuilder.BuildData[](len - 1);

    for (uint i = 1; i < len; i++) {
      data[i - 1].assetId = assetIds[i];
      if (assetId == assetIds[i]) {
        data[i - 1].priceE8 = priceE8;
      } else {
        data[i - 1].priceE8 = ForkEnv.ecoPyth2.getPriceUnsafe(assetIds[i]).price;
      }
      data[i - 1].publishTime = uint160(block.timestamp);
      data[i - 1].maxDiffBps = 15_000;
    }
  }

  function _validateClosedPosition(bytes32 _id) public {
    IPerpStorage.Position memory _position = ForkEnv.perpStorage.getPositionById(_id);
    // As the position has been closed, the gotten one should be empty stuct
    assertEq(_position.primaryAccount, address(0));
    assertEq(_position.marketIndex, 0);
    assertEq(_position.avgEntryPriceE30, 0);
    assertEq(_position.entryBorrowingRate, 0);
    assertEq(_position.reserveValueE30, 0);
    assertEq(_position.lastIncreaseTimestamp, 0);
    assertEq(_position.positionSizeE30, 0);
    assertEq(_position.realizedPnl, 0);
    assertEq(_position.lastFundingAccrued, 0);
    assertEq(_position.subAccountId, 0);
  }

  function _checkIsUnderMMR(
    address _primaryAccount,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256
  ) public view returns (bool) {
    address _subAccount = HMXLib.getSubAccount(_primaryAccount, _subAccountId);
    IConfigStorage.MarketConfig memory config = ForkEnv.configStorage.getMarketConfigByIndex(_marketIndex);

    int256 _subAccountEquity = ForkEnv.calculator.getEquity(_subAccount, 0, config.assetId);
    uint256 _mmr = ForkEnv.calculator.getMMR(_subAccount);
    if (_subAccountEquity < 0 || uint256(_subAccountEquity) < _mmr) return true;
    return false;
  }

  constructor() {
    // Labeling known addresses
    // Storages
    vm.label(address(configStorage), "ConfigStorage");
    vm.label(address(perpStorage), "PerpStorage");
    vm.label(address(vaultStorage), "VaultStorage");
    // GMXv2
    vm.label(address(gmxV2ExchangeRouter), "gmxV2ExchangeRouter");
    vm.label(gmxV2DepositVault, "gmxV2DepositVault");
    vm.label(gmxV2DepositUtils, "gmxV2DepositUtils");
    vm.label(address(gmxV2DepositHandler), "gmxV2DepositHandler");
    vm.label(gmxV2ExecuteDepositUtils, "gmxV2ExecuteDepositUtils");
    vm.label(gmxV2DepositStoreUtils, "gmxV2DepositStoreUtils");
    vm.label(gmxV2WithdrawalVault, "gmxV2WithdrawalVault");
    vm.label(gmxV2WithdrawalUtils, "gmxV2WithdrawalUtils");
    vm.label(gmxV2WithdrawalStoreUtils, "gmxV2WithdrawalStoreUtils");
    vm.label(address(gmxV2WithdrawalHandler), "gmxV2WithdrawalHandler");
    vm.label(gmxV2MarketUtils, "gmxV2MarketUtils");
    vm.label(gmxV2MarketStoreUtils, "gmxV2MarketStoreUtils");
    vm.label(gmxV2DataStore, "gmxV2DataStore");
    vm.label(address(gmxV2RoleStore), "gmxV2RoleStore");
    vm.label(gmxV2Oracle, "gmxV2Oracle");
    // Tokens
    vm.label(address(weth), "WETH");
    vm.label(address(wbtc), "WBTC");
    vm.label(address(usdc), "USDC");
    vm.label(address(usdc_e), "USDC.e");
  }
}
