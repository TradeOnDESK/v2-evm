import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const treasury = "0xcf0D151f84dCa261b1d201b04cDe24227Aa181F6";
const strategyBPS = 0; // 0%

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("StakedGlpStrategy", deployer);

  const contract = await upgrades.deployProxy(Contract, [
    config.tokens.sglp,
    {
      rewardRouter: config.vendors.gmx.rewardRouterV2,
      rewardTracker: config.vendors.gmx.rewardTracker,
      glpManager: config.vendors.gmx.glpManager,
      oracleMiddleware: config.oracles.middleware,
      vaultStorage: config.storages.vault,
    },
    treasury,
    strategyBPS,
  ]);
  await contract.deployed();
  console.log(`Deploying StakedGlpStrategy Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.strategies.stakedGlpStrategy = contract.address;
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
