import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("RebalanceHLPv2Service", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.tokens.weth,
    config.storages.vault,
    config.storages.config,
    config.vendors.gmxV2.exchangeRouter,
    config.vendors.gmxV2.depositVault,
    config.vendors.gmxV2.depositHandler,
    config.vendors.gmxV2.withdrawalVault,
    config.vendors.gmxV2.withdrawalHandler,
  ]);

  await contract.deployed();
  console.log(`[deploys/RebalanceHLPv2Service] Deploying RebalanceHLPv2Service Contract`);
  console.log(`[deploys/RebalanceHLPv2Service] Deployed at: ${contract.address}`);

  config.services.rebalanceHLPv2 = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "RebalanceHLPv2Service",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
