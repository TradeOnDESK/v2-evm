import { LiquidityHandler__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  const dlp = config.tokens.dlp;

  const liquidityHandler = LiquidityHandler__factory.connect(config.handlers.liquidity, deployer);
  console.log(`[configs/LiquidityHandler] Set DLP`);
  await ownerWrapper.authExec(liquidityHandler.address, liquidityHandler.interface.encodeFunctionData("setDlp", [dlp]));
  console.log("[configs/LiquidityHandler] Finished");
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
