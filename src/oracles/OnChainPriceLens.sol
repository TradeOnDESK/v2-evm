// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IPriceAdapter } from "@hmx/oracles/interfaces/IPriceAdapter.sol";
import { Ownable } from "@openzeppelin-4.8.1/contracts/access/Ownable.sol";

contract OnChainPriceLens is Ownable {
  error OnChainPriceLens_BadPriceId();
  error OnChainPriceLens_BadLength();

  event LogSetPriceAdapter(bytes32 priceId, address priceAdapter);

  mapping(bytes32 priceId => IPriceAdapter priceAdapter) public priceAdapterById;

  function setPriceAdapters(bytes32[] calldata priceIds, IPriceAdapter[] calldata priceAdapters) external onlyOwner {
    if (priceIds.length != priceAdapters.length) revert OnChainPriceLens_BadLength();

    for (uint256 i = 0; i < priceIds.length; ) {
      priceAdapterById[priceIds[i]] = priceAdapters[i];

      // Sanity check
      priceAdapters[i].getPrice();

      emit LogSetPriceAdapter(priceIds[i], address(priceAdapters[i]));

      unchecked {
        ++i;
      }
    }
  }

  function getPrice(bytes32 priceId) external view returns (uint256 price) {
    if (address(priceAdapterById[priceId]) == address(0)) revert OnChainPriceLens_BadPriceId();

    price = priceAdapterById[priceId].getPrice();
  }
}
