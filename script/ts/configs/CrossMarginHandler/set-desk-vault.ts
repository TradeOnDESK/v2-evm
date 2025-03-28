import signers from "../../entities/signers";
import { Command } from "commander";
import { CrossMarginHandler__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);

  console.log("[configs/CrossMarginHandler] Set DESK Vault");
  const crossMarginHandler = CrossMarginHandler__factory.connect(config.handlers.crossMargin, deployer);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);
  await ownerWrapper.authExec(
    crossMarginHandler.address,
    crossMarginHandler.interface.encodeFunctionData("setDESKVault", [config.vendors.desk.vault])
  );
  console.log("[configs/CrossMarginHandler] Done");
}

const program = new Command();

program.requiredOption("--chain-id <chain-id>", "Chain ID", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
