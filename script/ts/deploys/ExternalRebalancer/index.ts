import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, tenderly, upgrades, network, getChainId, run } from "hardhat";
import { getConfig, loadConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import signers from "../../entities/signers";

const BigNumber = ethers.BigNumber;

async function main() {
  const chainId = Number(await getChainId());
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);

  console.log(`[deploy/ExternalRebalancer] Preparing to deploy ExternalRebalancer`);

  const ExternalRebalancer = await ethers.getContractFactory("ExternalRebalancer", deployer);
  const contract = await upgrades.deployProxy(ExternalRebalancer, [
    config.storages.vault,
    config.calculator,
    100, // 1% max AUM drop (100 basis points)
  ]);
  await contract.deployed();

  console.log(`[deploy/ExternalRebalancer] ExternalRebalancer deployed at: ${contract.address}`);

  // Add the ExternalRebalancer to the config
  config.handlers.externalRebalancer = contract.address;
  writeConfigFile(config);

  console.log(`[deploy/ExternalRebalancer] Configuration updated`);
  console.log(`[deploy/ExternalRebalancer] VaultStorage: ${config.storages.vault}`);
  console.log(`[deploy/ExternalRebalancer] Calculator: ${config.calculator}`);
  console.log(`[deploy/ExternalRebalancer] Max AUM Drop Percentage: 1% (100 basis points)`);

  console.log(`[deploy/ExternalRebalancer] Verify contract on Etherscan`);
  await run("verify:verify", {
    address: await getImplementationAddress(network.provider, contract.address),
    constructorArguments: [],
  });

  console.log(`[deploy/ExternalRebalancer] Deployment completed successfully!`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
