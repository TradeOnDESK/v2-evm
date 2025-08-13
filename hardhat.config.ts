import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import fs from "fs";
dotEnvConfig();

import * as tdly from "@tenderly/hardhat-tenderly";
tdly.setup({ automaticVerifications: false });

import "@openzeppelin/hardhat-upgrades";
import "hardhat-preprocessor";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-verify";

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => line.trim().split("="));
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    tenderly: {
      url: process.env.TENDERLY_RPC || "",
      accounts: process.env.MAINNET_PRIVATE_KEY !== undefined ? [process.env.MAINNET_PRIVATE_KEY] : [],
    },
    arbitrum: {
      url: process.env.ARBITRUM_MAINNET_RPC || "",
      accounts: [process.env.MAINNET_PRIVATE_KEY || ""],
    },
    arb_goerli: {
      url: process.env.ARBITRUM_GOERLI_RPC || "",
      chainId: 421613,
      accounts: process.env.MAINNET_PRIVATE_KEY !== undefined ? [process.env.MAINNET_PRIVATE_KEY] : [],
    },
    arb_sepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC || "",
      chainId: 421614,
      accounts: process.env.MAINNET_PRIVATE_KEY !== undefined ? [process.env.MAINNET_PRIVATE_KEY] : [],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "./typechain",
    target: "ethers-v5",
  },
  tenderly: {
    project: process.env.TENDERLY_PROJECT_NAME!,
    username: process.env.TENDERLY_USERNAME!,
    privateVerification: true,
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY!,
      arbitrumGoerli: process.env.ARBISCAN_API_KEY!,
      arbitrumSepolia: process.env.ARBISCAN_API_KEY!,
      blastSepolia: process.env.ETHERSCAN_API_KEY!,
      blast: process.env.BLASTSCAN_API_KEY!,
    },
    customChains: [
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.blastscan.io/api",
          browserURL: "https://www.blastscan.io",
        },
      },
      {
        network: "blastSepolia",
        chainId: 168587773,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan",
          browserURL: "https://testnet.blastscan.io",
        },
      },
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io/",
        },
      },
    ],
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string, sourceInfo: { absolutePath: string }) => {
        const path = sourceInfo.absolutePath;
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match(find)) {
              if (path.includes("5.4.0") && line.includes("openzeppelin")) {
                line = line.replace(find, replace.slice(0, -1) + "-5.4.0/");
              } else {
                line = line.replace(find, replace);
              }
            }
          });
        }
        return line;
      },
    }),
  },
};

export default config;
