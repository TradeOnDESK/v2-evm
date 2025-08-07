// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { BaseTest, IConfigStorage, MockErc20 } from "@hmx-test/base/BaseTest.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";

import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { MockNonEOA } from "@hmx-test/mocks/MockNonEOA.sol";

contract CrossMarginService_Base is BaseTest {
  address internal CROSS_MARGIN_HANDLER;

  ICrossMarginService crossMarginService;

  function setUp() public virtual {
    CROSS_MARGIN_HANDLER = address(new MockNonEOA());

    crossMarginService = Deployer.deployCrossMarginService(
      address(proxyAdmin),
      address(configStorage),
      address(vaultStorage),
      address(perpStorage),
      address(mockCalculator),
      address(convertedGlpStrategy)
    );

    // Set whitelist for service executor
    configStorage.setServiceExecutor(address(crossMarginService), CROSS_MARGIN_HANDLER, true);
    vaultStorage.setServiceExecutors(address(crossMarginService), true);

    // @note - ALICE must act as CROSS_MARGIN_HANDLER here because CROSS_MARGIN_HANDLER doesn't included on this unit test yet
    ALICE = address(new MockNonEOA());
    configStorage.setServiceExecutor(address(crossMarginService), ALICE, true);

    // Set accepted token deposit/withdraw
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
  }

  // =========================================
  // | ------- common function ------------- |
  // =========================================

  function simulateAliceDepositToken(address _token, uint256 _depositAmount) internal {
    vm.startPrank(ALICE);
    // simulate transfer from Handler to VaultStorage
    IERC20(_token).transfer(address(vaultStorage), _depositAmount);
    MockErc20(_token).approve(address(crossMarginService), _depositAmount);
    crossMarginService.depositCollateral(ALICE, 1, _token, _depositAmount);
    vm.stopPrank();
  }

  function simulateAliceWithdrawToken(address _token, uint256 _withdrawAmount) internal {
    vm.startPrank(ALICE);
    crossMarginService.withdrawCollateral(ALICE, 1, _token, _withdrawAmount, ALICE);
    vm.stopPrank();
  }

  function getSubAccount(address _primary, uint8 _subAccountId) internal pure returns (address _subAccount) {
    if (_subAccountId > 255) revert();
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }
}
