import { ethers } from "ethers";
import { EcoPyth__factory } from "../../../../typechain";
import signers from "../../entities/signers";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

const ASSET_IDS = [ethers.utils.formatBytes32String("CRCL")];

async function main(chainId: number) {
  const deployer = signers.deployer(chainId);
  const config = loadConfig(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  const ecoPyth = EcoPyth__factory.connect(config.oracles.ecoPyth2, deployer);
  console.log("[configs/EcoPyth] Inserting asset IDs...");
  await ownerWrapper.authExec(ecoPyth.address, ecoPyth.interface.encodeFunctionData("insertAssetIds", [ASSET_IDS]));
}

const program = new Command();

program.requiredOption("--chain-id <chainId>", "chain id", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
