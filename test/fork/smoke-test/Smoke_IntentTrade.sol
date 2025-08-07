// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Test } from "forge-std/Test.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";
import { ProxyAdmin } from "@openzeppelin-4.8.1/contracts/proxy/transparent/ProxyAdmin.sol";
import { Deployer, IIntentHandler, IGasService } from "@hmx-test/libs/Deployer.sol";
import { OnChainPriceLens } from "@hmx/oracles/OnChainPriceLens.sol";
import { CalcPriceLens } from "@hmx/oracles/CalcPriceLens.sol";
import { UnsafeEcoPythCalldataBuilder3 } from "@hmx/oracles/UnsafeEcoPythCalldataBuilder3.sol";
import { ForkEnv, OrderbookOracle, AdaptiveFeeCalculator } from "@hmx-test/fork/bases/ForkEnv.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";
import { IntentBuilder } from "@hmx-test/libs/IntentBuilder.sol";
import { console } from "forge-std/console.sol";

contract Smoke_IntentTrade is ForkEnv {
  int64[] priceE8s;

  function setUp() external {
    // vm.txGasPrice(10000000); // 0.01 GWEI
  }

  function test() external {
    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"), 214327844);

    vm.startPrank(ForkEnv.multiSig);
    Deployer.upgrade("GasService", address(ForkEnv.proxyAdmin), 0xe54f0C6cD09617c5fC73647A0303AB35789a23Be);
    Deployer.upgrade("IntentHandler", address(ForkEnv.proxyAdmin), 0xA5b749203967e3ddF48006a7d7C258E59Ac07A96);
    IGasService gasService = IGasService(0xe54f0C6cD09617c5fC73647A0303AB35789a23Be);
    gasService.setGasTokenAssetId("ETH");
    vm.stopPrank();

    IIntentHandler intentHandler = IIntentHandler(0xA5b749203967e3ddF48006a7d7C258E59Ac07A96);

    // Trade
    IIntentHandler.ExecuteIntentInputs memory executeIntentInputs;
    executeIntentInputs.accountAndSubAccountIds = new bytes32[](1);
    executeIntentInputs.cmds = new bytes32[](1);

    executeIntentInputs.accountAndSubAccountIds[0] = 0x0000000000000000000000009c7350039cbc7f5a3a6a8b1a14d26e4ac0ac52c6;
    executeIntentInputs.cmds[0] = 0x001993ecd65993ebf5402000000078067800000000000001ffffa72ad8e480d8;

    executeIntentInputs.signatures = new bytes[](1);
    executeIntentInputs.signatures[
      0
    ] = hex"ac5406f0be3197e34d8ac06222d3dcc96a8a804ff6e48b070dad227c3cda16ef1849798990f2649b547c83202982548e178289a63e613fdc1e926ab1cea9b95c1c";

    bytes32[] memory priceData = new bytes32[](7);
    priceData[0] = 0x01426701b2ab000004fffff5fffffe00cc5100c580012edf00cb1700ec9b0000;
    priceData[1] = 0x00c97e00030e008508000e6bffefcc000953ffe1defff3970002630007db0000;
    priceData[2] = 0x00263900ad1000d28100c9c600f9bd00c9a400eef7ffe668010f4c006cec0000;
    priceData[3] = 0xfffc80ffb825000c61000bc50148a5004d6c00504a00f232ff72350015190000;
    priceData[4] = 0x0013ac005cbb00b4690032e6001b1d008dd2005690008e11007f2f004d1c0000;
    priceData[5] = 0xffe6a20052c8ff5b3fff6ef10061c90016890008daffdfd200490bffe92e0000;
    priceData[6] = 0xfffb070000000000000000000000000000000000000000000000000000000000;

    bytes32[] memory publishTimeData = new bytes32[](7);
    publishTimeData[0] = 0x000f8f000f8f000f8f000f8f000f8f000000000f8f000f8f0000000000000000;
    publishTimeData[1] = 0x000000000f8f000f8f000f91000f8f000f8f000f8f000f8f000f8f000f8f0000;
    publishTimeData[2] = 0x000f8f000f8f000000000000000f8f000f8f000000000f8f000000000f8f0000;
    publishTimeData[3] = 0x000f8e000f8f000f8f000f8f000f91000f8f000f8f000f8f000f8f000f910000;
    publishTimeData[4] = 0x000f91000f8f000f91000f8f000f8f000f8f000f8f000f8f000f8f000f8f0000;
    publishTimeData[5] = 0x000f8f000f8f000f8f000f8f000f8f000f8f000f8f000f8f000f8f000f8f0000;
    publishTimeData[6] = 0x000f8f0000000000000000000000000000000000000000000000000000000000;

    executeIntentInputs.priceData = priceData;
    executeIntentInputs.publishTimeData = publishTimeData;
    executeIntentInputs.minPublishTime = 1716494407;
    executeIntentInputs.encodedVaas = 0xee276676535c642361666670efb80b5d8f0af32beb9b74ddd30970cb1cc63fdd;

    vm.startPrank(0x7FDD623c90a0097465170EdD352Be27A9f3ad817);
    intentHandler.execute(executeIntentInputs);
    vm.stopPrank();
  }
}
