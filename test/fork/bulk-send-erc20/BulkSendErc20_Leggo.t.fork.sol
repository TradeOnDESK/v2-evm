// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

/// OZ
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";

/// HMX Tests
import { Cheats } from "@hmx-test/base/Cheats.sol";
import { ForkEnv } from "@hmx-test/fork/bases/ForkEnv.sol";

/// HMX
import { BulkSendErc20 } from "@hmx/tokens/BulkSendErc20.sol";

contract BulkSendErc20_LeggoForkTest is ForkEnv, Cheats {
  BulkSendErc20 internal bulkSendErc20;

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("arbitrum_fork"), 145403536);

    bulkSendErc20 = new BulkSendErc20();
  }

  function testCorrectness_WhenLeggo() external {
    motherload(address(ForkEnv.usdc_e), address(this), 10_000_00 * 1e6);
    motherload(address(ForkEnv.weth), address(this), 10_000_00 * 1e18);

    ForkEnv.usdc_e.approve(address(bulkSendErc20), type(uint256).max);
    ForkEnv.weth.approve(address(bulkSendErc20), type(uint256).max);

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = ForkEnv.usdc_e;
    tokens[1] = ForkEnv.weth;

    address[] memory recipients = new address[](2);
    recipients[0] = ALICE;
    recipients[1] = BOB;

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 10_000 * 1e6;
    amounts[1] = 10_000 * 1e18;

    bulkSendErc20.leggo(tokens, recipients, amounts);

    assertEq(ForkEnv.usdc_e.balanceOf(ALICE), 10_000 * 1e6);
    assertEq(ForkEnv.weth.balanceOf(BOB), 10_000 * 1e18);

    vm.startPrank(ALICE);
    vm.expectRevert("ERC20: transfer amount exceeds allowance");
    bulkSendErc20.leggo(tokens, recipients, amounts);
  }
}
