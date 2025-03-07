import { ethers, run, upgrades, getChainId } from "hardhat";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import ProxyAdminWrapper from "../../wrappers/ProxyAdminWrapper";

async function main() {
  const chainId = Number(await getChainId());
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const proxyAdminWrapper = new ProxyAdminWrapper(chainId, deployer);

  const LiquidityHandler = await ethers.getContractFactory("LiquidityHandler", deployer);
  const liquidityHandler = config.handlers.liquidity;

  console.log(`[upgrade/LiquidityHandler] Preparing to upgrade LiquidityHandler`);
  const newImplementation = await upgrades.prepareUpgrade(liquidityHandler, LiquidityHandler);
  console.log(`[upgrade/LiquidityHandler] Done`);

  console.log(`[upgrade/LiquidityHandler] New LiquidityHandler Implementation address: ${newImplementation}`);
  await proxyAdminWrapper.upgrade(liquidityHandler, newImplementation.toString());
  console.log(`[upgrade/LiquidityHandler] Upgraded!`);

  console.log(`[upgrade/LiquidityHandler] Verify contract`);
  await run("verify:verify", {
    address: newImplementation.toString(),
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
