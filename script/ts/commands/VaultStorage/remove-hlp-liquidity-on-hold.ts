import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { VaultStorage__factory } from "../../../../typechain";
import { ethers } from "ethers";
import * as readlineSync from "readline-sync";
import SafeWrapper from "../../wrappers/SafeWrapper";
import collaterals from "../../entities/collaterals";

async function main(chainId: number, nonce?: number) {
  const config = loadConfig(chainId);
  const signer = signers.deployer(chainId);
  const safeWrapper = new SafeWrapper(chainId, config.safe, signer);

  const tokenSymbol = "WUSDM";
  const amount = "160302284185048040369364";

  // Validate token symbol
  if (!collaterals[tokenSymbol]) {
    console.error(`[cmds/VaultStorage] Invalid token symbol: ${tokenSymbol}`);
    console.error(`[cmds/VaultStorage] Available tokens: ${Object.keys(collaterals).join(", ")}`);
    process.exit(1);
  }

  const token = collaterals[tokenSymbol];
  const amountBN = ethers.utils.parseUnits(amount, token.decimals);

  console.log(`[cmds/VaultStorage] Remove HLP liquidity on hold for ${tokenSymbol}...`);
  console.log(`[cmds/VaultStorage] Token: ${token.address}`);
  console.log(`[cmds/VaultStorage] Amount: ${amount} ${tokenSymbol} (${amountBN.toString()})`);

  const vaultStorage = VaultStorage__factory.connect(config.storages.vault, signer);

  // Check current HLP liquidity
  const currentHLPLiquidity = await vaultStorage.hlpLiquidity(token.address);
  console.log(
    `[cmds/VaultStorage] Current HLP liquidity: ${ethers.utils.formatUnits(
      currentHLPLiquidity,
      token.decimals
    )} ${tokenSymbol}`
  );

  if (currentHLPLiquidity.lt(amountBN)) {
    console.error(
      `[cmds/VaultStorage] Insufficient HLP liquidity. Available: ${ethers.utils.formatUnits(
        currentHLPLiquidity,
        token.decimals
      )} ${tokenSymbol}`
    );
    process.exit(1);
  }

  const confirm = readlineSync.question("Confirm to remove HLP liquidity on hold? (y/n): ");
  switch (confirm.toLowerCase()) {
    case "y":
      break;
    case "n":
      console.log("Remove HLP liquidity on hold cancelled!");
      return;
    default:
      console.log("Invalid input!");
      return;
  }

  const tx = await safeWrapper.proposeTransaction(
    vaultStorage.address,
    0,
    vaultStorage.interface.encodeFunctionData("removeHLPLiquidityOnHold", [token.address, amountBN]),
    { nonce }
  );

  console.log(`[cmds/VaultStorage] Proposed tx to remove ${amount} ${tokenSymbol} HLP liquidity on hold: ${tx}`);
  console.log("[cmds/VaultStorage] Finished");
}

const program = new Command();

program.requiredOption("--chain-id <chain-id>", "chain id", parseInt);
program.option("--nonce <nonce>", "nonce", parseInt);

const opts = program.parse(process.argv).opts();

main(opts.chainId, opts.nonce)
  .then(() => {
    process.exit(0);
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
