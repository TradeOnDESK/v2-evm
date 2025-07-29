import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { ExternalRebalancer__factory } from "../../../../typechain";
import * as readlineSync from "readline-sync";
import { ethers } from "ethers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);

  const tokenToRemove = config.tokens.wusdm;
  const amountToRemove = ethers.utils.parseUnits("1000000", 18);
  const recipient = "0x6a5D2BF8ba767f7763cd342Cb62C5076f9924872";

  console.log(`[cmds/ExternalRebalancer] Starting rebalance on chain ${chainId}...`);
  console.log(`[cmds/ExternalRebalancer] Token to remove: ${tokenToRemove}`);
  console.log(`[cmds/ExternalRebalancer] Amount to remove: ${amountToRemove}`);
  console.log(`[cmds/ExternalRebalancer] Recipient: ${recipient}`);

  const confirm = readlineSync.question("[cmds/ExternalRebalancer] Confirm (Y/N): ");
  switch (confirm) {
    case "Y":
    case "y":
      break;
    default:
      console.log("[cmds/ExternalRebalancer] Cancelled.");
      return;
  }

  const externalRebalancer = ExternalRebalancer__factory.connect(config.services.externalRebalancer, deployer);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  // Check if the caller is whitelisted
  console.log(`[cmds/ExternalRebalancer] Checking if caller is whitelisted...`);
  const deployerAddress = await deployer.getAddress();
  const isWhitelisted = await externalRebalancer.whitelistedExecutors(deployerAddress);
  if (!isWhitelisted) {
    console.log(`[cmds/ExternalRebalancer] Caller is not whitelisted. Adding to whitelist...`);
    await ownerWrapper.authExec(
      externalRebalancer.address,
      externalRebalancer.interface.encodeFunctionData("addWhitelistedExecutor", [deployerAddress])
    );
    console.log(`[cmds/ExternalRebalancer] Caller added to whitelist.`);
  }

  console.log(`[cmds/ExternalRebalancer] Executing startRebalance...`);
  await ownerWrapper.authExec(
    externalRebalancer.address,
    externalRebalancer.interface.encodeFunctionData("startRebalance", [tokenToRemove, amountToRemove, recipient])
  );

  console.log(`[cmds/ExternalRebalancer] Rebalance started successfully on chain ${chainId}.`);
  console.log(`[cmds/ExternalRebalancer] Removed ${amountToRemove} tokens from HLP liquidity and put on hold.`);
  console.log(`[cmds/ExternalRebalancer] Tokens transferred to: ${recipient}`);
}

const program = new Command();

program.requiredOption("--chain-id <chain-id>", "chain id", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
