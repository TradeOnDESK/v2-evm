import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const tradingStaking = config.staking.trading;

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("TradingStakingHook", deployer);

  const contract = await upgrades.deployProxy(Contract, [tradingStaking, config.services.trade]);
  await contract.deployed();
  console.log(`Deploying TradingStakingHook Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.hooks.tradingStaking = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "TradingStakingHook",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
