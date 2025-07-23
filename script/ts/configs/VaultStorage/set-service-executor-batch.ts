import { VaultStorage__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { Command } from "commander";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const inputs = [
    {
      executorAddress: "0x6409ba830719cd0fE27ccB3051DF1b399C90df4a",
      isServiceExecutor: true,
    },
  ];

  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);
  const vaultStorage = VaultStorage__factory.connect(config.storages.vault, deployer);

  console.log("[configs/VaultStorage] Set the service executors...");
  await ownerWrapper.authExec(
    vaultStorage.address,
    vaultStorage.interface.encodeFunctionData("setServiceExecutorBatch", [
      inputs.map((each) => each.executorAddress),
      inputs.map((each) => each.isServiceExecutor),
    ])
  );
  console.log(`[configs/VaultStorage] Done`);
}

const program = new Command();

program.requiredOption("--chain-id <chain-id>", "chain id", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
