import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin-4.8.1/upgrades-core";
import { Calculator__factory, PerpStorage__factory } from "../../../../typechain";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const perpStorage = PerpStorage__factory.connect(config.storages.perp, deployer);
  const calculator = Calculator__factory.connect(config.calculator, deployer);

  const numberOfMarket = 5;
  const marketName = ["ETH", "BTC", "AAPL", "JPY", "XAU"];
  for (let i = 0; i < numberOfMarket; i++) {
    const market = await perpStorage.getMarketByIndex(i);
    const fundingRateVelocity = await calculator.getFundingRateVelocity(i);
    console.log(`Market: ${marketName[i]}`);
    console.log(`1H Funding Rate: ${ethers.utils.formatUnits(market.currentFundingRate.div(24).mul(100), 18)}%`);
    console.log(`1H Funding Rate Velocity: ${ethers.utils.formatUnits(fundingRateVelocity.div(24).mul(100), 18)}%`);
    console.log(`Long Unrealized Funding Fee: ${ethers.utils.formatUnits(market.accumFundingLong, 30)} USD`);
    console.log(`Short Unrealized Funding Fee: ${ethers.utils.formatUnits(market.accumFundingShort, 30)} USD`);
    console.log();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
