// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import {AxialBasic} from "./AxialBasic.sol";

contract AxialAc4dAdapter is AxialBasic {
    /// @dev the params are adapter manager address, router address, lptoken address, farm id, adapter name
    constructor(address _adapterManager, address _timelock)
        AxialBasic(
            _adapterManager,
            _timelock,
            0x8c3c1C6F971C01481150CA7942bD2bbB9Bc27bC7,
            0x4da067E13974A4d32D342d86fBBbE4fb0f95f382,
            1,
            "AxialAc4d"
        )
    {}
}
