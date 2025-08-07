// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ConfigJsonRepo } from "@hmx-script/foundry/utils/ConfigJsonRepo.s.sol";

import { BotHandler } from "@hmx/handlers/BotHandler.sol";
import { CrossMarginHandler } from "@hmx/handlers/CrossMarginHandler.sol";
import { LimitTradeHandler } from "@hmx/handlers/LimitTradeHandler.sol";
import { LiquidityHandler } from "@hmx/handlers/LiquidityHandler.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployHandlers is ConfigJsonRepo {
  struct ContractAddress {
    address pythAddress;
    address tradeServiceAddress;
    address liquidationServiceAddress;
    address liquidityServiceAddress;
    address crossMarginServiceAddress;
    address weth;
  }

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address proxyAdmin = getJsonAddress(".proxyAdmin");

    ContractAddress memory vars = ContractAddress(
      getJsonAddress(".oracles.pyth"),
      getJsonAddress(".services.trade"),
      getJsonAddress(".services.liquidation"),
      getJsonAddress(".services.liquidity"),
      getJsonAddress(".services.crossMargin"),
      getJsonAddress(".tokens.weth")
    );

    // @todo - TBD
    uint64 minExecutionFee = 0;
    uint32 minExecutionTimestamp = 5 * 60;

    address limitTradeHandlerAddress = address(
      Deployer.deployLimitTradeHandler(
        address(proxyAdmin),
        vars.weth,
        vars.tradeServiceAddress,
        vars.pythAddress,
        minExecutionFee,
        minExecutionTimestamp
      )
    );

    vm.stopBroadcast();

    updateJson(".handlers.limitTrade", limitTradeHandlerAddress);
  }
}
