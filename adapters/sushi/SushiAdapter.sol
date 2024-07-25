// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/sushi/ISushiFactory.sol";
import "../../interfaces/sushi/ISushiRouter.sol";
import "../../interfaces/sushi/IStakingRewards.sol";

contract SushiAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    address public constant routerAddr =
        0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    ISushiRouter internal router = ISushiRouter(routerAddr);

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Sushi")
    {}

    event SushiFarmEvent(address farmAddress, address account, uint256 amount);

    event SushiUnFarmEvent(
        address farmAddress,
        address account,
        uint256 amount
    );
    event SushiAddLiquidityEvent(
        uint256 liquidity,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        address account
    );

    event SushiRemoveLiquidityEvent(
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
        uint256[] memory amounts = router.swapETHForExactTokens{
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
        uint256[] memory amounts = router.swapExactETHForTokens{
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
        uint256[] memory amounts = router.swapTokensForExactETH(
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

        uint256[] memory amounts = router.swapExactTokensForETH(
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
        emit SushiAddLiquidityEvent(
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
        address lpTokenAddr = ISushiFactory(router.factory()).getPair(
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
        emit SushiRemoveLiquidityEvent(
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
            .addLiquidityETH{value: msg.value}(
            addInfo.tokenAddr,
            addInfo.amountTokenDesired,
            addInfo.amountTokenMin,
            addInfo.amountAVAXMin,
            account,
            block.timestamp
        );
        returnAsset(
            addInfo.tokenAddr,
            account,
            addInfo.amountTokenDesired - _amountToken
        );
        returnAsset(avaxAddr, account, msg.value - _amountAVAX);
        emit SushiAddLiquidityEvent(
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
        address lpTokenAddr = ISushiFactory(router.factory()).getPair(
            removeInfo.tokenA,
            wavaxAddr
        );
        pullAndApprove(lpTokenAddr, account, routerAddr, removeInfo.liquidity);
        (uint256 amountToken, uint256 amountAVAX) = router.removeLiquidityETH(
            removeInfo.tokenA,
            removeInfo.liquidity,
            removeInfo.amountTokenMin,
            removeInfo.amountAVAXMin,
            account,
            block.timestamp
        );
        emit SushiRemoveLiquidityEvent(
            removeInfo.tokenA,
            avaxAddr,
            removeInfo.liquidity,
            amountToken,
            amountAVAX,
            account
        );
    }

    function depositLpToken(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        IStakingRewards(stakePoolAddr).stake(amount);
        emit SushiFarmEvent(stakePoolAddr, address(this), amount);
    }

    function withdrawLpToken(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        IStakingRewards(stakePoolAddr).withdraw(amount);
        emit SushiUnFarmEvent(stakePoolAddr, address(this), amount);
    }

    function claim_rewards(address stakePoolAddr) external onlyDelegation {
        IStakingRewards(stakePoolAddr).getReward();
    }
}
