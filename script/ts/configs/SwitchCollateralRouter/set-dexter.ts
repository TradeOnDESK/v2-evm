import { Command } from "commander";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { SwitchCollateralRouter__factory } from "../../../../typechain";

type SetDexter = {
  tokenIn: string;
  tokenOut: string;
  dexter: string;
};

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);
  const swithCollateralRouter = SwitchCollateralRouter__factory.connect(
    config.extension.switchCollateralRouter,
    deployer
  );
  const params: Array<SetDexter> = [
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.usdt,
      dexter: config.extension.dexter.curve,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.dai,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.wbtc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.weth,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.arb,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.sglp,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.usdt,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.curve,
    },
    {
      tokenIn: config.tokens.dai,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.wbtc,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.arb,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.sglp,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.usdt,
      tokenOut: config.tokens.weth,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.usdt,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.dai,
      tokenOut: config.tokens.sglp,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.sglp,
      tokenOut: config.tokens.dai,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.wbtc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.arb,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.sglp,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.wbtc,
      tokenOut: config.tokens.weth,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.arb,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.sglp,
      tokenOut: config.tokens.weth,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.wbtc,
      tokenOut: config.tokens.sglp,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.sglp,
      tokenOut: config.tokens.wbtc,
      dexter: config.extension.dexter.glp,
    },
    {
      tokenIn: config.tokens.wstEth,
      tokenOut: config.tokens.weth,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.wstEth,
      tokenOut: config.tokens.usdc,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.weth,
      tokenOut: config.tokens.wstEth,
      dexter: config.extension.dexter.uniswapV3,
    },
    {
      tokenIn: config.tokens.usdc,
      tokenOut: config.tokens.wstEth,
      dexter: config.extension.dexter.uniswapV3,
    },
  ];

  console.log("[cmds/SwitchCollateralRouter] Setting dexter ...");
  for (let i = 0; i < params.length; i++) {
    const tx = await swithCollateralRouter.setDexterOf(params[i].tokenIn, params[i].tokenOut, params[i].dexter, {
      gasLimit: 10000000,
    });
    console.log(
      `[cmds/SwitchCollateralRouter] Tx - Set Dexter of (${params[i].tokenIn}, ${params[i].tokenOut}): ${tx.hash}`
    );
    await tx.wait(1);
  }
  console.log("[cmds/SwitchCollateralRouter] Finished");
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
