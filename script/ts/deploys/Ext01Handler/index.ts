import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("Ext01Handler", deployer);
  const contract = await upgrades.deployProxy(Contract, [
    config.services.crossMargin,
    config.services.liquidation,
    config.services.liquidity,
    config.services.trade,
    config.oracles.ecoPyth2,
  ]);
  await contract.deployed();
  console.log(`[deploy/Ext01Handler] Deploying Ext01Handler Contract`);
  console.log(`[deploy/Ext01Handler] Deployed at: ${contract.address}`);

  config.handlers.ext01 = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "Ext01Handler",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
