import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, tenderly, upgrades, network, getChainId } from "hardhat";
import { getConfig, loadConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const chainId = Number(await getChainId());
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const TradingStakingHook = await ethers.getContractFactory("TradingStakingHook", deployer);
  const tradingStakingHook = config.hooks.tradingStaking;

  console.log(`[upgrade/TradingStakingHook] Preparing to upgrade TradingStakingHook`);
  const newImplementation = await upgrades.prepareUpgrade(tradingStakingHook, TradingStakingHook);
  console.log(`[upgrade/TradingStakingHook] Done`);

  console.log(`[upgrade/TradingStakingHook] New TradingStakingHook Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(tradingStakingHook, newImplementation.toString());
  console.log(`[upgrade/TradingStakingHook] Upgraded!`);

  console.log(`[upgrade/TradingStakingHook] Verify contract on Tenderly`);
  await tenderly.verify({
    address: newImplementation.toString(),
    name: "TradingStakingHook",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
