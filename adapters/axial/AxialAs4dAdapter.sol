// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import {AxialBasic} from "./AxialBasic.sol";

contract AxialAs4dAdapter is AxialBasic {
    /// @dev the params are adapter manager address, router address, lptoken address, farm id, adapter name
    constructor(address _adapterManager, address _timelock)
        AxialBasic(
            _adapterManager,
            _timelock,
            0x2a716c4933A20Cd8B9f9D9C39Ae7196A85c24228,
            0x3A7387f8BA3ebFFa4A0ECcB1733e940CE2275D3f,
            0,
            "AxialAs4d"
        )
    {}
}
