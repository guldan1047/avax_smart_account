// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../base/AdapterBase.sol";
import "../../../interfaces/curve/ICurveAPoolForUseOnAvalanche.sol";
import "../../../interfaces/curve/ICurveLpToken.sol";
import "../../../interfaces/curve/ICurveRewardsOnlyGauge.sol";
import "../../../interfaces/aave/v2/IAToken.sol";
import "../../../interfaces/curve/IGaugeFactory.sol";

contract CurveCrvAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "CurveCrvSwap")
    {}

    address public constant routerAddr =
        0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address public constant lpAddr = 0x1337BedC9D22ecbe766dF105c9623922A27963EC;
    address public constant farmAddr =
        0x4620D46b4db7fB04a01A75fFed228Bc027C9A899;
    address public constant guageFactory =
        0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    address public constant crvAddr =
        0x47536F17F4fF30e64A96a7555826b8f9e66ec468;

    mapping(int128 => address) public coins;
    mapping(int128 => address) public underlying_coins;

    function initialize(
        address[] calldata tokenAddr,
        address[] calldata aTokenAddr
    ) external onlyTimelock {
        require(
            tokenAddr.length == 3 && tokenAddr.length == aTokenAddr.length,
            "Set length mismatch."
        );
        for (uint256 i = 0; i < tokenAddr.length; i++) {
            require(
                IAToken(aTokenAddr[i]).UNDERLYING_ASSET_ADDRESS() ==
                    tokenAddr[i],
                "Address mismatch."
            );
        }
        coins[0] = aTokenAddr[0];
        coins[1] = aTokenAddr[1];
        coins[2] = aTokenAddr[2];
        underlying_coins[0] = tokenAddr[0];
        underlying_coins[1] = tokenAddr[1];
        underlying_coins[2] = tokenAddr[2];
    }

    event CurveCrvExchangeEvent(
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        address account
    );

    event CurveCrvAddLiquidityEvent(
        address lpAddress,
        address[3] tokenAddresses,
        uint256[3] addAmounts,
        uint256 lpAmount,
        address account
    );
    event CurveCrvRemoveLiquidityEvent(
        address lpAddress,
        uint256 lpRemove,
        address[3] tokenAddresses,
        uint256[3] tokenAmounts,
        address account
    );

    event CurveCrvDepositEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveCrvWithdrawEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveCrvClaimRewardsEvent(
        address lpToken,
        address[2] rewardTokens,
        uint256[2] rewardAmounts,
        address account
    );

    function exchange(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param fromNumber 0 for adai; 1 for ausdc; 2 for ausdt
        /// @param toNumber 0 for adai; 1 for ausdc; 2 for ausdt
        /// @param dx amount to exchange
        /// @param min_dy min amount to be exchanged out
        (int128 fromNumber, int128 toNumber, uint256 dx, uint256 min_dy) = abi
            .decode(encodedData, (int128, int128, uint256, uint256));
        address tokenFrom = coins[fromNumber];
        pullAndApprove(tokenFrom, account, routerAddr, dx);
        uint256 giveBack = ICurveAPoolForUseOnAvalanche(routerAddr).exchange(
            fromNumber,
            toNumber,
            dx,
            min_dy
        );
        IERC20(coins[toNumber]).safeTransfer(account, giveBack);

        emit CurveCrvExchangeEvent(
            coins[fromNumber],
            coins[toNumber],
            dx,
            giveBack,
            account
        );
    }

    function exchangeUnderlying(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param fromNumber 0 for dai.e; 1 for usdc.e; 2 for usdt.e
        /// @param toNumber 0 for dai.e; 1 for usdc.e; 2 for usdt.e
        /// @param dx amount to exchange
        /// @param min_dy min amount to be exchanged out
        (int128 fromNumber, int128 toNumber, uint256 dx, uint256 min_dy) = abi
            .decode(encodedData, (int128, int128, uint256, uint256));
        pullAndApprove(underlying_coins[fromNumber], account, routerAddr, dx);

        uint256 giveBack = ICurveAPoolForUseOnAvalanche(routerAddr)
            .exchange_underlying(fromNumber, toNumber, dx, min_dy);
        IERC20(underlying_coins[toNumber]).safeTransfer(account, giveBack);

        emit CurveCrvExchangeEvent(
            underlying_coins[fromNumber],
            underlying_coins[toNumber],
            dx,
            giveBack,
            account
        );
    }

    function addLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param amountsIn the amounts to add, in the order of dai.e, usdc.e, usdt.e
        /// @param minMintAmount the minimum lp token amount to be minted and returned to the user
        /// @param useUnderlying true: use dai.e, usdc.e, usdt.e; false: use avdai, avusdc, avusdt
        (
            uint256[3] memory amountsIn,
            uint256 minMintAmount,
            bool useUnderlying
        ) = abi.decode(encodedData, (uint256[3], uint256, bool));

        if (useUnderlying) {
            pullAndApprove(
                underlying_coins[0],
                account,
                routerAddr,
                amountsIn[0]
            );
            pullAndApprove(
                underlying_coins[1],
                account,
                routerAddr,
                amountsIn[1]
            );
            pullAndApprove(
                underlying_coins[2],
                account,
                routerAddr,
                amountsIn[2]
            );
        } else {
            pullAndApprove(coins[0], account, routerAddr, amountsIn[0]);
            pullAndApprove(coins[1], account, routerAddr, amountsIn[1]);
            pullAndApprove(coins[2], account, routerAddr, amountsIn[2]);
        }
        uint256 giveBack = ICurveAPoolForUseOnAvalanche(routerAddr)
            .add_liquidity(amountsIn, minMintAmount, useUnderlying);
        IERC20(lpAddr).safeTransfer(account, giveBack);
        emit CurveCrvAddLiquidityEvent(
            lpAddr,
            [underlying_coins[0], underlying_coins[1], underlying_coins[2]],
            amountsIn,
            giveBack,
            account
        );
    }

    function removeLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param removeAmount amount of the lp token to remove liquidity
        /// @param minAmounts the minimum amounts of the (underlying) tokens to return to the user
        /// @param useUnderlying true: use dai.e, usdc.e, usdt.e; false: use avdai, avusdc, avusdt
        (
            uint256 removeAmount,
            uint256[3] memory minAmounts,
            bool useUnderlying
        ) = abi.decode(encodedData, (uint256, uint256[3], bool));

        pullAndApprove(lpAddr, account, routerAddr, removeAmount);

        uint256[3] memory giveBack = ICurveAPoolForUseOnAvalanche(routerAddr)
            .remove_liquidity(removeAmount, minAmounts, useUnderlying);
        if (useUnderlying) {
            IERC20(underlying_coins[0]).safeTransfer(account, giveBack[0]);
            IERC20(underlying_coins[1]).safeTransfer(account, giveBack[1]);
            IERC20(underlying_coins[2]).safeTransfer(account, giveBack[2]);
        } else {
            IERC20(coins[0]).safeTransfer(account, giveBack[0]);
            IERC20(coins[1]).safeTransfer(account, giveBack[1]);
            IERC20(coins[2]).safeTransfer(account, giveBack[2]);
        }

        emit CurveCrvRemoveLiquidityEvent(
            lpAddr,
            removeAmount,
            [underlying_coins[0], underlying_coins[1], underlying_coins[2]],
            giveBack,
            account
        );
    }

    function removeLiquidityOneCoin(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param tokenNumber 0 for dai.e(or avdai); 1 for usdc.e(or avusdc); 2 for usdt.e(or avusdt)
        /// @param lpAmount the amount of the lp to remove
        /// @param minAmount the minimum amount to return to the user
        /// @param useUnderlying true: use dai.e, usdc.e, usdt.e; false: use avdai, avusdc, avusdt
        (
            int128 tokenNumber,
            uint256 lpAmount,
            uint256 minAmount,
            bool useUnderlying
        ) = abi.decode(encodedData, (int128, uint256, uint256, bool));

        pullAndApprove(lpAddr, account, routerAddr, lpAmount);
        uint256 giveBack = ICurveAPoolForUseOnAvalanche(routerAddr)
            .remove_liquidity_one_coin(
                lpAmount,
                tokenNumber,
                minAmount,
                useUnderlying
            );
        uint256[3] memory amounts;
        if (tokenNumber == 0) {
            amounts = [giveBack, 0, 0];
        } else if (tokenNumber == 1) {
            amounts = [0, giveBack, 0];
        } else if (tokenNumber == 2) {
            amounts = [0, 0, giveBack];
        }
        address toToken;
        if (useUnderlying) {
            toToken = underlying_coins[tokenNumber];
        } else {
            toToken = coins[tokenNumber];
        }
        IERC20(toToken).safeTransfer(account, giveBack);

        emit CurveCrvRemoveLiquidityEvent(
            lpAddr,
            lpAmount,
            [underlying_coins[0], underlying_coins[1], underlying_coins[2]],
            amounts,
            account
        );
    }

    function deposit(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        uint256 amountDeposit = abi.decode(encodedData, (uint256));
        pullAndApprove(lpAddr, account, farmAddr, amountDeposit);
        ICurveRewardsOnlyGauge(farmAddr).deposit(amountDeposit, account, false);
        emit CurveCrvDepositEvent(lpAddr, farmAddr, amountDeposit, account);
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        uint256 amountWithdraw = abi.decode(encodedData, (uint256));
        pullAndApprove(farmAddr, account, farmAddr, amountWithdraw);
        ICurveLpToken lp = ICurveLpToken(lpAddr);
        uint256 balanceBefore = lp.balanceOf(address(this));
        ICurveRewardsOnlyGauge(farmAddr).withdraw(amountWithdraw);
        uint256 balanceAfter = lp.balanceOf(address(this));
        uint256 lpAmount = balanceAfter - balanceBefore;
        IERC20(lpAddr).safeTransfer(account, lpAmount);
        emit CurveCrvWithdrawEvent(lpAddr, farmAddr, lpAmount, account);
    }

    function claimRewards() external onlyDelegation {
        address[2] memory rewardTokens = [wavaxAddr, crvAddr];
        uint256[2] memory balancesBefore;
        uint256[2] memory balancesAfter;
        uint256[2] memory rewardAmounts;
        balancesBefore[0] = IERC20(rewardTokens[0]).balanceOf(address(this));
        balancesBefore[1] = IERC20(rewardTokens[1]).balanceOf(address(this));
        IGaugeFactory(guageFactory).mint(farmAddr);
        balancesAfter[0] = IERC20(rewardTokens[0]).balanceOf(address(this));
        balancesAfter[1] = IERC20(rewardTokens[1]).balanceOf(address(this));
        rewardAmounts[0] = balancesAfter[0] - balancesBefore[0];
        rewardAmounts[1] = balancesAfter[1] - balancesBefore[1];

        emit CurveCrvClaimRewardsEvent(
            lpAddr,
            rewardTokens,
            rewardAmounts,
            address(this)
        );
    }
}
