import { GasService__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ethers } from "ethers";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  const valueToAdd = ethers.utils.parseUnits("8500", "30");

  const gasService = GasService__factory.connect(config.services.gas, deployer);
  console.log(
    `[configs/GasService] adjustSubsidizedExecutionFeeValue for ${ethers.utils.formatUnits(valueToAdd, 30)} USD`
  );
  await ownerWrapper.authExec(
    gasService.address,
    gasService.interface.encodeFunctionData("adjustSubsidizedExecutionFeeValue", [valueToAdd])
  );
  console.log("[configs/GasService] Finished");
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
