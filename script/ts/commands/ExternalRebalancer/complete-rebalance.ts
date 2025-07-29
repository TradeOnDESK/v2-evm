import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { ExternalRebalancer__factory } from "../../../../typechain";
import * as readlineSync from "readline-sync";
import { ethers } from "ethers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ERC20__factory } from "../../../../typechain";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);

  const tokenToRemove = config.tokens.wusdm;
  const replacementToken = config.tokens.usdcNative;
  const replacementAmount = ethers.utils.parseUnits("1000000", 6);

  console.log(`[cmds/ExternalRebalancer] Completing rebalance on chain ${chainId}...`);
  console.log(`[cmds/ExternalRebalancer] Token to remove (on-hold): ${tokenToRemove}`);
  console.log(`[cmds/ExternalRebalancer] Replacement token: ${replacementToken}`);
  console.log(`[cmds/ExternalRebalancer] Replacement amount: ${replacementAmount}`);

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

  // Check and approve token allowance for the replacement token
  console.log(`[cmds/ExternalRebalancer] Checking token allowance...`);
  const replacementTokenContract = ERC20__factory.connect(replacementToken, deployer);
  const signerAddress = await deployer.getAddress();
  const allowance = await replacementTokenContract.allowance(signerAddress, externalRebalancer.address);

  if (allowance.lt(replacementAmount)) {
    console.log(`[cmds/ExternalRebalancer] Approving ${ethers.utils.formatUnits(replacementAmount, 6)} USDC...`);
    const approveTx = await replacementTokenContract.approve(externalRebalancer.address, replacementAmount);
    await approveTx.wait();
    console.log(`[cmds/ExternalRebalancer] Token approval completed.`);
  } else {
    console.log(`[cmds/ExternalRebalancer] Sufficient allowance already exists.`);
  }

  console.log(`[cmds/ExternalRebalancer] Executing completeRebalance...`);
  await ownerWrapper.authExec(
    externalRebalancer.address,
    externalRebalancer.interface.encodeFunctionData("completeRebalance", [
      tokenToRemove,
      replacementToken,
      replacementAmount,
    ])
  );

  console.log(`[cmds/ExternalRebalancer] Rebalance completed successfully on chain ${chainId}.`);
  console.log(`[cmds/ExternalRebalancer] Cleared on-hold tokens: ${tokenToRemove}`);
  console.log(`[cmds/ExternalRebalancer] Added replacement tokens: ${replacementAmount} ${replacementToken}`);
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
