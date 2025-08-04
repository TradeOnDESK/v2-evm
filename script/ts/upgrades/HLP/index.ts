import { ethers, run, tenderly, upgrades } from "hardhat";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const Contract = await ethers.getContractFactory("HLP", deployer);
  const TARGET_ADDRESS = config.tokens.hlp;

  console.log(`[upgrades/HLP] Preparing to upgrade HLP`);
  const newImplementation = await upgrades.prepareUpgrade(TARGET_ADDRESS, Contract);
  console.log(`[upgrades/HLP] Done`);

  console.log(`[upgrades/HLP] New HLP Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(TARGET_ADDRESS, newImplementation.toString());
  console.log(`[upgrades/HLP] Done`);

  console.log(`[upgrades/HLP] Verify contract on Etherscan`);
  await run("verify:verify", {
    address: newImplementation.toString(),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
