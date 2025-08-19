import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ethers } from "hardhat";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  // The executor address to whitelist
  const whitelistedExecutor = "0x6a5D2BF8ba767f7763cd342Cb62C5076f9924872"; // Update this address as needed

  const externalRebalancer = await ethers.getContractFactory("ExternalRebalancer", deployer);
  const externalRebalancerContract = externalRebalancer.attach(config.handlers.externalRebalancer);

  console.log(`[configs/ExternalRebalancer] Set Whitelisted Executor`);
  console.log(`[configs/ExternalRebalancer] Executor: ${whitelistedExecutor}`);

  await ownerWrapper.authExec(
    externalRebalancerContract.address,
    externalRebalancerContract.interface.encodeFunctionData("addWhitelistedExecutor", [whitelistedExecutor])
  );

  console.log("[configs/ExternalRebalancer] Finished");
}

const prog = new Command();

prog.requiredOption("--chain-id <number>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
