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

contract MigrateCollateralToDESK_ForkTest is ForkEnv, Cheats {
  function setUp() public virtual {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"));

    // -- UPGRADE -- //
    vm.startPrank(ForkEnv.proxyAdmin.owner());
    Deployer.upgrade("CrossMarginHandler", address(ForkEnv.proxyAdmin), address(ForkEnv.crossMarginHandler));

    ForkEnv.crossMarginHandler.setDESKVault(ForkEnv.deskVault);
    vm.stopPrank();
  }

  function testCorrectness_withdrawToDESK() external {
    deal(address(ForkEnv.usdc), ForkEnv.ALICE, 100e6);

    vm.startPrank(ForkEnv.ALICE);
    ForkEnv.usdc.approve(address(ForkEnv.crossMarginHandler), type(uint256).max);
    ForkEnv.crossMarginHandler.depositCollateral(0, address(ForkEnv.usdc), 100e6, false);
    vm.stopPrank();

    vm.startPrank(ForkEnv.ALICE);
    deal(ForkEnv.ALICE, 1 ether);
    uint256 executionOrderFee = ForkEnv.crossMarginHandler.minExecutionOrderFee();
    ForkEnv.crossMarginHandler.createWithdrawCollateralOrder{ value: executionOrderFee }(
      0,
      address(ForkEnv.usdc),
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
    ) = ForkEnv.ecoPythBuilder.build(data);

    uint256 aliceBalanceBefore = ForkEnv.usdc.balanceOf(ForkEnv.ALICE);
    uint256 deskVaultBalanceBefore = ForkEnv.usdc.balanceOf(ForkEnv.deskVault);
    uint256 deskDepositRequestId = IDESKVault(ForkEnv.deskVault).totalDepositRequests() + 1;

    vm.prank(ForkEnv.liquidityOrderExecutor);
    ForkEnv.crossMarginHandler.executeOrder(
      type(uint256).max,
      payable(ALICE),
      _priceUpdateCalldata,
      _publishTimeUpdateCalldata,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );

    assertEq(aliceBalanceBefore, ForkEnv.usdc.balanceOf(ForkEnv.ALICE));
    assertEq(deskVaultBalanceBefore + 100e6, ForkEnv.usdc.balanceOf(ForkEnv.deskVault));

    (bytes32 subaccount, uint256 amount, address tokenAddress) = IDESKVault(ForkEnv.deskVault).depositRequests(
      deskDepositRequestId
    );
    assertEq(subaccount, bytes32(bytes20(address(ForkEnv.ALICE))));
    assertEq(amount, 100e6);
    assertEq(tokenAddress, address(ForkEnv.usdc));
  }
}
