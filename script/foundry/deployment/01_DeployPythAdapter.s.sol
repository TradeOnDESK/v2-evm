// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";

import { PythAdapter } from "@hmx/oracles/PythAdapter.sol";

import { ConfigJsonRepo } from "@hmx-script/foundry/utils/ConfigJsonRepo.s.sol";

import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployPythAdapter is ConfigJsonRepo {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address proxyAdmin = getJsonAddress(".proxyAdmin");

    address pythAddress = getJsonAddress(".oracles.pyth");
    address pythAdapterAddress = address(Deployer.deployPythAdapter(address(proxyAdmin), pythAddress));

    vm.stopBroadcast();

    updateJson(".oracles.pythAdapter", pythAdapterAddress);
  }
}
