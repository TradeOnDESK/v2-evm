import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("DistributeSTIPARBStrategy", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.storages.vault,
    "0x238DAF7b15342113B00fA9e3F3E60a11Ab4274fD", // arb rewarder <<<<< UPDATE THIS
    config.tokens.arb,
    500, // 5% dev fee
    "0x24D53494Dc9E260A6b2Ddb0b40C1ED222471779C", // treasury
    config.strategies.erc20Approve,
  ]);

  await contract.deployed();
  console.log(`Deploying DistributeSTIPARBStrategy Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.strategies.distributeSTIPARB = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "DistributeSTIPARBStrategy",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
