import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const minExecutionFee = ethers.utils.parseEther("0.0003"); // 0.0003 ether
const minExecutionTimestamp = 60 * 60 * 5; // 5 minutes

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("LimitTradeHandler", deployer);
  const contract = await upgrades.deployProxy(
    Contract,
    [config.tokens.weth, config.services.trade, config.oracles.ecoPyth, minExecutionFee, minExecutionTimestamp],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  await contract.deployed();
  console.log(`Deploying LimitTradeHandler Contract`);
  console.log(`Deployed at: ${contract.address}`);

  config.handlers.limitTrade = contract.address;
  writeConfigFile(config);

  await tenderly.verify({
    address: await getImplementationAddress(network.provider, contract.address),
    name: "LimitTradeHandler",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
