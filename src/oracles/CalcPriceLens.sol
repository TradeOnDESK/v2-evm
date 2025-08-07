// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";

import { ICalcPriceAdapter } from "@hmx/oracles/interfaces/ICalcPriceAdapter.sol";

import { IEcoPythCalldataBuilder3 } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder3.sol";

contract CalcPriceLens is Ownable {
  error CalcPriceLens_BadPriceId();
  error CalcPriceLens_BadLength();

  event LogSetPriceAdapter(bytes32 priceId, address priceAdapter);

  mapping(bytes32 priceId => ICalcPriceAdapter calcPriceAdapters) public priceAdapterById;

  function setPriceAdapters(
    bytes32[] calldata priceIds,
    ICalcPriceAdapter[] calldata calcPriceAdapters
  ) external onlyOwner {
    if (priceIds.length != calcPriceAdapters.length) revert CalcPriceLens_BadLength();

    for (uint256 i = 0; i < priceIds.length; ) {
      priceAdapterById[priceIds[i]] = calcPriceAdapters[i];

      emit LogSetPriceAdapter(priceIds[i], address(calcPriceAdapters[i]));

      unchecked {
        ++i;
      }
    }
  }

  function getPrice(
    bytes32 priceId,
    IEcoPythCalldataBuilder3.BuildData[] calldata _buildDatas
  ) external view returns (uint256 price) {
    if (address(priceAdapterById[priceId]) == address(0)) revert CalcPriceLens_BadPriceId();

    price = priceAdapterById[priceId].getPrice(_buildDatas);
  }

  function getPrice(bytes32 priceId, uint256[] memory priceE8s) external view returns (uint256 price) {
    if (address(priceAdapterById[priceId]) == address(0)) revert CalcPriceLens_BadPriceId();

    price = priceAdapterById[priceId].getPrice(priceE8s);
  }
}
