import { ethers } from "ethers";
import { OracleMiddleware__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { Command } from "commander";
import SafeWrapper from "../../wrappers/SafeWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const assetConfigs = [
    {
      assetId: ethers.utils.formatBytes32String("CRCL"),
      confidenceThreshold: 0,
      trustPriceAge: 60 * 60 * 24 * 3, // 3 days
      adapter: config.oracles.pythAdapter,
    },
  ];

  const deployer = signers.deployer(chainId);
  const safeWrapper = new SafeWrapper(chainId, config.safe, deployer);
  const oracle = OracleMiddleware__factory.connect(config.oracles.middleware, deployer);

  console.log("[configs/OracleMiddleware] Setting asset price configs...");
  const tx = await safeWrapper.proposeTransaction(
    oracle.address,
    0,
    oracle.interface.encodeFunctionData("setAssetPriceConfigs", [
      assetConfigs.map((each) => each.assetId),
      assetConfigs.map((each) => each.confidenceThreshold),
      assetConfigs.map((each) => each.trustPriceAge),
      assetConfigs.map((each) => each.adapter),
    ])
  );
  console.log(`[configs/OracleMiddleware] Tx: ${tx}`);
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
