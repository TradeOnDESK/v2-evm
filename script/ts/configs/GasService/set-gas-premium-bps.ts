import { GasService__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  const gasPremiumBps = 1000; // 10%

  const gasService = GasService__factory.connect(config.services.gas, deployer);
  console.log(`[configs/GasService] Set Gas Premium Bps`);
  await ownerWrapper.authExec(
    gasService.address,
    gasService.interface.encodeFunctionData("setGasPremiumBps", [gasPremiumBps])
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
