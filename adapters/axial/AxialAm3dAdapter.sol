// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import {AxialBasic} from "./AxialBasic.sol";

contract AxialAm3dAdapter is AxialBasic {
    /// @dev the params are adapter manager address, router address, lptoken address, farm id, adapter name
    constructor(address _adapterManager, address _timelock)
        AxialBasic(
            _adapterManager,
            _timelock,
            0x90c7b96AD2142166D001B27b5fbc128494CDfBc8,
            0xc161E4B11FaF62584EFCD2100cCB461A2DdE64D1,
            3,
            "AxialAm3d"
        )
    {}
}
