// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { ConfigJsonRepo } from "@hmx-script/foundry/utils/ConfigJsonRepo.s.sol";

import { Calculator } from "@hmx/contracts/Calculator.sol";

import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployCalculators is ConfigJsonRepo {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    ProxyAdmin proxyAdmin = new ProxyAdmin();

    address oracleMiddlewareAddress = getJsonAddress(".oracles.middleware");
    address vaultStorageAddress = getJsonAddress(".storages.vault");
    address perpStorageAddress = getJsonAddress(".storages.perp");
    address configStorageAddress = getJsonAddress(".storages.config");

    address calculatorAddress = address(
      Deployer.deployCalculator(
        address(proxyAdmin),
        oracleMiddlewareAddress,
        vaultStorageAddress,
        perpStorageAddress,
        configStorageAddress
      )
    );

    vm.stopBroadcast();

    updateJson(".calculator", calculatorAddress);
  }
}
