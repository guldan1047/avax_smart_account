// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import {IYakRouter} from "../../interfaces/yak/IYakRouter.sol";
import {IMasterYak} from "../../interfaces/yak/IMasterYak.sol";
import {IWAVAX} from "../../interfaces/IWAVAX.sol";

contract YakAdapter is AdapterBase {
    address public constant routerAddr =
        0xC4729E56b831d74bBc18797e0e17A295fA77488c;
    address public constant masterYakAddr =
        0x0cf605484A512d3F3435fed77AB5ddC0525Daf5f;

    IYakRouter internal router = IYakRouter(routerAddr);

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Yak")
    {}

    function swapNoSplit(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        IYakRouter.Trade memory trade;
        uint256 fee;
        address to;
        (
            trade.amountIn,
            trade.amountOut,
            trade.path,
            trade.adapters,
            fee,
            to
        ) = abi.decode(
            encodedData,
            (uint256, uint256, address[], address[], uint256, address)
        );
        pullAndApprove(trade.path[0], to, routerAddr, trade.amountIn);

        router.swapNoSplit(trade, to, fee);
    }

    function swapNoSplitFromAVAX(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        IYakRouter.Trade memory trade;
        uint256 fee;
        address to;
        (
            trade.amountIn,
            trade.amountOut,
            trade.path,
            trade.adapters,
            fee,
            to
        ) = abi.decode(
            encodedData,
            (uint256, uint256, address[], address[], uint256, address)
        );

        router.swapNoSplitFromAVAX{value: trade.amountIn}(trade, to, fee);
    }

    function swapNoSplitToAVAX(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        IYakRouter.Trade memory trade;
        uint256 fee;
        address to;
        (
            trade.amountIn,
            trade.amountOut,
            trade.path,
            trade.adapters,
            fee,
            to
        ) = abi.decode(
            encodedData,
            (uint256, uint256, address[], address[], uint256, address)
        );
        pullAndApprove(trade.path[0], to, routerAddr, trade.amountIn);
        router.swapNoSplit(trade, address(this), fee);
        IWAVAX(wavaxAddr).withdraw(trade.amountOut);
        safeTransferAVAX(to, trade.amountOut);
    }

    function deposit(uint256 pid, uint256 amount) external onlyDelegation {
        IMasterYak(masterYakAddr).deposit(pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external onlyDelegation {
        IMasterYak(masterYakAddr).withdraw(pid, amount);
    }
}
