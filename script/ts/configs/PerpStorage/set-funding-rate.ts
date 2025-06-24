import { PerpStorage__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);

  // Example funding rates for different markets
  // You can modify these values as needed
  const marketIndexes = [2, 5, 6, 7, 18, 19, 24]; // Market indexes to update
  const fundingRates = [0, 0, 0, 0, 0, 0, 0]; // Funding rates in basis points (0.1%, -0.05%, 0.2%, 0%, -0.15%)

  const perpStorage = PerpStorage__factory.connect(config.storages.perp, deployer);
  console.log(`[configs/PerpStorage] setFundingRate`);
  console.log(`Market Indexes: [${marketIndexes.join(", ")}]`);
  console.log(`Funding Rates: [${fundingRates.join(", ")}]`);

  await ownerWrapper.authExec(
    perpStorage.address,
    perpStorage.interface.encodeFunctionData("setFundingRate", [marketIndexes, fundingRates])
  );
  console.log("[configs/PerpStorage] Finished");
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
