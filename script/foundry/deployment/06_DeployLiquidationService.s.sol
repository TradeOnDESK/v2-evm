// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";

import { ConfigJsonRepo } from "@hmx-script/foundry/utils/ConfigJsonRepo.s.sol";

import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { LiquidationService } from "@hmx/services/LiquidationService.sol";
import { LiquidityService } from "@hmx/services/LiquidityService.sol";
import { TradeService } from "@hmx/services/TradeService.sol";

import { Deployer } from "@hmx-test/libs/Deployer.sol";

contract DeployLiquidationService is ConfigJsonRepo {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address proxyAdminAddress = getJsonAddress(".proxyAdmin");
    address configStorageAddress = getJsonAddress(".storages.config");
    address vaultStorageAddress = getJsonAddress(".storages.vault");
    address perpStorageAddress = getJsonAddress(".storages.perp");
    address calculatorAddress = getJsonAddress(".calculator");
    // shhh compiler
    calculatorAddress;
    address tradeHelperAddress = getJsonAddress(".helpers.trade");
    address liquidationServiceAddress = address(
      Deployer.deployLiquidationService(
        proxyAdminAddress,
        perpStorageAddress,
        vaultStorageAddress,
        configStorageAddress,
        tradeHelperAddress
      )
    );

    vm.stopBroadcast();

    updateJson(".services.liquidation", liquidationServiceAddress);
  }
}
