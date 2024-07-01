import { ConfigStorage__factory } from "../../../../typechain";
import { loadConfig, loadMarketConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ethers } from "ethers";
import * as readlineSync from "readline-sync";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const marketConfig = loadMarketConfig(chainId);

  const inputs = [
    {
      marketIndex: 0,
      imfBps: 200,
      maxProfitRateBps: 200000,
    },
  ];

  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);
  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);

  const currentMarketConfigs = await configStorage.getMarketConfigs();

  console.log("[config/ConfigStorage] Set Market IMF and Max Profits...");
  console.table(
    inputs.map((e) => {
      const existingImfBps = (currentMarketConfigs[e.marketIndex].initialMarginFractionBPS / 1e4) * 100;
      const existingMaxProfitRateBps = (currentMarketConfigs[e.marketIndex].maxProfitRateBPS / 1e4) * 100;
      const newImfBps = (e.imfBps / 1e4) * 100;
      const newMaxProfitRateBps = (e.maxProfitRateBps / 1e4) * 100;
      return {
        marketIndex: e.marketIndex,
        marketName: marketConfig.markets[e.marketIndex].name,
        existingImfBps: existingImfBps + "%",
        newImfBps: newImfBps + "%",
        existingMaxLeverage: 100 / existingImfBps,
        newMaxLeverage: 100 / newImfBps,
        existingMaxProfitRateBps: existingMaxProfitRateBps + "%",
        maxProfitRateBps: newMaxProfitRateBps + "%",
      };
    })
  );
  const confirm = readlineSync.question(`[configs/ConfigStorage] Confirm to update IMF and Max Profit Rate? (y/n): `);
  switch (confirm) {
    case "y":
      break;
    case "n":
      console.log("[configs/ConfigStorage] Set IMF and Max Profit Rate cancelled!");
      return;
    default:
      console.log("[configs/ConfigStorage] Invalid input!");
      return;
  }
  await ownerWrapper.authExec(
    configStorage.address,
    configStorage.interface.encodeFunctionData("setMarketIMFAndMaxProfit", [
      inputs.map((e) => e.marketIndex),
      inputs.map((e) => e.imfBps),
      inputs.map((e) => e.maxProfitRateBps),
    ])
  );
  console.log("[config/ConfigStorage] Done");
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

const opts = prog.parse(process.argv).opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
