import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";
import { Calculator__factory, ConfigStorage__factory, PerpStorage__factory } from "../../../../typechain";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log(ethers.utils.formatBytes32String("1000SHIB"));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
