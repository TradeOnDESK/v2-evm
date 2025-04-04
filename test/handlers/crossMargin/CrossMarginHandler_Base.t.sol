// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { BaseTest, IConfigStorage, IPerpStorage, MockErc20 } from "@hmx-test/base/BaseTest.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";

import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { MockDESKVault } from "@hmx-test/mocks/MockDESKVault.sol";

contract CrossMarginHandler_Base is BaseTest {
  ICrossMarginHandler internal crossMarginHandler;
  ICrossMarginService internal crossMarginService;
  MockDESKVault internal mockDESKVault;

  uint8 internal SUB_ACCOUNT_NO = 1;
  uint256 internal constant executionOrderFee = 0.0001 ether;
  uint256 internal constant maxExecutionChuck = 10;

  bytes[] internal priceDataBytes;

  int24[] internal tickPrices;
  uint24[] internal publishTimeDiffs;

  function setUp() public virtual {
    tickPrices = new int24[](3);
    tickPrices[0] = 99039;
    tickPrices[1] = 73135;
    tickPrices[2] = 73135;

    publishTimeDiffs = new uint24[](3);
    publishTimeDiffs[0] = 0;
    publishTimeDiffs[1] = 0;
    publishTimeDiffs[2] = 0;

    pythAdapter = Deployer.deployPythAdapter(address(proxyAdmin), address(ecoPyth));
    pythAdapter.setConfig(wbtcAssetId, wbtcAssetId, false);
    pythAdapter.setConfig(wethAssetId, wethAssetId, false);
    pythAdapter.setConfig(usdcAssetId, usdcAssetId, false);

    ecoPyth.setUpdater(address(this), true);

    ecoPyth.insertAssetId(wbtcAssetId);
    ecoPyth.insertAssetId(wethAssetId);
    ecoPyth.insertAssetId(usdcAssetId);

    // have to updatePriceFeed first, before oracleMiddleware.setAssetPriceConfig sanity check price
    bytes32[] memory priceUpdateDatas = ecoPyth.buildPriceUpdateData(tickPrices);
    bytes32[] memory publishTimeUpdateDatas = ecoPyth.buildPublishTimeUpdateData(publishTimeDiffs);

    ecoPyth.updatePriceFeeds(priceUpdateDatas, publishTimeUpdateDatas, 1600, keccak256("pyth"));

    oracleMiddleware.setAssetPriceConfig(wethAssetId, 1e6, 60, address(pythAdapter));
    oracleMiddleware.setAssetPriceConfig(wbtcAssetId, 1e6, 60, address(pythAdapter));
    oracleMiddleware.setAssetPriceConfig(usdcAssetId, 1e6, 60, address(pythAdapter));

    calculator = Deployer.deployCalculator(
      address(proxyAdmin),
      address(oracleMiddleware),
      address(vaultStorage),
      address(mockPerpStorage),
      address(configStorage)
    );

    crossMarginService = Deployer.deployCrossMarginService(
      address(proxyAdmin),
      address(configStorage),
      address(vaultStorage),
      address(perpStorage),
      address(calculator),
      address(convertedGlpStrategy)
    );
    crossMarginHandler = Deployer.deployCrossMarginHandler(
      address(proxyAdmin),
      address(crossMarginService),
      address(ecoPyth),
      executionOrderFee,
      maxExecutionChuck
    );

    ecoPyth.setUpdater(address(crossMarginHandler), true);
    // Set whitelist for service executor
    configStorage.setServiceExecutor(address(crossMarginService), address(crossMarginHandler), true);
    vaultStorage.setServiceExecutors(address(crossMarginService), true);

    crossMarginHandler.setOrderExecutor(address(this), true);

    // Set accepted token deposit/withdraw as WETH and USDC
    IConfigStorage.CollateralTokenConfig memory _collateralConfigWETH = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 0.8 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    IConfigStorage.CollateralTokenConfig memory _collateralConfigUSDC = IConfigStorage.CollateralTokenConfig({
      collateralFactorBPS: 0.8 * 1e4,
      accepted: true,
      settleStrategy: address(0)
    });

    configStorage.setCollateralTokenConfig(wethAssetId, _collateralConfigWETH);
    configStorage.setCollateralTokenConfig(usdcAssetId, _collateralConfigUSDC);

    // Set market config
    configStorage.setMarketConfig(
      0,
      IConfigStorage.MarketConfig({
        assetId: wethAssetId,
        maxLongPositionSize: 10_000_000 * 1e30,
        maxShortPositionSize: 10_000_000 * 1e30,
        assetClass: 1,
        maxProfitRateBPS: 9 * 1e4,
        initialMarginFractionBPS: 0.1 * 1e4,
        maintenanceMarginFractionBPS: 0.005 * 1e4,
        increasePositionFeeRateBPS: 0,
        decreasePositionFeeRateBPS: 0,
        allowIncreasePosition: false,
        active: true,
        fundingRate: IConfigStorage.FundingRate({ maxFundingRate: 0.0004 * 1e4, maxSkewScaleUSD: 3_000_000 * 1e30 })
      }),
      false
    );

    // Mock gas for handler used for update Pyth's prices
    vm.deal(address(crossMarginHandler), 1 ether);

    // Set market status
    oracleMiddleware.setUpdater(address(this), true);
    oracleMiddleware.setMarketStatus(wbtcAssetId, uint8(2)); // active
    oracleMiddleware.setMarketStatus(wethAssetId, uint8(2)); // active

    mockDESKVault = new MockDESKVault();
    mockDESKVault.setMinDeposit(address(usdc), 10e6);
  }

  /**
   * COMMON FUNCTION
   */

  function getSubAccount(address _primary, uint8 _subAccountId) internal pure returns (address _subAccount) {
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }

  function simulateAliceDepositToken(address _token, uint256 _depositAmount) internal {
    vm.startPrank(ALICE);
    MockErc20(_token).approve(address(crossMarginHandler), _depositAmount);
    crossMarginHandler.depositCollateral(SUB_ACCOUNT_NO, _token, _depositAmount, false);
    vm.stopPrank();
  }

  function simulateAliceWithdrawToken(
    address _token,
    uint256 _withdrawAmount,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 /* _minPublishTime */,
    bool _shouldUnwrap
  ) internal {
    vm.deal(ALICE, executionOrderFee);

    vm.prank(ALICE);
    uint256 orderIndex = crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      SUB_ACCOUNT_NO,
      _token,
      _withdrawAmount,
      executionOrderFee,
      _shouldUnwrap
    );

    bytes32[] memory priceUpdateData = ecoPyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = ecoPyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    crossMarginHandler.executeOrder({
      _endIndex: orderIndex,
      _feeReceiver: payable(FEEVER),
      _priceData: priceUpdateData,
      _publishTimeData: publishTimeUpdateData,
      _minPublishTime: block.timestamp,
      _encodedVaas: keccak256("someEncodedVaas")
    });
  }

  function simulateAliceWithdrawToken(
    address _token,
    uint256 _withdrawAmount,
    int24[] memory _tickPrices,
    uint24[] memory _publishTimeDiffs,
    uint256 /* _minPublishTime */,
    bool _shouldUnwrap,
    bool _isMigrateToDESK
  ) internal {
    vm.deal(ALICE, executionOrderFee);

    vm.prank(ALICE);
    uint256 orderIndex = crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      SUB_ACCOUNT_NO,
      _token,
      _withdrawAmount,
      executionOrderFee,
      _shouldUnwrap,
      _isMigrateToDESK
    );

    bytes32[] memory priceUpdateData = ecoPyth.buildPriceUpdateData(_tickPrices);
    bytes32[] memory publishTimeUpdateData = ecoPyth.buildPublishTimeUpdateData(_publishTimeDiffs);
    crossMarginHandler.executeOrder({
      _endIndex: orderIndex,
      _feeReceiver: payable(FEEVER),
      _priceData: priceUpdateData,
      _publishTimeData: publishTimeUpdateData,
      _minPublishTime: block.timestamp,
      _encodedVaas: keccak256("someEncodedVaas")
    });
  }

  function simulateAliceCreateWithdrawOrder() internal {
    vm.deal(ALICE, 0.0001 ether);

    vm.prank(ALICE);
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      SUB_ACCOUNT_NO,
      address(weth),
      1 ether,
      0.0001 ether,
      false
    );
  }

  function simulateExecuteWithdrawOrder() internal {
    bytes32[] memory priceUpdateData = ecoPyth.buildPriceUpdateData(tickPrices);
    bytes32[] memory publishTimeUpdateData = ecoPyth.buildPublishTimeUpdateData(publishTimeDiffs);
    crossMarginHandler.executeOrder({
      _endIndex: crossMarginHandler.getWithdrawOrderLength(),
      _feeReceiver: payable(FEEVER),
      _priceData: priceUpdateData,
      _publishTimeData: publishTimeUpdateData,
      _minPublishTime: block.timestamp,
      _encodedVaas: keccak256("someEncodedVaas")
    });
  }
}
