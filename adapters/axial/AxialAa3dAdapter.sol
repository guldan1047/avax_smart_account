// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import {AxialBasic} from "./AxialBasic.sol";

contract AxialAa3dAdapter is AxialBasic {
    /// @dev the params are adapter manager address, router address, lptoken address, farm id, adapter name
    constructor(address _adapterManager, address _timelock)
        AxialBasic(
            _adapterManager,
            _timelock,
            0x6EfbC734D91b229BE29137cf9fE531C1D3bf4Da6,
            0xaD556e7dc377d9089C6564f9E8d275f5EE4da22d,
            4,
            "AxialAa3d"
        )
    {}
}
