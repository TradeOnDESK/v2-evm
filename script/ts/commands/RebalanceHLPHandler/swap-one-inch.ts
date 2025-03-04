import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { ERC20__factory, RebalanceHLPHandler__factory } from "../../../../typechain";
import { getUpdatePriceData } from "../../utils/price";
import { ecoPythPriceFeedIdsByIndex } from "../../constants/eco-pyth-index";
import chains from "../../entities/chains";
import * as readlineSync from "readline-sync";
import { ethers } from "ethers";
import { OneInchWrapper } from "../../wrappers/OneInchWrapper";
import oneInch from "../../entities/one-inch";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const PARAMS = {
    amountIn: "4.69",
    minAmountOut: "456000",
    path: [config.tokens.wbtc, config.tokens.usdc],
  };

  const chainInfo = chains[chainId];
  const deployer = signers.deployer(chainId);
  const handler = RebalanceHLPHandler__factory.connect(config.handlers.rebalanceHLP, deployer);
  const oneInchWrapper = new OneInchWrapper(chainId, oneInch.baseUrl, oneInch.apiKey);
  const path0Token = ERC20__factory.connect(PARAMS.path[0], deployer);
  const pathLastToken = ERC20__factory.connect(PARAMS.path[PARAMS.path.length - 1], deployer);

  const [path0Symbol, path0Decimals, pathLastSymbol, pathLastDecimals] = await Promise.all([
    path0Token.symbol(),
    path0Token.decimals(),
    pathLastToken.symbol(),
    pathLastToken.decimals(),
  ]);

  console.log(`[commands/RebalanceHLPHandler] Swapping from ${path0Symbol} to ${pathLastSymbol} through OneInch...`);
  const [readableTable, minPublishedTime, priceUpdateData, publishTimeDiffUpdateData, hashedVaas] =
    await getUpdatePriceData(ecoPythPriceFeedIdsByIndex, chainInfo.jsonRpcProvider);
  console.table(readableTable);
  const confirm = readlineSync.question("Confirm to update price feeds? (y/n): ");
  switch (confirm) {
    case "y":
      break;
    case "n":
      console.log("Feed Price cancelled!");
      return;
    default:
      console.log("Invalid input!");
      return;
  }

  console.log(`[commands/RebalanceHLPHandler] Getting swap data from OneInch...`);
  const oneInchData = await oneInchWrapper.getSwapData(
    config.services.rebalanceHLP,
    PARAMS.path[0],
    PARAMS.path[PARAMS.path.length - 1],
    ethers.utils.parseUnits(PARAMS.amountIn, path0Decimals).toString(),
    25
  );
  console.log(`[commands/RebalanceHLPHandler] Received swap data from OneInch`);

  console.log(`[commands/RebalanceHLPHandler] Calling the handler...`);
  const tx = await handler.oneInchSwap(
    {
      amountIn: ethers.utils.parseUnits(PARAMS.amountIn, path0Decimals),
      minAmountOut: ethers.utils.parseUnits(PARAMS.minAmountOut, pathLastDecimals),
      path: PARAMS.path,
    },
    oneInchData.tx.data,
    priceUpdateData,
    publishTimeDiffUpdateData,
    minPublishedTime,
    hashedVaas
  );
  console.log(`[commands/RebalanceHLPHandler] Tx: ${tx.hash}`);
}

const program = new Command();

program.requiredOption("--chain-id <chainId>", "chain id", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
