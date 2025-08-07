import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("ConvertedGlpStrategy", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.tokens.sglp,
    config.yieldSources.gmx.rewardRouterV2,
    config.storages.vault,
  ]);
  await contract.deployed();
  console.log(`Deploying ConvertedGlpStrategy Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.strategies.convertedGlpStrategy = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "ConvertedGlpStrategy",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
