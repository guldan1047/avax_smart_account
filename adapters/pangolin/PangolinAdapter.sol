// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/pangolin/IPangolinFactory.sol";
import "../../interfaces/pangolin/IPangolinRouter.sol";
import "../../interfaces/pangolin/IPangolinChef.sol";

contract PangolinAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    address public constant routerAddr =
        0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
    IPangolinRouter internal router = IPangolinRouter(routerAddr);

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Pangolin")
    {}

    event PangolinFarmEvent(uint256 pid, address account, uint256 amount);

    event PangolinUnFarmEvent(uint256 pid, address account, uint256 amount);

    event PangolinAddLiquidityEvent(
        uint256 liquidity,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        address account
    );

    event PangolinRemoveLiquidityEvent(
        address token0,
        address token1,
        uint256 amount,
        uint256 amount0,
        uint256 amount1,
        address account
    );

    /// @dev swap AVAX for fixed amount of tokens
    function swapAVAXForExactTokens(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 amountInMax, uint256 amountOut, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        uint256[] memory amounts = router.swapAVAXForExactTokens{
            value: amountInMax
        }(amountOut, path, account, block.timestamp);
        returnAsset(avaxAddr, account, amountInMax - amounts[0]);
    }

    /// @dev swap fixed amount of AVAX for tokens
    function swapExactAVAXForTokens(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 amountIn, uint256 amountOutMin, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        uint256[] memory amounts = router.swapExactAVAXForTokens{
            value: amountIn
        }(amountOutMin, path, account, block.timestamp);
    }

    /// @dev swap tokens for fixed amount of AVAX
    function swapTokensForExactTokens(
        address account,
        bytes calldata encodedData
    ) external onlyAdapterManager {
        (uint256 amountOut, uint256 amountInMax, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        pullAndApprove(path[0], account, routerAddr, amountInMax);
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            account,
            block.timestamp
        );
        returnAsset(path[0], account, amountInMax - amounts[0]);
    }

    /// @dev swap fixed amount of tokens for AVAX
    function swapExactTokensForTokens(
        address account,
        bytes calldata encodedData
    ) external onlyAdapterManager {
        (uint256 amountIn, uint256 amountOutMin, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        pullAndApprove(path[0], account, routerAddr, amountIn);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            account,
            block.timestamp
        );
    }

    function swapTokensForExactAVAX(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 amountOut, uint256 amountInMax, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        pullAndApprove(path[0], account, routerAddr, amountInMax);
        uint256[] memory amounts = router.swapTokensForExactAVAX(
            amountOut,
            amountInMax,
            path,
            account,
            block.timestamp
        );
        returnAsset(path[0], account, amountInMax - amounts[0]);
    }

    function swapExactTokensForAVAX(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (uint256 amountIn, uint256 amountOutMin, address[] memory path) = abi
            .decode(encodedData, (uint256, uint256, address[]));
        pullAndApprove(path[0], account, routerAddr, amountIn);

        uint256[] memory amounts = router.swapExactTokensForAVAX(
            amountIn,
            amountOutMin,
            path,
            account,
            block.timestamp
        );
    }

    struct addLiquidityInfo {
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 minAmountA;
        uint256 minAmountB;
    }

    function addLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        addLiquidityInfo memory addInfo = abi.decode(
            encodedData,
            (addLiquidityInfo)
        );
        pullAndApprove(addInfo.tokenA, account, routerAddr, addInfo.amountA);
        pullAndApprove(addInfo.tokenB, account, routerAddr, addInfo.amountB);
        (uint256 _amountA, uint256 _amountB, uint256 liquidity) = router
            .addLiquidity(
                addInfo.tokenA,
                addInfo.tokenB,
                addInfo.amountA,
                addInfo.amountB,
                addInfo.minAmountA,
                addInfo.minAmountB,
                account,
                block.timestamp
            );
        returnAsset(addInfo.tokenA, account, addInfo.amountA - _amountA);
        returnAsset(addInfo.tokenB, account, addInfo.amountB - _amountB);

        emit PangolinAddLiquidityEvent(
            liquidity,
            addInfo.tokenA,
            addInfo.tokenB,
            _amountA,
            _amountB,
            account
        );
    }

    struct removeLiquidityInfo {
        address tokenA;
        address tokenB;
        uint256 amount;
        uint256 minAmountA;
        uint256 minAmountB;
    }

    function removeLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        removeLiquidityInfo memory removeInfo = abi.decode(
            encodedData,
            (removeLiquidityInfo)
        );
        address lpTokenAddr = IPangolinFactory(router.factory()).getPair(
            removeInfo.tokenA,
            removeInfo.tokenB
        );
        require(lpTokenAddr != address(0), "pair-not-found.");
        pullAndApprove(lpTokenAddr, account, routerAddr, removeInfo.amount);
        (uint256 _amountA, uint256 _amountB) = router.removeLiquidity(
            removeInfo.tokenA,
            removeInfo.tokenB,
            removeInfo.amount,
            removeInfo.minAmountA,
            removeInfo.minAmountB,
            account,
            block.timestamp
        );
        emit PangolinRemoveLiquidityEvent(
            removeInfo.tokenA,
            removeInfo.tokenB,
            removeInfo.amount,
            _amountA,
            _amountB,
            account
        );
    }

    struct addLiquidityAVAXInfo {
        address tokenAddr;
        uint256 amountTokenDesired;
        uint256 amountTokenMin;
        uint256 amountAVAXMin;
    }

    function addLiquidityAVAX(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        addLiquidityAVAXInfo memory addInfo = abi.decode(
            encodedData,
            (addLiquidityAVAXInfo)
        );
        pullAndApprove(
            addInfo.tokenAddr,
            account,
            routerAddr,
            addInfo.amountTokenDesired
        );
        (uint256 _amountToken, uint256 _amountAVAX, uint256 _liquidity) = router
            .addLiquidityAVAX{value: msg.value}(
            addInfo.tokenAddr,
            addInfo.amountTokenDesired,
            addInfo.amountTokenMin,
            addInfo.amountAVAXMin,
            account,
            block.timestamp
        );
        if (addInfo.amountTokenDesired > _amountToken) {
            IERC20(addInfo.tokenAddr).safeTransfer(
                account,
                addInfo.amountTokenDesired - _amountToken
            );
        }
        returnAsset(
            addInfo.tokenAddr,
            account,
            addInfo.amountTokenDesired - _amountToken
        );
        returnAsset(avaxAddr, account, msg.value - _amountAVAX);

        emit PangolinAddLiquidityEvent(
            _liquidity,
            addInfo.tokenAddr,
            avaxAddr,
            _amountToken,
            _amountAVAX,
            account
        );
    }

    struct removeLiquidityAVAXInfo {
        address tokenA;
        uint256 liquidity;
        uint256 amountTokenMin;
        uint256 amountAVAXMin;
    }

    function removeLiquidityAVAX(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        removeLiquidityAVAXInfo memory removeInfo = abi.decode(
            encodedData,
            (removeLiquidityAVAXInfo)
        );
        address lpTokenAddr = IPangolinFactory(router.factory()).getPair(
            removeInfo.tokenA,
            wavaxAddr
        );
        pullAndApprove(lpTokenAddr, account, routerAddr, removeInfo.liquidity);
        (uint256 amountToken, uint256 amountAVAX) = router.removeLiquidityAVAX(
            removeInfo.tokenA,
            removeInfo.liquidity,
            removeInfo.amountTokenMin,
            removeInfo.amountAVAXMin,
            account,
            block.timestamp
        );
        emit PangolinRemoveLiquidityEvent(
            removeInfo.tokenA,
            avaxAddr,
            removeInfo.liquidity,
            amountToken,
            amountAVAX,
            account
        );
    }

    function depositLpToken(
        uint256 pid,
        address chefAddress,
        uint256 amount
    ) external onlyDelegation {
        IPangolinChef(chefAddress).deposit(pid, amount, address(this));
        emit PangolinFarmEvent(pid, address(this), amount);
    }

    function withdrawLpToken(
        uint256 pid,
        address chefAddress,
        uint256 amount
    ) external onlyDelegation {
        IPangolinChef(chefAddress).withdraw(pid, amount, address(this));
        emit PangolinUnFarmEvent(pid, address(this), amount);
    }

    function claim_rewards(uint256 pid, address chefAddress)
        external
        onlyDelegation
    {
        IPangolinChef(chefAddress).harvest(pid, address(this));
    }
}
