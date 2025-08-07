import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const minExecutionFee = ethers.utils.parseEther("0.0003"); // 0.0003 ether
const maxExecutionChunk = 100;

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("CrossMarginHandler", deployer);
  const contract = await upgrades.deployProxy(Contract, [
    config.services.crossMargin,
    config.oracles.ecoPyth,
    minExecutionFee,
    maxExecutionChunk,
  ]);
  await contract.deployed();
  console.log(`Deploying CrossMarginHandler Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.handlers.crossMargin = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "CrossMarginHandler",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
