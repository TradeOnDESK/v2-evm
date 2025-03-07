import { ConfigStorage__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import { OwnerWrapper } from "../../wrappers/OwnerWrapper";
import { ethers } from "ethers";

async function main(chainId: number) {
  const config = loadConfig(chainId);

  const inputs = [
    {
      index: 0,
      fromSize: 0,
      toSize: ethers.constants.MaxUint256,
      minProfitDuration: 0,
    },
  ];

  const deployer = signers.deployer(chainId);
  const ownerWrapper = new OwnerWrapper(chainId, deployer);
  const configStorage = ConfigStorage__factory.connect(config.storages.config, deployer);

  console.log("[config/ConfigStorage] Set Step Min Profit Duration...");
  console.table(
    inputs.map((each) => {
      return {
        ...each,
        fromSize: ethers.utils.formatUnits(each.fromSize, 30),
        toSize: ethers.utils.formatUnits(each.toSize, 30),
      };
    })
  );
  await ownerWrapper.authExec(
    configStorage.address,
    configStorage.interface.encodeFunctionData("setStepMinProfitDuration", [inputs.map((e) => e.index), inputs])
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
