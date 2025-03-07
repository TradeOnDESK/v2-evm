import { ethers, run, upgrades } from "hardhat";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const Contract = await ethers.getContractFactory("CrossMarginHandler", deployer);
  const TARGET_ADDRESS = config.handlers.crossMargin;

  console.log(`[upgrades/CrossMarginHandler] Preparing to upgrade CrossMarginHandler`);
  const newImplementation = await upgrades.prepareUpgrade(TARGET_ADDRESS, Contract);
  console.log(`[upgrades/CrossMarginHandler] Done`);

  console.log(`[upgrades/CrossMarginHandler] New CrossMarginHandler Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(TARGET_ADDRESS, newImplementation.toString());

  console.log(`[upgrades/CrossMarginHandler] Verify contract`);
  await run("verify:verify", {
    address: newImplementation.toString(),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
