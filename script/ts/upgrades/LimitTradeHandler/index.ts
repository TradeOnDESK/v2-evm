import { ethers, run, upgrades, getChainId } from "hardhat";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

async function main() {
  const chainId = Number(await getChainId());
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const LimitTradeHandler = await ethers.getContractFactory("LimitTradeHandler", deployer);
  const limitTradeHandler = config.handlers.limitTrade;

  console.log(`[upgrade/LimitTradeHandler] Preparing to upgrade LimitTradeHandler`);
  const newImplementation = await upgrades.prepareUpgrade(limitTradeHandler, LimitTradeHandler, {
    unsafeAllow: ["delegatecall"],
  });
  console.log(`[upgrade/LimitTradeHandler] Done`);

  console.log(`[upgrade/LimitTradeHandler] New LimitTradeHandler Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(limitTradeHandler, newImplementation.toString());
  console.log(`[upgrade/LimitTradeHandler] Upgraded!`);

  console.log(`[upgrade/LimitTradeHandler] Verify contract`);
  await run("verify:verify", {
    address: newImplementation.toString(),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
