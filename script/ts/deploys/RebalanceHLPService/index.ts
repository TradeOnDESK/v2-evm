import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const config = getConfig();
const minHLPValueLossBPS = 50; // 0.5%

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("RebalanceHLPService", deployer);
  const contract = await upgrades.deployProxy(Contract, [
    config.tokens.sglp,
    config.vendors.gmx.rewardRouterV2,
    config.vendors.gmx.glpManager,
    config.storages.vault,
    config.storages.config,
    config.calculator,
    config.extension.switchCollateralRouter,
    minHLPValueLossBPS,
  ]);

  await contract.deployed();
  console.log(`Deploying RebalanceHLPService Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.services.rebalanceHLP = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "RebalanceHLPService",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
