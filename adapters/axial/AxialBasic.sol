// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import {ISwapFlashLoan} from "../../interfaces/axial/ISwapFlashLoan.sol";
import {IMasterChefAxialV3} from "../../interfaces/axial/IMasterChefAxialV3.sol";

/// @dev common part of Axial adapters
contract AxialBasic is AdapterBase {
    using SafeERC20 for IERC20;

    address public immutable routerAddr;
    address public immutable lpTokenAddr;
    address public immutable stakingPoolAddr =
        0x958C0d0baA8F220846d3966742D4Fb5edc5493D3;
    uint256 public immutable stakingPid;

    event AxialAddLiquidity(
        address adapterAddress,
        uint256[] amounts,
        uint256 minLpAmount,
        address account
    );

    event AxialRemoveLiquidity(
        address adapterAddress,
        uint256[] amountsMin,
        uint256 lpAmount,
        address account
    );

    event AxialRemoveLiquidityOneToken(
        address adapterAddress,
        uint8 tokenIndex,
        uint256 lpAmount,
        uint256 minAmount,
        address account
    );

    event AxialFarmEvent(
        address farmAddress,
        address account,
        uint256 amount,
        uint256 pid
    );

    event AxialUnFarmEvent(
        address farmAddress,
        address account,
        uint256 amount,
        uint256 pid
    );

    constructor(
        address _adapterManager,
        address _timelock,
        address _routerAddr,
        address _lpTokenAddr,
        uint256 _pid,
        string memory _name
    ) AdapterBase(_adapterManager, _timelock, _name) {
        routerAddr = _routerAddr;
        lpTokenAddr = _lpTokenAddr;
        stakingPid = _pid;
    }

    function swap(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            uint8 tokenIndexFrom,
            uint8 tokenIndexTo,
            uint256 dx,
            uint256 minDy
        ) = abi.decode(encodedData, (uint8, uint8, uint256, uint256));
        uint256[2] memory amounts;
        ISwapFlashLoan router = ISwapFlashLoan(routerAddr);
        address tokenFrom = router.getToken(tokenIndexFrom);
        address tokenTo = router.getToken(tokenIndexTo);
        pullAndApprove(tokenFrom, account, routerAddr, dx);
        amounts[0] = dx;
        amounts[1] = router.swap(
            tokenIndexFrom,
            tokenIndexTo,
            dx,
            minDy,
            block.timestamp
        );
        IERC20(tokenTo).safeTransfer(account, amounts[1]);
    }

    function addLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256[] memory amounts, uint256 minToMint) = abi.decode(
            encodedData,
            (uint256[], uint256)
        );

        ISwapFlashLoan router = ISwapFlashLoan(routerAddr);
        for (uint8 i = 0; i < amounts.length; i++) {
            address tokenAddr = router.getToken(i);
            pullAndApprove(tokenAddr, account, routerAddr, amounts[i]);
        }

        uint256 amount = router.addLiquidity(
            amounts,
            minToMint,
            block.timestamp
        );

        IERC20(lpTokenAddr).safeTransfer(account, amount);
        emit AxialAddLiquidity(address(this), amounts, minToMint, account);
    }

    function removeLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 lpAmount, uint256[] memory amountsMin) = abi.decode(
            encodedData,
            (uint256, uint256[])
        );

        ISwapFlashLoan router = ISwapFlashLoan(routerAddr);
        pullAndApprove(lpTokenAddr, account, routerAddr, lpAmount);
        uint256[] memory amountsOut = router.removeLiquidity(
            lpAmount,
            amountsMin,
            block.timestamp
        );
        for (uint8 i = 0; i < amountsOut.length; i++) {
            address tokenAddr = router.getToken(i);
            IERC20(tokenAddr).safeTransfer(account, amountsOut[i]);
        }
        emit AxialRemoveLiquidity(address(this), amountsMin, lpAmount, account);
    }

    function removeLiquidityOneToken(
        address account,
        bytes calldata encodedData
    ) external onlyAdapterManager {
        (uint256 lpAmount, uint8 tokenIndex, uint256 minAmount) = abi.decode(
            encodedData,
            (uint256, uint8, uint256)
        );

        ISwapFlashLoan router = ISwapFlashLoan(routerAddr);
        pullAndApprove(lpTokenAddr, account, routerAddr, lpAmount);
        uint256 amount = router.removeLiquidityOneToken(
            lpAmount,
            tokenIndex,
            minAmount,
            block.timestamp
        );
        address tokenAddr = router.getToken(tokenIndex);
        IERC20(tokenAddr).safeTransfer(account, amount);
        emit AxialRemoveLiquidityOneToken(
            address(this),
            tokenIndex,
            lpAmount,
            minAmount,
            account
        );
    }

    function deposit(uint256 amount) external onlyDelegation {
        IMasterChefAxialV3(stakingPoolAddr).deposit(stakingPid, amount);
        emit AxialFarmEvent(stakingPoolAddr, address(this), amount, stakingPid);
    }

    function withdraw(uint256 amount) external onlyDelegation {
        IMasterChefAxialV3(stakingPoolAddr).withdraw(stakingPid, amount);
        emit AxialUnFarmEvent(
            stakingPoolAddr,
            address(this),
            amount,
            stakingPid
        );
    }
}
