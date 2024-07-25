// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/kyber/IKyberRouter.sol";
import "../../interfaces/kyber/IKyberZap.sol";
import "../../interfaces/kyber/IKyberFairLaunchV2.sol";
import "../../interfaces/kyber/IKyberDMMPool.sol";

import "hardhat/console.sol";

contract KyberAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Kyber")
    {}

    address public constant routerAddr =
        0x8Efa5A9AD6D594Cf76830267077B78cE0Bc5A5F8;
    address public constant zapAddr =
        0x83D4908c1B4F9Ca423BEE264163BC1d50F251c31;
    address public constant fairLaunchV2Addr =
        0x845d1D0D9b344fbA8a205461B9E94aEfe258B918;

    IKyberRouter internal router = IKyberRouter(routerAddr);
    IKyberZap internal zapper = IKyberZap(zapAddr);
    IKyberFairLaunchV2 internal fairLaunchV2 =
        IKyberFairLaunchV2(fairLaunchV2Addr);

    uint256 internal constant Q112 = 2**112;

    event KyberAddLiquidityEvent(
        address tokenA,
        address tokenB,
        address pool,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address account
    );

    event KyberRemoveLiquidityEvent(
        address tokenA,
        address tokenB,
        address pool,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address account
    );

    struct addLiquidityInfo {
        address tokenA;
        address tokenB;
        address pool;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        uint256 vReserve0;
        uint256 vReserve1;
        uint256 boundsLimit;
    }

    struct addLiquidityReturnInfo {
        uint256 amountA;
        uint256 amountB;
        uint256 liquidty;
    }

    function addLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        addLiquidityInfo memory addInfo = abi.decode(
            encodedData,
            (addLiquidityInfo)
        );
        pullAndApprove(
            addInfo.tokenA,
            account,
            routerAddr,
            addInfo.amountADesired
        );
        pullAndApprove(
            addInfo.tokenB,
            account,
            routerAddr,
            addInfo.amountBDesired
        );
        // stack too deep, therefore seperated the function
        (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ) = _addLiquidityOperation(account, addInfo);
        returnAsset(addInfo.tokenA, account, addInfo.amountADesired - amountA);
        returnAsset(addInfo.tokenB, account, addInfo.amountBDesired - amountB);

        emit KyberAddLiquidityEvent(
            addInfo.tokenA,
            addInfo.tokenB,
            addInfo.pool,
            amountA,
            amountB,
            liquidity,
            account
        );
    }

    function _addLiquidityOperation(
        address account,
        addLiquidityInfo memory addInfo
    )
        internal
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        uint256[2] memory vReserveRatioBounds = calcVReserveRatioBounds(
            addInfo.vReserve0,
            addInfo.vReserve1,
            addInfo.boundsLimit
        );
        (amountA, amountB, liquidity) = router.addLiquidity(
            addInfo.tokenA,
            addInfo.tokenB,
            addInfo.pool,
            addInfo.amountADesired,
            addInfo.amountBDesired,
            addInfo.amountAMin,
            addInfo.amountBMin,
            vReserveRatioBounds,
            account,
            block.timestamp
        );
    }

    function calcVReserveRatioBounds(
        uint256 vReserve0,
        uint256 vReserve1,
        uint256 boundsLimit
    ) internal pure returns (uint256[2] memory vReserveRatioBounds) {
        uint256 vReserveRatio = (vReserve1 * Q112) / vReserve0;
        vReserveRatioBounds = [
            (vReserveRatio * (100 - boundsLimit)) / 100,
            (vReserveRatio * (100 + boundsLimit)) / 100
        ];
    }

    struct addLiquidityETHInfo {
        address token;
        address pool;
        uint256 amountTokenDesired;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        uint256 vReserve0;
        uint256 vReserve1;
        uint256 boundsLimit;
    }

    function addLiquidityETH(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        addLiquidityETHInfo memory addInfo = abi.decode(
            encodedData,
            (addLiquidityETHInfo)
        );
        pullAndApprove(
            addInfo.token,
            account,
            routerAddr,
            addInfo.amountTokenDesired
        );

        (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        ) = _addLiquidityETHOperation(account, addInfo);
        returnAsset(
            addInfo.token,
            account,
            addInfo.amountTokenDesired - amountToken
        );
        returnAsset(avaxAddr, account, msg.value - amountETH);

        emit KyberAddLiquidityEvent(
            addInfo.token,
            avaxAddr,
            addInfo.pool,
            amountToken,
            amountETH,
            liquidity,
            account
        );
    }

    function _addLiquidityETHOperation(
        address account,
        addLiquidityETHInfo memory addInfo
    )
        internal
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        uint256[2] memory vReserveRatioBounds = calcVReserveRatioBounds(
            addInfo.vReserve0,
            addInfo.vReserve1,
            addInfo.boundsLimit
        );
        (amountToken, amountETH, liquidity) = router.addLiquidityETH{
            value: msg.value
        }(
            addInfo.token,
            addInfo.pool,
            addInfo.amountTokenDesired,
            addInfo.amountTokenMin,
            addInfo.amountETHMin,
            vReserveRatioBounds,
            account,
            block.timestamp
        );
    }

    struct removeLiquidityInfo {
        address tokenA;
        address tokenB;
        address pool;
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    function removeLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        removeLiquidityInfo memory removeInfo = abi.decode(
            encodedData,
            (removeLiquidityInfo)
        );
        pullAndApprove(
            removeInfo.pool,
            account,
            routerAddr,
            removeInfo.liquidity
        );
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            removeInfo.tokenA,
            removeInfo.tokenB,
            removeInfo.pool,
            removeInfo.liquidity,
            removeInfo.amountAMin,
            removeInfo.amountBMin,
            account,
            block.timestamp
        );
        emit KyberRemoveLiquidityEvent(
            removeInfo.tokenA,
            removeInfo.tokenB,
            removeInfo.pool,
            amountA,
            amountB,
            removeInfo.liquidity,
            account
        );
    }

    struct removeLiquidityETHInfo {
        address token;
        address pool;
        uint256 liquidity;
        uint256 amountTokenMin;
        uint256 amountETHMin;
    }

    function removeLiquidityETH(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        removeLiquidityETHInfo memory removeInfo = abi.decode(
            encodedData,
            (removeLiquidityETHInfo)
        );
        pullAndApprove(
            removeInfo.pool,
            account,
            routerAddr,
            removeInfo.liquidity
        );
        (uint256 amountToken, uint256 amountETH) = router.removeLiquidityETH(
            removeInfo.token,
            removeInfo.pool,
            removeInfo.liquidity,
            removeInfo.amountTokenMin,
            removeInfo.amountETHMin,
            account,
            block.timestamp
        );
        emit KyberRemoveLiquidityEvent(
            removeInfo.token,
            avaxAddr,
            removeInfo.pool,
            amountToken,
            amountETH,
            removeInfo.liquidity,
            account
        );
    }

    struct zapInInfo {
        address tokenIn;
        address tokenOut;
        uint256 userIn;
        address pool;
        uint256 minLpQty;
    }

    function zapIn(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        zapInInfo memory zapInfo = abi.decode(encodedData, (zapInInfo));
        pullAndApprove(zapInfo.tokenIn, account, zapAddr, zapInfo.userIn);
        zapper.zapIn(
            zapInfo.tokenIn,
            zapInfo.tokenOut,
            zapInfo.userIn,
            zapInfo.pool,
            account,
            zapInfo.minLpQty,
            block.timestamp
        );
    }

    struct zapInEthInfo {
        address tokenOut;
        address pool;
        uint256 minLpQty;
    }

    function zapInEth(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        zapInEthInfo memory zapInfo = abi.decode(encodedData, (zapInEthInfo));
        zapper.zapInEth{value: msg.value}(
            zapInfo.tokenOut,
            zapInfo.pool,
            account,
            zapInfo.minLpQty,
            block.timestamp
        );
    }

    struct zapOutInfo {
        address tokenIn;
        address tokenOut;
        uint256 liquidity;
        address pool;
        uint256 minTokenOut;
    }

    function zapOut(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        zapOutInfo memory zapInfo = abi.decode(encodedData, (zapOutInfo));
        pullAndApprove(zapInfo.pool, account, zapAddr, zapInfo.liquidity);
        zapper.zapOut(
            zapInfo.tokenIn,
            zapInfo.tokenOut,
            zapInfo.liquidity,
            zapInfo.pool,
            account,
            zapInfo.minTokenOut,
            block.timestamp
        );
    }

    function deposit(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 pid, uint256 amount, bool shouldHarvest) = abi.decode(
            encodedData,
            (uint256, uint256, bool)
        );
        (
            ,
            address stakeToken,
            address generatedToken,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = fairLaunchV2.getPoolInfo(pid);
        pullAndApprove(stakeToken, account, fairLaunchV2Addr, amount);
        IERC20 lp = IERC20(generatedToken);
        uint256 balanceBefore = lp.balanceOf(address(this));
        fairLaunchV2.deposit(pid, amount, shouldHarvest);
        uint256 balanceAfter = lp.balanceOf(address(this));
        returnAsset(generatedToken, account, balanceAfter - balanceBefore);
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 pid, uint256 amount) = abi.decode(
            encodedData,
            (uint256, uint256)
        );
        (
            ,
            address stakeToken,
            address generatedToken,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = fairLaunchV2.getPoolInfo(pid);
        pullAndApprove(generatedToken, account, fairLaunchV2Addr, amount);
        IERC20 dmmPool = IERC20(stakeToken);
        uint256 balanceBefore = dmmPool.balanceOf(address(this));
        fairLaunchV2.withdraw(pid, amount);
        uint256 balanceAfter = dmmPool.balanceOf(address(this));
        returnAsset(stakeToken, account, balanceAfter - balanceBefore);
    }

    // function harvest(address account, bytes calldata encodedData)
    //     external
    //     onlyAdapterManager
    // {
    //     uint256 pid = abi.decode(encodedData, (uint256));
    //     address[] memory rewardTokens = fairLaunchV2.getRewardTokens();
    //     uint256[] memory balancesBefore;
    //     for (uint256 i = 0; i < rewardTokens.length; i++) {
    //         if (rewardTokens[i] == 0x0000000000000000000000000000000000000000) {
    //             balancesBefore[i] = address(this).balance;
    //         }
    //         balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(
    //             address(this)
    //         );
    //     }
    //     fairLaunchV2.harvest(pid);
    //     for (uint256 i = 0; i < rewardTokens.length; i++) {
    //         uint256 balanceDiff;
    //         if (rewardTokens[i] == 0x0000000000000000000000000000000000000000) {
    //             balanceDiff = address(this).balance;
    //             if (balanceDiff > 0) {
    //                 safeTransferAVAX(account, balanceDiff);
    //             }
    //         } else {
    //             balanceDiff =
    //                 IERC20(rewardTokens[i]).balanceOf(address(this)) -
    //                 balancesBefore[i];
    //             if (balanceDiff > 0) {
    //                 IERC20(rewardTokens[i]).safeTransfer(account, balanceDiff);
    //             }
    //         }
    //     }
    // }

    function harvest(bytes calldata encodedData) external onlyDelegation {
        uint256 pid = abi.decode(encodedData, (uint256));
        fairLaunchV2.harvest(pid);
    }
}
