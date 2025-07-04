import { EcoPyth__factory } from "../../../../typechain";
import { ecoPythAssetIdByIndex, ecoPythPriceFeedIdsByIndex } from "../../constants/eco-pyth-index";
import * as readlineSync from "readline-sync";
import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import { getUpdatePriceData } from "../../utils/price";
import signers from "../../entities/signers";
import chains from "../../entities/chains";
import HmxApiWrapper from "../../wrappers/HMXApiWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const provider = chains[chainId].jsonRpcProvider;
  const deployer = signers.deployer(chainId);
  const hmxApi = new HmxApiWrapper(chainId);

  const pyth = EcoPyth__factory.connect(config.oracles.ecoPyth2, deployer);

  const [readableTable, minPublishedTime, priceUpdateData, publishTimeDiffUpdateData, hashedVaas] =
    await getUpdatePriceData(ecoPythPriceFeedIdsByIndex, provider);
  console.table(readableTable);
  const confirm = readlineSync.question(`[cmds/EcoPyth] Confirm to update price feeds? (y/n): `);
  switch (confirm) {
    case "y":
      break;
    case "n":
      console.log("[cmds/EcoPyth] Feed Price cancelled!");
      return;
    default:
      console.log("[cmds/EcoPyth] Invalid input!");
      return;
  }

  console.log("[cmds/EcoPyth] Feed Price...");
  const tx = await (
    await pyth.updatePriceFeeds(priceUpdateData, publishTimeDiffUpdateData, minPublishedTime, hashedVaas)
  ).wait();
  console.log(`[cmds/EcoPyth] Done: ${tx.transactionHash}`);
  console.log("[cmds/EcoPyth] Feed Price success!");
  // console.log("[cmds/EcoPyth] Refreshing Asset Ids at HMX API...");
  // await hmxApi.refreshAssetIds();
  // console.log("[cmds/EcoPyth] Success!");
  // console.log("[cmds/EcoPyth] Refreshing Market Ids at HMX API...");
  // await hmxApi.refreshMarketIds();
  // console.log("[cmds/EcoPyth] Success!");
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
