import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { ethers } from "ethers";
import { IntentBuilder__factory, IntentHandler__factory } from "../../../../typechain";
import { getUpdatePriceData } from "../../utils/price";
import { ecoPythPriceFeedIdsByIndex } from "../../constants/eco-pyth-index";
import chains from "../../entities/chains";
import * as readlineSync from "readline-sync";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const provider = chains[chainId].jsonRpcProvider;
  const signer = signers.deployer(chainId);
  const intentBuilder = IntentBuilder__factory.connect("0xa7D01695B0a5dc8354aD18ed17ac255136cF7543", signer);
  const intentHandler = IntentHandler__factory.connect(config.handlers.intent, signer);

  const account = "0x6629eC35c8Aa279BA45Dbfb575c728d3812aE31a";
  const subAccountId = 0;
  const marketIndex = 0;
  const sizeDelta = ethers.utils.parseUnits("1000000", 30);
  const triggerPrice = 0;
  const acceptablePrice = ethers.utils.parseUnits("5000", 30);
  const triggerAboveThreshold = true;
  const reduceOnly = false;
  const tpToken = config.tokens.usdc;
  const createdTimestamp = (new Date().valueOf() / 1000).toFixed();
  const expiryTimestamp = (new Date().valueOf() / 1000 + 1000).toFixed();

  const tradeOrder = {
    marketIndex,
    sizeDelta,
    triggerPrice,
    acceptablePrice,
    triggerAboveThreshold,
    reduceOnly,
    tpToken,
    createdTimestamp,
    expiryTimestamp,
    account,
    subAccountId,
  };
  const compressedTradeOrder = await intentBuilder.buildTradeOrder(tradeOrder);
  const digest = await intentHandler.getDigest(tradeOrder);
  const privateKey = process.env.MAINNET_PRIVATE_KEY!;
  const rawSignature = new ethers.utils.SigningKey("0x" + privateKey).signDigest(digest);
  const signature = ethers.utils.solidityPack(
    ["bytes32", "bytes32", "uint8"],
    [rawSignature.r, rawSignature.s, rawSignature.v]
  );

  const pk = ethers.utils.recoverPublicKey(digest, signature);
  const recoveredAddress = ethers.utils.computeAddress(ethers.utils.arrayify(pk));

  console.log("recoveredAddress", recoveredAddress);

  const [readableTable, minPublishedTime, priceUpdateData, publishTimeDiffUpdateData, hashedVaas] =
    await getUpdatePriceData(ecoPythPriceFeedIdsByIndex, provider);
  console.table(readableTable);

  const executeInputs = {
    accountAndSubAccountIds: [compressedTradeOrder.accountAndSubAccountId],
    cmds: [compressedTradeOrder.cmd],
    signatures: [signature],
    priceData: priceUpdateData,
    publishTimeData: publishTimeDiffUpdateData,
    minPublishTime: minPublishedTime,
    encodedVaas: hashedVaas,
  };

  const tx = await intentHandler.execute(executeInputs, { gasLimit: 10000000 });
  console.log(`Tx: ${tx.hash}`);
  await tx.wait();
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
