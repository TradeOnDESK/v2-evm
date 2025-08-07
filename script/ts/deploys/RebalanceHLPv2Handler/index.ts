import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];
  const minExecutionFee = ethers.utils.parseEther("0.001");
  const Contract = await ethers.getContractFactory("RebalanceHLPv2Handler", deployer);
  const contract = await upgrades.deployProxy(Contract, [
    config.services.rebalanceHLPv2,
    config.tokens.weth,
    minExecutionFee,
  ]);
  await contract.deployed();

  console.log(`[deploys/RebalanceHLPv2Handler] Deploying RebalanceHLPv2Handler Contract`);
  console.log(`[deploys/RebalanceHLPv2Handler] Deployed at: ${contract.address}`);

  config.handlers.rebalanceHLPv2 = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "RebalanceHLPv2Handler",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
