// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { OracleMiddleware } from "@hmx/oracles/OracleMiddleware.sol";
import { PythAdapter } from "@hmx/oracles/PythAdapter.sol";
import { IERC20 } from "@openzeppelin-4.8.1/contracts/token/ERC20/IERC20.sol";
import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";
import { StakedGlpOracleAdapter } from "@hmx/oracles/StakedGlpOracleAdapter.sol";

abstract contract Deployment {
  struct DeployReturnVars {
    OracleMiddleware oracleMiddleware;
  }

  function deploy() internal returns (DeployReturnVars memory) {
    DeployReturnVars memory vars;

    vars.oracleMiddleware = new OracleMiddleware();

    return vars;
  }
}
