import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { CrossMarginHandler__factory } from "../../../../typechain";
import { ethers } from "ethers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const signer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, signer);

  const subAccountId = 0;
  const token = config.tokens.deskUsdc;
  const amount = ethers.utils.parseUnits("10", 6);
  const shouldWrap = false;
  const isMigrateToDESK = true;

  console.log("[commands/CrossMarginHandler] withdrawCollateral...");
  const handler = CrossMarginHandler__factory.connect(config.handlers.crossMargin, signer);
  const executionFee = await handler.minExecutionOrderFee();
  const tx = await handler["createWithdrawCollateralOrder(uint8,address,uint256,uint256,bool,bool)"](
    subAccountId,
    token,
    amount,
    executionFee,
    shouldWrap,
    isMigrateToDESK,
    { value: executionFee }
  );
  console.log(`[CrossMarginHandler] Tx: ${tx.hash}`);
  await tx.wait(1);
  console.log("[CrossMarginHandler] Finished");
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
