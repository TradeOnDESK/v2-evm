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

  console.log(`[cmds/VaultStorage] Clear on hold for ${tokenSymbol}...`);
  console.log(`[cmds/VaultStorage] Token: ${token.address}`);
  console.log(`[cmds/VaultStorage] Amount: ${amount} ${tokenSymbol} (${amountBN.toString()})`);

  const vaultStorage = VaultStorage__factory.connect(config.storages.vault, signer);

  // Check current on hold amount
  const currentOnHold = await vaultStorage.hlpLiquidityOnHold(token.address);
  console.log(
    `[cmds/VaultStorage] Current on hold amount: ${ethers.utils.formatUnits(
      currentOnHold,
      token.decimals
    )} ${tokenSymbol}`
  );

  if (currentOnHold.lt(amountBN)) {
    console.error(
      `[cmds/VaultStorage] Insufficient on hold amount. Available: ${ethers.utils.formatUnits(
        currentOnHold,
        token.decimals
      )} ${tokenSymbol}`
    );
    process.exit(1);
  }

  // Check current total amount
  const currentTotalAmount = await vaultStorage.totalAmount(token.address);
  console.log(
    `[cmds/VaultStorage] Current total amount: ${ethers.utils.formatUnits(
      currentTotalAmount,
      token.decimals
    )} ${tokenSymbol}`
  );

  const confirm = readlineSync.question("Confirm to clear on hold amount? (y/n): ");
  switch (confirm.toLowerCase()) {
    case "y":
      break;
    case "n":
      console.log("Clear on hold cancelled!");
      return;
    default:
      console.log("Invalid input!");
      return;
  }

  const tx = await safeWrapper.proposeTransaction(
    vaultStorage.address,
    0,
    vaultStorage.interface.encodeFunctionData("clearOnHold", [token.address, amountBN]),
    { nonce }
  );

  console.log(`[cmds/VaultStorage] Proposed tx to clear ${amount} ${tokenSymbol} on hold: ${tx}`);
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
