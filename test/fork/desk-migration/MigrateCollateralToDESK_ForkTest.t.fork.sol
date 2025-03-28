// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// HMX
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IDESKVault } from "@hmx/interfaces/desk/IDESKVault.sol";

/// HMX Tests
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";
import { Cheats } from "@hmx-test/base/Cheats.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MigrateCollateralToDESK_ForkTest is ForkEnv, Cheats {
  function setUp() public virtual {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"));

    // -- UPGRADE -- //
    vm.startPrank(proxyAdmin.owner());
    Deployer.upgrade("CrossMarginHandler", address(proxyAdmin), address(crossMarginHandler));

    crossMarginHandler.setDESKVault(deskVault);
    vm.stopPrank();
  }

  function testCorrectness_withdrawToDESK() external {
    deal(address(usdc), ALICE, 100e6);

    vm.startPrank(ALICE);
    usdc.approve(address(crossMarginHandler), type(uint256).max);
    crossMarginHandler.depositCollateral(0, address(usdc), 100e6, false);
    vm.stopPrank();

    assertEq(vaultStorage.traderBalances(ALICE, address(usdc)), 100e6);

    vm.startPrank(ALICE);
    deal(ALICE, 1 ether);
    uint256 executionOrderFee = crossMarginHandler.minExecutionOrderFee();
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(usdc),
      100e6,
      executionOrderFee,
      false,
      true
    );
    vm.stopPrank();

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ecoPythBuilder.build(data);

    uint256 aliceBalanceBefore = usdc.balanceOf(ALICE);
    uint256 deskVaultBalanceBefore = usdc.balanceOf(deskVault);
    uint256 deskDepositRequestId = IDESKVault(deskVault).totalDepositRequests() + 1;

    vm.prank(liquidityOrderExecutor);
    crossMarginHandler.executeOrder(
      type(uint256).max,
      payable(ALICE),
      _priceUpdateCalldata,
      _publishTimeUpdateCalldata,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );

    assertEq(aliceBalanceBefore, usdc.balanceOf(ALICE));
    assertEq(deskVaultBalanceBefore + 100e6, usdc.balanceOf(deskVault));

    (bytes32 subaccount, uint256 amount, address tokenAddress) = IDESKVault(deskVault).depositRequests(
      deskDepositRequestId
    );
    assertEq(subaccount, bytes32(bytes20(address(ALICE))));
    assertEq(amount, 100e6);
    assertEq(tokenAddress, address(usdc));
    assertEq(vaultStorage.traderBalances(ALICE, address(usdc)), 0, "Alice will have 0 USDC in the subaccount on HMX.");
  }

  function testCorrectness_withdrawToDESK_failedAtDESK() external {
    deal(address(usdc), ALICE, 100e6);

    vm.startPrank(ALICE);
    usdc.approve(address(crossMarginHandler), type(uint256).max);
    crossMarginHandler.depositCollateral(0, address(usdc), 100e6, false);
    vm.stopPrank();

    assertEq(vaultStorage.traderBalances(ALICE, address(usdc)), 100e6);

    vm.startPrank(ALICE);
    deal(ALICE, 1 ether);
    uint256 executionOrderFee = crossMarginHandler.minExecutionOrderFee();
    crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(usdc),
      100e6,
      executionOrderFee,
      false,
      true
    );
    vm.stopPrank();

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ecoPythBuilder.build(data);

    uint256 aliceBalanceBefore = usdc.balanceOf(ALICE);
    uint256 deskVaultBalanceBefore = usdc.balanceOf(deskVault);

    // Intentionally upgrade DESK Vault to break it to make every contract call to DESKVault failed
    vm.startPrank(0x6337856e255E589D376a52A55936E81bE86A4093);
    Deployer.upgradeAndCall("CrossMarginHandler", 0xBcCc1C18BB0fb718Fb44AF93B628efE75AB6B21a, address(deskVault), "");
    vm.stopPrank();

    vm.prank(liquidityOrderExecutor);
    crossMarginHandler.executeOrder(
      type(uint256).max,
      payable(ALICE),
      _priceUpdateCalldata,
      _publishTimeUpdateCalldata,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );

    assertEq(aliceBalanceBefore, usdc.balanceOf(ALICE), "Alice wallet balance remains the same.");
    assertEq(deskVaultBalanceBefore, usdc.balanceOf(deskVault), "DESK Vault balance remains the same.");
    assertEq(
      vaultStorage.traderBalances(ALICE, address(usdc)),
      100e6,
      "Alice subaccount's balance on HMX remains the same."
    );
  }
}
