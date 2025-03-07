import { ConfigStorage__factory } from "../../../../typechain";
import { loadConfig, loadMarketConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ethers } from "ethers";
import * as readlineSync from "readline-sync";
import { numberWithCommas } from "../../utils/number";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const marketConfig = loadMarketConfig(chainId);

  const inputs = [
    {
      marketIndex: 0,
      maxLongPositionSize: 1_000_000,
      maxShortPositionSize: 1_000_000,
    },
    {
      marketIndex: 1,
      maxLongPositionSize: 1_000_000,
      maxShortPositionSize: 1_000_000,
    },
    // {
    //   marketIndex: 23,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 25,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 44,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 15,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 16,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 50,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
    // {
    //   marketIndex: 20,
    //   maxLongPositionSize: 50_000,
    //   maxShortPositionSize: 50_000,
    // },
    // {
    //   marketIndex: 51,
    //   maxLongPositionSize: 20_000,
    //   maxShortPositionSize: 20_000,
    // },
  ];

  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);
  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);

  const currentMarketConfigs = await configStorage.getMarketConfigs();

  console.log("[configs/ConfigStorage] Set Market Max OIs...");
  for (let i = 0; i < inputs.length; i++) {
    const each = inputs[i];
    const existingMaxLongPositionSize = Number(
      ethers.utils.formatUnits(currentMarketConfigs[each.marketIndex].maxLongPositionSize, 30)
    );
    const existingMaxShortPositionSize = Number(
      ethers.utils.formatUnits(currentMarketConfigs[each.marketIndex].maxShortPositionSize, 30)
    );
    console.table({
      existing: {
        marketIndex: each.marketIndex,
        marketName: marketConfig.markets[each.marketIndex].name,
        maxLongPositionSize: numberWithCommas(existingMaxLongPositionSize),
        maxShortPositionSize: numberWithCommas(existingMaxShortPositionSize),
      },
      newOne: {
        marketIndex: each.marketIndex,
        marketName: marketConfig.markets[each.marketIndex].name,
        maxLongPositionSize: numberWithCommas(each.maxLongPositionSize),
        maxShortPositionSize: numberWithCommas(each.maxShortPositionSize),
      },
    });
  }
  const confirm = readlineSync.question(`[configs/ConfigStorage] Confirm to update Max OIs? (y/n): `);
  switch (confirm) {
    case "y":
      break;
    case "n":
      console.log("[configs/ConfigStorage] Set Max OIs cancelled!");
      return;
    default:
      console.log("[configs/ConfigStorage] Invalid input!");
      return;
  }
  const tx = await configStorage.setMarketMaxOI(
    inputs.map((e) => e.marketIndex),
    inputs.map((e) => ethers.utils.parseUnits(e.maxLongPositionSize.toString(), 30)),
    inputs.map((e) => ethers.utils.parseUnits(e.maxShortPositionSize.toString(), 30))
  );
  console.log(`[config/ConfigStorage] Tx: ${tx.hash}`);
  await tx.wait();
  console.log("[config/ConfigStorage] Done");
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

const opts = prog.parse(process.argv).opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
