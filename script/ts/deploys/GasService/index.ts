import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const executionFeeInUsd = ethers.utils.parseUnits("0.2", 30);
  const executionFeeTreasury = "0x7FDD623c90a0097465170EdD352Be27A9f3ad817";

  const Contract = await ethers.getContractFactory("GasService", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.storages.vault,
    config.storages.config,
    executionFeeInUsd,
    executionFeeTreasury,
  ]);
  await contract.deployed();
  console.log(`Deploying GasService Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.services.gas = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "GasService",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
