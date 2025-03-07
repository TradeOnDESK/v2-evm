import { ethers, run, upgrades, getChainId } from "hardhat";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

async function main() {
  const chainId = Number(await getChainId());
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const Ext01Handler = await ethers.getContractFactory("Ext01Handler", deployer);
  const ext01Handler = config.handlers.ext01;

  console.log(`[upgrade/Ext01Handler] Preparing to upgrade Ext01Handler`);
  const newImplementation = await upgrades.prepareUpgrade(ext01Handler, Ext01Handler, {
    unsafeAllow: ["delegatecall"],
  });
  console.log(`[upgrade/Ext01Handler] Done`);

  console.log(`[upgrade/Ext01Handler] New Ext01Handler Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(ext01Handler, newImplementation.toString());
  console.log(`[upgrade/Ext01Handler] Upgraded!`);

  console.log(`[upgrade/Ext01Handler] Verify contract`);
  await run("verify:verify", {
    address: newImplementation.toString(),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
