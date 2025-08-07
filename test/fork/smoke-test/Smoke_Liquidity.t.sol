// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Smoke_Base } from "./Smoke_Base.t.sol";
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";

import "forge-std/console.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { LiquidityHandler } from "@hmx/handlers/LiquidityHandler.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

contract Smoke_Liquidity is ForkEnv {
  function addLiquidity() external {
    _createAndExecuteAddLiquidityOrder();
  }

  function removeLiquidity() external {
    _createAndExecuteRemoveLiquidityOrder();
  }

  function _createAndExecuteAddLiquidityOrder() internal {
    deal(address(ForkEnv.usdc), ALICE, 10 * 1e6);
    deal(ALICE, 10 ether);
    deal(address(ForkEnv.liquidityHandler), 100 ether);

    vm.startPrank(ALICE);

    ForkEnv.usdc.approve(address(ForkEnv.liquidityHandler), type(uint256).max);

    uint256 minExecutionFee = ForkEnv.liquidityHandler.minExecutionOrderFee();

    uint256 _latestOrderIndex = ForkEnv.liquidityHandler.createAddLiquidityOrder{ value: minExecutionFee }(
      address(ForkEnv.usdc),
      10 * 1e6,
      0 ether,
      minExecutionFee,
      false
    );
    vm.stopPrank();

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ForkEnv.ecoPythBuilder.build(data);

    // hlp price = aum / total supply
    uint256 _hlpPriceE30 = (ForkEnv.calculator.getAUME30(false) * 1e18) / ForkEnv.hlp.totalSupply();
    uint256 _estimatedHlpReceived = (10 * 1e18 * 1e30) / _hlpPriceE30;

    vm.prank(ForkEnv.positionManager);
    ForkEnv.botHandler.updateLiquidityEnabled(true);

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    vm.prank(ForkEnv.liquidityOrderExecutor);
    ForkEnv.liquidityHandler.executeOrder(
      _latestOrderIndex,
      payable(ALICE),
      _priceUpdateCalldata,
      _publishTimeUpdateCalldata,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );

    assertApproxEqRel(
      ForkEnv.hlpStaking.calculateShare(address(this), address(ALICE)),
      _estimatedHlpReceived,
      0.01 ether,
      "User HLP Balance in Staking"
    );
    assertEq(ForkEnv.usdc.balanceOf(ALICE), 0, "User USDC.e Balance");
  }

  function _createAndExecuteRemoveLiquidityOrder() internal {
    deal(address(ForkEnv.hlp), ALICE, 10 * 1e18);
    deal(ALICE, 10 ether);
    deal(address(ForkEnv.liquidityHandler), 100 ether);

    vm.startPrank(ALICE);

    ForkEnv.hlp.approve(address(ForkEnv.liquidityHandler), type(uint256).max);

    uint256 minExecutionFee = ForkEnv.liquidityHandler.minExecutionOrderFee();

    uint256 _latestOrderIndex = ForkEnv.liquidityHandler.createRemoveLiquidityOrder{ value: minExecutionFee }(
      address(ForkEnv.usdc),
      10 * 1e18,
      0 ether,
      minExecutionFee,
      false
    );
    vm.stopPrank();

    IEcoPythCalldataBuilder.BuildData[] memory data = _buildDataForPrice();
    (
      uint256 _minPublishTime,
      bytes32[] memory _priceUpdateCalldata,
      bytes32[] memory _publishTimeUpdateCalldata
    ) = ForkEnv.ecoPythBuilder.build(data);

    // hlpPrice = aumE30 / totalSupply
    uint256 _hlpPriceE30 = (ForkEnv.calculator.getAUME30(false) * 1e18) / ForkEnv.hlp.totalSupply();
    // convert hlp e30 to usdc e6
    uint256 _estimatedUsdcReceivedE6 = (10 * 1e6 * _hlpPriceE30) / 1e30;

    vm.prank(ForkEnv.positionManager);
    ForkEnv.botHandler.updateLiquidityEnabled(true);

    vm.warp(block.timestamp + 30);
    vm.roll(block.number + 30);

    vm.prank(ForkEnv.liquidityOrderExecutor);
    ForkEnv.liquidityHandler.executeOrder(
      _latestOrderIndex,
      payable(ALICE),
      _priceUpdateCalldata,
      _publishTimeUpdateCalldata,
      _minPublishTime,
      keccak256("someEncodedVaas")
    );

    assertApproxEqRel(ForkEnv.usdc.balanceOf(ALICE), _estimatedUsdcReceivedE6, 0.01 ether, "User USDC.e Balance");
    assertEq(ForkEnv.hlp.balanceOf(ALICE), 0, "User HLP Balance");
  }
}
