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

  const TLCHook = await ethers.getContractFactory("TLCHook", deployer);
  const tlcHook = config.hooks.tlc;

  console.log(`[upgrade/TLCHook] Preparing to upgrade TLCHook`);
  const newImplementation = await upgrades.prepareUpgrade(tlcHook, TLCHook);
  console.log(`[upgrade/TLCHook] Done`);

  console.log(`[upgrade/TLCHook] New TLCHook Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(tlcHook, newImplementation.toString());
  console.log(`[upgrade/TLCHook] Upgraded!`);

  console.log(`[upgrade/TLCHook] Verify contract on Tenderly`);
  await tenderly.verify({
    address: newImplementation.toString(),
    name: "TLCHook",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
