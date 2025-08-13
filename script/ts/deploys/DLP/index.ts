import { ethers, upgrades, run, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  // Get the asset address from config - using USDC as default
  const assetAddress = config.tokens.hlp;

  console.log(`[DLP] Deploying DLP Contract with asset: ${assetAddress}`);
  console.log(`[DLP] Deployer: ${deployer.address}`);

  const Contract = await ethers.getContractFactory("DLP", deployer);
  const contract = await upgrades.deployProxy(Contract, [assetAddress]);
  await contract.deployed();

  console.log(`[DLP] DLP Contract deployed at: ${contract.address}`);

  // Add DLP to the tokens section of the config
  config.tokens.dlp = contract.address;
  writeConfigFile(config);

  await run("verify:verify", {
    address: await getImplementationAddress(network.provider, contract.address),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
