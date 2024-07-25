// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../base/AdapterBase.sol";
import "../../../interfaces/curve/ICurveAtriCrypto.sol";
import "../../../interfaces/curve/ICurveRewardsOnlyGauge.sol";
import "../../../interfaces/curve/ICurveLpToken.sol";
import "../../../interfaces/curve/IGaugeFactory.sol";

contract CurveAtriAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "CurveAtriSwap")
    {}

    address public constant routerAddr =
        0x58e57cA18B7A47112b877E31929798Cd3D703b0f;
    address public constant lpAddr = 0x1daB6560494B04473A0BE3E7D83CF3Fdf3a51828;
    address public constant farmAddr =
        0x1879075f1c055564CB968905aC404A5A01a1699A;
    address public constant guageFactory =
        0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    address public constant crvAddr =
        0x47536F17F4fF30e64A96a7555826b8f9e66ec468;
    event CurveAtriExchangeEvent(
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        address account
    );

    event CurveAtriAddLiquidityEvent(
        address lpAddress,
        address[5] tokenAddresses,
        uint256[5] addAmounts,
        uint256 lpAmount,
        address account
    );
    event CurveAtriRemoveLiquidityEvent(
        address lpAddress,
        uint256 lpRemove,
        address[5] tokenAddresses,
        uint256[5] tokenAmounts,
        address account
    );

    event CurveAtriDepositEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveAtriWithdrawEvent(
        address lpToken,
        address gauge,
        uint256 lpAmount,
        address account
    );

    event CurveAtriClaimRewardsEvent(
        address lpToken,
        address[2] rewardTokens,
        uint256[2] rewardAmounts,
        address account
    );

    address[5] public underlying_coins;

    function initialize(address[] calldata _underlying_coins)
        external
        onlyTimelock
    {
        require(_underlying_coins.length == 5, "Set length mismatch.");
        for (uint256 i = 0; i < 5; i++) {
            underlying_coins[i] = _underlying_coins[i];
        }
    }

    function exchangeUnderlying(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param fromNumber 0 for dai.e; 1 for usdc.e; 2 for usdt.e; 3 for wbtc.e; 4 for weth.e
        /// @param toNumber 0 for dai.e; 1 for usdc.e; 2 for usdt.e; 3 for wbtc.e; 4 for weth.e
        /// @param dx amount to exchange
        /// @param min_dy min amount to be exchanged out
        (uint256 fromNumber, uint256 toNumber, uint256 dx, uint256 min_dy) = abi
            .decode(encodedData, (uint256, uint256, uint256, uint256));
        pullAndApprove(underlying_coins[fromNumber], account, routerAddr, dx);
        IERC20 tokenTo = IERC20(underlying_coins[toNumber]);
        uint256 balanceBefore = tokenTo.balanceOf(account);
        ICurveAtriCrypto(routerAddr).exchange_underlying(
            fromNumber,
            toNumber,
            dx,
            min_dy,
            account
        );
        uint256 balanceAfter = tokenTo.balanceOf(account);

        emit CurveAtriExchangeEvent(
            underlying_coins[fromNumber],
            underlying_coins[toNumber],
            dx,
            balanceAfter - balanceBefore,
            account
        );
    }

    function addLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param amountsIn the amounts to add, in the order of dai.e, usdc.e, usdt.e, wbtc.e, weth.e
        /// @param minMintAmount the minimum amount of lp to be minted and returned to the user
        (uint256[5] memory amountsIn, uint256 minMintAmount) = abi.decode(
            encodedData,
            (uint256[5], uint256)
        );
        pullAndApprove(underlying_coins[0], account, routerAddr, amountsIn[0]);
        pullAndApprove(underlying_coins[1], account, routerAddr, amountsIn[1]);
        pullAndApprove(underlying_coins[2], account, routerAddr, amountsIn[2]);
        pullAndApprove(underlying_coins[3], account, routerAddr, amountsIn[3]);
        pullAndApprove(underlying_coins[4], account, routerAddr, amountsIn[4]);

        ICurveLpToken lp = ICurveLpToken(lpAddr);
        uint256 balanceBefore = lp.balanceOf(account);
        ICurveAtriCrypto(routerAddr).add_liquidity(
            amountsIn,
            minMintAmount,
            account
        );
        uint256 balanceAfter = lp.balanceOf(account);
        uint256 lpAmount = balanceAfter - balanceBefore;
        emit CurveAtriAddLiquidityEvent(
            lpAddr,
            [
                underlying_coins[0],
                underlying_coins[1],
                underlying_coins[2],
                underlying_coins[3],
                underlying_coins[4]
            ],
            amountsIn,
            lpAmount,
            account
        );
    }

    function removeLiquidity(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param removeAmount the amount of lp to remove liquidity
        /// @param minAmounts the minimum amounts of underlying tokens to return to the user
        (uint256 removeAmount, uint256[5] memory minAmounts) = abi.decode(
            encodedData,
            (uint256, uint256[5])
        );

        pullAndApprove(lpAddr, account, routerAddr, removeAmount);
        uint256[5] memory balancesBefore;

        balancesBefore[0] = IERC20(underlying_coins[0]).balanceOf(account);
        balancesBefore[1] = IERC20(underlying_coins[1]).balanceOf(account);
        balancesBefore[2] = IERC20(underlying_coins[2]).balanceOf(account);
        balancesBefore[3] = IERC20(underlying_coins[3]).balanceOf(account);
        balancesBefore[4] = IERC20(underlying_coins[4]).balanceOf(account);

        ICurveAtriCrypto(routerAddr).remove_liquidity(
            removeAmount,
            minAmounts,
            account
        );

        uint256[5] memory balancesAfter;

        balancesAfter[0] = IERC20(underlying_coins[0]).balanceOf(account);
        balancesAfter[1] = IERC20(underlying_coins[1]).balanceOf(account);
        balancesAfter[2] = IERC20(underlying_coins[2]).balanceOf(account);
        balancesAfter[3] = IERC20(underlying_coins[3]).balanceOf(account);
        balancesAfter[4] = IERC20(underlying_coins[4]).balanceOf(account);

        uint256[5] memory tokenAmounts;

        tokenAmounts[0] = balancesAfter[0] - balancesBefore[0];
        tokenAmounts[1] = balancesAfter[1] - balancesBefore[1];
        tokenAmounts[2] = balancesAfter[2] - balancesBefore[2];
        tokenAmounts[3] = balancesAfter[3] - balancesBefore[3];
        tokenAmounts[4] = balancesAfter[4] - balancesBefore[4];

        emit CurveAtriRemoveLiquidityEvent(
            lpAddr,
            removeAmount,
            [
                underlying_coins[0],
                underlying_coins[1],
                underlying_coins[2],
                underlying_coins[3],
                underlying_coins[4]
            ],
            tokenAmounts,
            account
        );
    }

    function removeLiquidityOneCoin(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        /// @param tokenNumber  0 for dai.e; 1 for usdc.e; 2 for usdt.e; 3 for wbtc.e; 4 for weth.e
        /// @param lpAmount the amount of lp to remove liquidity
        /// @param minAmount the minimum amount of the token to return to the user
        (uint256 tokenNumber, uint256 lpAmount, uint256 minAmount) = abi.decode(
            encodedData,
            (uint256, uint256, uint256)
        );

        pullAndApprove(lpAddr, account, routerAddr, lpAmount);
        IERC20 tokenGet = IERC20(underlying_coins[tokenNumber]);
        uint256 balanceBefore = IERC20(tokenGet).balanceOf(account);
        ICurveAtriCrypto(routerAddr).remove_liquidity_one_coin(
            lpAmount,
            tokenNumber,
            minAmount,
            account
        );
        uint256 balanceAfter = IERC20(tokenGet).balanceOf(account);
        uint256 tokenAmount = balanceAfter - balanceBefore;
        uint256[5] memory amounts;
        amounts[tokenNumber] = tokenAmount;
        emit CurveAtriRemoveLiquidityEvent(
            lpAddr,
            lpAmount,
            [
                underlying_coins[0],
                underlying_coins[1],
                underlying_coins[2],
                underlying_coins[3],
                underlying_coins[4]
            ],
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
        emit CurveAtriDepositEvent(lpAddr, farmAddr, amountDeposit, account);
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
        emit CurveAtriWithdrawEvent(lpAddr, farmAddr, lpAmount, account);
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

        emit CurveAtriClaimRewardsEvent(
            lpAddr,
            rewardTokens,
            rewardAmounts,
            address(this)
        );
    }
}
