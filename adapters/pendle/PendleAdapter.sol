// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/pendle/IPendleWrapper.sol";
import "../../interfaces/pendle/IPendleGenericMarket.sol";
import "../../interfaces/pendle/IPendleRouter.sol";
import "../../interfaces/pendle/IPendleFutureYieldToken.sol";
import "../../interfaces/traderJoe/IJoePair.sol";

contract PendleAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Pendle")
    {}

    function tokenizeYield(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 forgeId,
            address routerAddress,
            address underlyingAsset,
            address lp,
            uint256 expiry,
            uint256 amountTokenize,
            address to
        ) = abi.decode(
                encodedData,
                (bytes32, address, address, address, uint256, uint256, address)
            );
        pullAndApprove(lp, to, routerAddress, amountTokenize);

        IPendleRouter router = IPendleRouter(routerAddress);
        (address ot_address, address xyt_address, uint256 amountMinted) = router
            .tokenizeYield(
                forgeId,
                underlyingAsset,
                expiry,
                amountTokenize,
                to
            );
    }

    function redeemUnderlying(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 forgeId,
            address routerAddress,
            address underlyingAsset,
            address lpAddress,
            address otAddress,
            address ytAddress,
            uint256 expiry,
            uint256 amountRedeem,
            address to
        ) = abi.decode(
                encodedData,
                (
                    bytes32,
                    address,
                    address,
                    address,
                    address,
                    address,
                    uint256,
                    uint256,
                    address
                )
            );
        pullAndApprove(otAddress, to, routerAddress, amountRedeem);
        pullAndApprove(ytAddress, to, routerAddress, amountRedeem);
        IERC20 lp = IERC20(lpAddress);

        IPendleRouter router = IPendleRouter(routerAddress);
        uint256 redeemAmount = router.redeemUnderlying(
            forgeId,
            underlyingAsset,
            expiry,
            amountRedeem
        );
        lp.safeTransfer(to, redeemAmount);
    }

    function redeemDueInterests(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 forgeId,
            address routerAddress,
            address underlyingAsset,
            uint256 expiry,
            address user
        ) = abi.decode(
                encodedData,
                (bytes32, address, address, uint256, address)
            );
        IPendleRouter router = IPendleRouter(routerAddress);
        uint256 interests = router.redeemDueInterests(
            forgeId,
            underlyingAsset,
            expiry,
            user
        );
    }

    function redeemLpInterests(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address routerAddress, address market_address, address user) = abi
            .decode(encodedData, (address, address, address));
        IPendleRouter router = IPendleRouter(routerAddress);
        uint256 interests = router.redeemLpInterests(market_address, user);
    }

    function addMarketLiquidityDual(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 marketFactoryId,
            // address routerAddress,
            // address yt_address,
            // address liquidity_token_address,
            // address yt_lp_address,
            // address user,
            address[] memory addresses,
            uint256 desiredXytAmount,
            uint256 desiredTokenAmount,
            uint256 xytMinAmount,
            uint256 tokenMinAmount
        ) = abi.decode(
                encodedData,
                (bytes32, address[], uint256, uint256, uint256, uint256)
            );

        pullAndApprove(
            addresses[1],
            addresses[4],
            addresses[0],
            desiredXytAmount
        );
        pullAndApprove(
            addresses[2],
            addresses[4],
            addresses[0],
            desiredTokenAmount
        );
        IPendleGenericMarket market = IPendleGenericMarket(addresses[3]);
        IERC20 liquidity_token = IERC20(addresses[2]);
        IPendleFutureYieldToken yt = IPendleFutureYieldToken(addresses[1]);

        IPendleRouter router = IPendleRouter(addresses[0]);
        (uint256 amountXytUsed, uint256 amountTokenUsed, uint256 lpOut) = router
            .addMarketLiquidityDual(
                marketFactoryId,
                addresses[1],
                addresses[2],
                desiredXytAmount,
                desiredTokenAmount,
                xytMinAmount,
                tokenMinAmount
            );

        yt.transfer(addresses[4], desiredXytAmount - amountXytUsed);
        liquidity_token.safeTransfer(
            addresses[4],
            desiredTokenAmount - amountTokenUsed
        );
        market.transfer(addresses[4], lpOut);
    }

    function addMarketLiquiditySingle(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 marketFactoryId,
            // address routerAddress,
            // address yt_address,
            // address liquidity_token_address,
            // address yt_lp_address,
            // address user,
            address[] memory addresses,
            bool forXyt,
            uint256 exactIn,
            uint256 minOutLp
        ) = abi.decode(
                encodedData,
                (bytes32, address[], bool, uint256, uint256)
            );
        if (forXyt) {
            pullAndApprove(addresses[1], addresses[4], addresses[0], exactIn);
        } else {
            pullAndApprove(addresses[2], addresses[4], addresses[0], exactIn);
        }
        IPendleGenericMarket market = IPendleGenericMarket(addresses[3]);

        IPendleRouter router = IPendleRouter(addresses[0]);
        uint256 exactOutLp = router.addMarketLiquiditySingle(
            marketFactoryId,
            addresses[1],
            addresses[2],
            forXyt,
            exactIn,
            minOutLp
        );

        market.transfer(addresses[4], exactOutLp);
    }

    function removeMarketLiquidityDual(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 marketFactoryId,
            // address routerAddress,
            // address yt_address,
            // address liquidity_token_address,
            // address yt_lp_address,
            // address user,
            address[] memory addresses,
            uint256 exactInLp,
            uint256 minOutXyt,
            uint256 minOutToken
        ) = abi.decode(
                encodedData,
                (bytes32, address[], uint256, uint256, uint256)
            );

        pullAndApprove(addresses[3], addresses[4], addresses[0], exactInLp);

        IERC20 liquidity_token = IERC20(addresses[2]);
        IPendleFutureYieldToken yt = IPendleFutureYieldToken(addresses[1]);

        IPendleRouter router = IPendleRouter(addresses[0]);
        (uint256 exactOutXyt, uint256 exactOutToken) = router
            .removeMarketLiquidityDual(
                marketFactoryId,
                addresses[1],
                addresses[2],
                exactInLp,
                minOutXyt,
                minOutToken
            );

        yt.transfer(addresses[4], exactOutXyt);
        liquidity_token.safeTransfer(addresses[4], exactOutToken);
    }

    function removeMarketLiquiditySingle(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            bytes32 marketFactoryId,
            // address routerAddress,
            // address yt_address,
            // address liquidity_token_address,
            // address yt_lp_address,
            // address user,
            address[] memory addresses,
            bool forXyt,
            uint256 exactInLp,
            uint256 minOutAsset
        ) = abi.decode(
                encodedData,
                (bytes32, address[], bool, uint256, uint256)
            );
        pullAndApprove(addresses[3], addresses[4], addresses[0], exactInLp);

        IERC20 liquidity_token = IERC20(addresses[2]);
        IPendleFutureYieldToken yt = IPendleFutureYieldToken(addresses[1]);

        IPendleRouter router = IPendleRouter(addresses[0]);
        (uint256 exactOutXyt, uint256 exactOutToken) = router
            .removeMarketLiquiditySingle(
                marketFactoryId,
                addresses[1],
                addresses[2],
                forXyt,
                exactInLp,
                minOutAsset
            );

        if (forXyt) {
            yt.transfer(addresses[4], exactOutXyt);
        } else {
            liquidity_token.safeTransfer(addresses[4], exactOutToken);
        }
    }

    function swapExactIn(bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            address routerAddress,
            address tokenInAddress,
            address tokenOutAddress,
            address userAddress,
            uint256 inAmount,
            uint256 minOutAmount,
            bytes32 marketFactoryId
        ) = abi.decode(
                encodedData,
                (address, address, address, address, uint256, uint256, bytes32)
            );

        IERC20 tokenOut = IERC20(tokenOutAddress);

        IPendleRouter router = IPendleRouter(routerAddress);
        uint256 outSwapAmount = router.swapExactIn(
            tokenInAddress,
            tokenOutAddress,
            inAmount,
            minOutAmount,
            marketFactoryId
        );
        tokenOut.safeTransfer(userAddress, outSwapAmount);
    }
}
