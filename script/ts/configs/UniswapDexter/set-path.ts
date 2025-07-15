import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { UniswapDexter__factory } from "../../../../typechain";
import { ethers } from "ethers";

type SetPathConfig = {
  tokenIn: string;
  tokenOut: string;
  path: string;
};

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const dexter = UniswapDexter__factory.connect(config.extension.dexter.uniswapV3, deployer);

  const params: Array<SetPathConfig> = [
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdc, 100, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.usdc,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 100, config.tokens.usdc]
      ),
    },
    {
      tokenIn: config.tokens.usdt,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdt, 100, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.usdt,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 100, config.tokens.usdt]
      ),
    },
    {
      tokenIn: config.tokens.dai,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.dai, 100, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.dai,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 100, config.tokens.dai]
      ),
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.weth, 500, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.weth,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 500, config.tokens.weth]
      ),
    },
    {
      tokenIn: config.tokens.wbtc,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.wbtc, 3000, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.wbtc,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 3000, config.tokens.wbtc]
      ),
    },
    {
      tokenIn: config.tokens.arb,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.arb, 500, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.arb,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 500, config.tokens.arb]
      ),
    },
    {
      tokenIn: config.tokens.wusdm,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.wusdm, 500, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.wusdm,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address"],
        [config.tokens.usdcNative, 500, config.tokens.wusdm]
      ),
    },
    {
      tokenIn: config.tokens.link,
      tokenOut: config.tokens.usdcNative,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address", "uint24", "address"],
        [config.tokens.link, 500, config.tokens.weth, 500, config.tokens.usdcNative]
      ),
    },
    {
      tokenIn: config.tokens.usdcNative,
      tokenOut: config.tokens.link,
      path: ethers.utils.solidityPack(
        ["address", "uint24", "address", "uint24", "address"],
        [config.tokens.usdcNative, 500, config.tokens.weth, 500, config.tokens.link]
      ),
    },
  ];

  console.log("[cmds/UniswapDexter] Setting path config...");
  for (let i = 0; i < params.length; i++) {
    console.log(params[i].path);
    const tx = await dexter.setPathOf(params[i].tokenIn, params[i].tokenOut, params[i].path, {
      gasLimit: 10000000,
    });
    console.log(`[cmds/UniswapDexter] Tx - Set Path of (${params[i].tokenIn}, ${params[i].tokenOut}): ${tx.hash}`);
    await tx.wait(1);
  }

  console.log("[cmds/UniswapDexter] Finished");
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
