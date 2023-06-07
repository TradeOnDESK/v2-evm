import { ethers } from "hardhat";
import { ConfigStorage__factory, EcoPyth__factory, PythAdapter__factory } from "../../../../typechain";
import { getConfig } from "../../utils/config";

const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];
  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);

  console.log("> ConfigStorage: Set WETH...");
  await (await configStorage.setHLP(config.tokens.weth)).wait();
  console.log("> ConfigStorage: Set WETH success!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
