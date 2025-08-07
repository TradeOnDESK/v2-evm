import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("CrossMarginService", deployer);
  const contract = await upgrades.deployProxy(Contract, [
    config.storages.config,
    config.storages.vault,
    config.storages.perp,
    config.calculator,
    config.strategies.convertedGlpStrategy,
  ]);
  await contract.deployed();
  console.log(`Deploying CrossMarginService Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.services.crossMargin = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "CrossMarginService",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
