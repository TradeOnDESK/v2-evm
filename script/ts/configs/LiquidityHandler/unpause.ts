import { LiquidityHandler__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  const liquidityHandler = LiquidityHandler__factory.connect(config.handlers.liquidity, deployer);
  console.log(`[configs/LiquidityHandler] Unpause LiquidityHandler`);
  await ownerWrapper.authExec(liquidityHandler.address, liquidityHandler.interface.encodeFunctionData("unpause", []));
  console.log("[configs/LiquidityHandler] LiquidityHandler unpaused successfully");
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
