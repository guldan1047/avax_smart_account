// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../base/AdapterBase.sol";
import "../../../interfaces/curve/ICurveAPoolForUseOnPolygon.sol";
import "../../../interfaces/curve/ICurveRewardsOnlyGauge.sol";
import "../../../interfaces/curve/ICurveLpToken.sol";
import "../../../interfaces/curve/IGaugeFactory.sol";
import "hardhat/console.sol";

contract CurveBtcAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "CurveBtcSwap")
    {}

    address public constant routerAddr =
        0x16a7DA911A4DD1d83F3fF066fE28F3C792C50d90;
    address public constant lpAddr = 0xC2b1DF84112619D190193E48148000e3990Bf627;
    address public constant farmAddr =
        0x00F7d467ef51E44f11f52a0c0Bef2E56C271b264;
    address public constant guageFactory =
        0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    address public constant crvAddr =
        0x47536F17F4fF30e64A96a7555826b8f9e66ec468;

    mapping(int128 => address) public coins;
    mapping(int128 => address) public underlying_coins;

    event CurveBtcExchangeEvent(
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        address account
    );

    event CurveBtcAddLiquidityEvent(
        address lpAddress,
        address[2] tokenAddresses,
        uint256[2] addAmounts,
        uint256 lpAmount,
        address account
    );

    event CurveBtcRemoveLiquidityEvent(
        address lpAddress,
        uint256 lpRemove,
        address[2] tokenAddresses,
        uint256[2] tokenAmounts,
        address account
    );

    event CurveBtcDepositEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveBtcWithdrawEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveBtcClaimRewardsEvent(
        address lpToken,
        address[2] rewardTokens,
        uint256[2] rewardAmounts,
        address account
    );

    function initialize(
        address[] calldata _underlying_coins,
        address[] calldata _coins
    ) external onlyTimelock {
        require(
            _underlying_coins.length == 2 &&
                _coins.length == _underlying_coins.length,
            "Set length mismatch."
        );
        // for (uint256 i = 0; i < tokenAddr.length; i++) {
        //     require(
        //         IAToken(aTokenAddr[i]).UNDERLYING_ASSET_ADDRESS() ==
        //             tokenAddr[i],
        //         "Address mismatch."
        //     );
        // }
        underlying_coins[0] = _underlying_coins[0];
        underlying_coins[1] = _underlying_coins[1];
        coins[0] = _coins[0];
        coins[1] = _coins[1];
    }

    function exchange(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param fromNumber 0 for avwbtc; 1 for renbtc.e
        /// @param toNumber 0 for avwbtc; 1 for renbtc.e
        /// @param dx amount to exchange
        /// @param min_dy min amount to be exchanged out
        (int128 fromNumber, int128 toNumber, uint256 dx, uint256 min_dy) = abi
            .decode(encodedData, (int128, int128, uint256, uint256));
        pullAndApprove(coins[fromNumber], account, routerAddr, dx);

        uint256 giveBack = ICurveAPoolForUseOnPolygon(routerAddr).exchange(
            fromNumber,
            toNumber,
            dx,
            min_dy
        );
        IERC20(coins[toNumber]).safeTransfer(account, giveBack);

        emit CurveBtcExchangeEvent(
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
        /// @param fromNumber 0 for wbtc.e; 1 for renbtc.e
        /// @param toNumber 0 for wbtc.e; 1 for renbtc.e
        /// @param dx amount to exchange
        /// @param min_dy min amount to be exchanged out
        (int128 fromNumber, int128 toNumber, uint256 dx, uint256 min_dy) = abi
            .decode(encodedData, (int128, int128, uint256, uint256));
        pullAndApprove(underlying_coins[fromNumber], account, routerAddr, dx);

        uint256 giveBack = ICurveAPoolForUseOnPolygon(routerAddr)
            .exchange_underlying(fromNumber, toNumber, dx, min_dy);
        IERC20(underlying_coins[toNumber]).safeTransfer(account, giveBack);

        emit CurveBtcExchangeEvent(
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
        /// @param amountsIn the amounts to add, in the order of wbtc.e(or avwbtc), renbtc.e
        /// @param minMintAmount the minimum lp token amount to be minted and returned to the user
        /// @param useUnderlying true: use wbtc.e; false: use avwbtc
        (
            uint256[2] memory amountsIn,
            uint256 minMintAmount,
            bool useUnderlying
        ) = abi.decode(encodedData, (uint256[2], uint256, bool));
        if (useUnderlying) {
            pullAndApprove(
                underlying_coins[0],
                account,
                routerAddr,
                amountsIn[0]
            );
        } else {
            pullAndApprove(coins[0], account, routerAddr, amountsIn[0]);
        }
        pullAndApprove(coins[1], account, routerAddr, amountsIn[1]);

        uint256 giveBack = ICurveAPoolForUseOnPolygon(routerAddr).add_liquidity(
            amountsIn,
            minMintAmount,
            useUnderlying
        );

        IERC20(lpAddr).transfer(account, giveBack);
        emit CurveBtcAddLiquidityEvent(
            lpAddr,
            [underlying_coins[0], underlying_coins[1]],
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
        /// @param useUnderlying true: use wbtc.e; false: use avwbtc
        (
            uint256 removeAmount,
            uint256[2] memory minAmounts,
            bool useUnderlying
        ) = abi.decode(encodedData, (uint256, uint256[2], bool));
        pullAndApprove(lpAddr, account, routerAddr, removeAmount);
        uint256[2] memory giveBack = ICurveAPoolForUseOnPolygon(routerAddr)
            .remove_liquidity(removeAmount, minAmounts, useUnderlying);
        if (useUnderlying) {
            IERC20(underlying_coins[0]).safeTransfer(account, giveBack[0]);
        } else {
            IERC20(coins[0]).safeTransfer(account, giveBack[0]);
        }
        IERC20(coins[1]).safeTransfer(account, giveBack[1]);
        emit CurveBtcRemoveLiquidityEvent(
            lpAddr,
            removeAmount,
            [underlying_coins[0], underlying_coins[1]],
            giveBack,
            account
        );
    }

    function removeLiquidityOneCoin(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param tokenNumber 0 for wbtc.e(or avwbtc); 1 for renbtc.e
        /// @param lpAmount the amount of the lp to remove
        /// @param minAmount the minimum amount to return to the user
        /// @param useUnderlying true: use wbtc.e; false: use avwbtc
        (
            int128 tokenNumber,
            uint256 lpAmount,
            uint256 minAmount,
            bool useUnderlying
        ) = abi.decode(encodedData, (int128, uint256, uint256, bool));

        pullAndApprove(lpAddr, account, routerAddr, lpAmount);
        uint256 giveBack = ICurveAPoolForUseOnPolygon(routerAddr)
            .remove_liquidity_one_coin(
                lpAmount,
                tokenNumber,
                minAmount,
                useUnderlying
            );

        uint256[2] memory amounts;
        if (tokenNumber == 0) {
            amounts = [giveBack, 0];
        } else if (tokenNumber == 1) {
            amounts = [0, giveBack];
        }
        address toToken;
        if (useUnderlying) {
            toToken = underlying_coins[tokenNumber];
        } else {
            toToken = coins[tokenNumber];
        }
        IERC20(toToken).safeTransfer(account, giveBack);

        emit CurveBtcRemoveLiquidityEvent(
            lpAddr,
            lpAmount,
            [underlying_coins[0], underlying_coins[1]],
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
        emit CurveBtcDepositEvent(lpAddr, farmAddr, amountDeposit, account);
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
        emit CurveBtcWithdrawEvent(lpAddr, farmAddr, lpAmount, account);
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

        emit CurveBtcClaimRewardsEvent(
            lpAddr,
            rewardTokens,
            rewardAmounts,
            address(this)
        );
    }
}
