import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const keeper = "0x6629eC35c8Aa279BA45Dbfb575c728d3812aE31a";
const treasury = "0x6629eC35c8Aa279BA45Dbfb575c728d3812aE31a";
const strategyBPS = 1000; // 10%

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("StakedGlpStrategy", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.tokens.sglp,
    {
      rewardRouter: config.yieldSources.gmx.rewardRouterV2,
      rewardTracker: config.yieldSources.gmx.rewardTracker,
      glpManager: config.yieldSources.gmx.glpManager,
      oracleMiddleware: config.oracles.middleware,
      vaultStorage: config.storages.vault,
    },
    treasury,
    strategyBPS,
  ]);
  await contract.deployed();
  console.log(`Deploying StakedGlpStrategy Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.strategies.stakedGLPStrategy = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "StakedGlpStrategy",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
