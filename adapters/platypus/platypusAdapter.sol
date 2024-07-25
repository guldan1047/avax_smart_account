// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/platypus/IPlatypusMainPoolRouter.sol";
import "../../interfaces/platypus/IPlatypussavaxPoolRouter.sol";
import "../../interfaces/platypus/IMasterPlatypusV3.sol";
import "../../interfaces/platypus/Iveptp.sol";

contract PlatypusAdapter is AdapterBase {
    address public constant farmAddress =
        0x68c5f4374228BEEdFa078e77b5ed93C28a2f713E;

    address public constant veptpAddress =
        0x5857019c749147EEE22b1Fe63500F237F3c1B692;

    mapping(address => bool) public allowedRouters;
    mapping(address => bool) public allowedTokens;
    mapping(address => bool) public allowedAssets;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Platypus")
    {}

    function initialize(
        address[] calldata _allowedRouters,
        address[] calldata _allowedTokens,
        address[] calldata _allowedAssets
    ) external onlyTimelock {
        for (uint256 i = 0; i < _allowedRouters.length; i++) {
            allowedRouters[_allowedRouters[i]] = true;
        }
        for (uint256 i = 0; i < _allowedTokens.length; i++) {
            allowedTokens[_allowedTokens[i]] = true;
        }
        for (uint256 i = 0; i < _allowedAssets.length; i++) {
            allowedAssets[_allowedAssets[i]] = true;
        }
    }

    event PlatypusSwapEvent(
        address fromAddress,
        address toAddress,
        uint256 actualToAmount,
        address router,
        address account
    );

    event PlatypusDepositEvent(
        address token,
        address asset,
        uint256 tokenAmount,
        uint256 liquidity,
        address router,
        address account
    );

    event PlatypusWithdrawEvent(
        address token,
        address asset,
        uint256 tokenAmount,
        uint256 liquidity,
        address router,
        address account
    );

    event PlatypusStakeEvent(
        uint256 pid,
        uint256 amount,
        uint256 receivedPTP,
        address farmAddress,
        address account
    );

    event PlatypusUnstakeEvent(
        uint256 pid,
        uint256 amount,
        uint256 receivedPTP,
        address farmAddress,
        address account
    );

    struct swapInfoStruct {
        address routerAddress;
        address fromAddress;
        address toAddress;
        uint256 swapAmount;
        uint256 minimumToAmount;
        bool useETH;
        bool receiveETH;
        uint256 deadline;
    }

    function swap(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        swapInfoStruct memory swapInfo = abi.decode(
            encodedData,
            (swapInfoStruct)
        );
        require(allowedRouters[swapInfo.routerAddress], "router not supported");
        require(
            allowedTokens[swapInfo.fromAddress],
            "token address not supported"
        );
        require(
            allowedTokens[swapInfo.toAddress],
            "token address not supported"
        );

        if (swapInfo.useETH) {
            (uint256 actualToAmount, ) = IPlatypussavaxPoolRouter(
                swapInfo.routerAddress
            ).swapFromETH{value: msg.value}(
                swapInfo.toAddress,
                swapInfo.minimumToAmount,
                account,
                swapInfo.deadline
            );
            emit PlatypusSwapEvent(
                avaxAddr,
                swapInfo.toAddress,
                actualToAmount,
                swapInfo.routerAddress,
                account
            );
            return;
        } else {
            pullAndApprove(
                swapInfo.fromAddress,
                account,
                swapInfo.routerAddress,
                swapInfo.swapAmount
            );
            if (swapInfo.receiveETH) {
                (uint256 actualToAmount, ) = IPlatypussavaxPoolRouter(
                    swapInfo.routerAddress
                ).swapToETH(
                        swapInfo.fromAddress,
                        swapInfo.swapAmount,
                        swapInfo.minimumToAmount,
                        account,
                        swapInfo.deadline
                    );
                emit PlatypusSwapEvent(
                    swapInfo.fromAddress,
                    avaxAddr,
                    actualToAmount,
                    swapInfo.routerAddress,
                    account
                );
                return;
            } else {
                (uint256 actualToAmount, ) = IPlatypusMainPoolRouter(
                    swapInfo.routerAddress
                ).swap(
                        swapInfo.fromAddress,
                        swapInfo.toAddress,
                        swapInfo.swapAmount,
                        swapInfo.minimumToAmount,
                        account,
                        swapInfo.deadline
                    );
                emit PlatypusSwapEvent(
                    swapInfo.fromAddress,
                    swapInfo.toAddress,
                    actualToAmount,
                    swapInfo.routerAddress,
                    account
                );
                return;
            }
        }
    }

    function deposit(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (
            address routerAddress,
            address tokenAddress,
            address assetAddress,
            uint256 depositAmount,
            bool useETH,
            uint256 deadline
        ) = abi.decode(
                encodedData,
                (address, address, address, uint256, bool, uint256)
            );

        if (useETH) {
            uint256 liquidity = IPlatypussavaxPoolRouter(routerAddress)
                .depositETH{value: msg.value}(account, deadline);
            emit PlatypusDepositEvent(
                avaxAddr,
                assetAddress,
                depositAmount,
                liquidity,
                routerAddress,
                account
            );
            return;
        } else {
            pullAndApprove(tokenAddress, account, routerAddress, depositAmount);
            uint256 liquidity = IPlatypusMainPoolRouter(routerAddress).deposit(
                tokenAddress,
                depositAmount,
                account,
                deadline
            );

            emit PlatypusDepositEvent(
                tokenAddress,
                assetAddress,
                depositAmount,
                liquidity,
                routerAddress,
                account
            );
            return;
        }
    }

    struct withdrawInfoStruct {
        address routerAddress;
        address tokenAddress;
        address assetAddress;
        uint256 liquidity;
        uint256 minAmount;
        bool receiveETH;
        uint256 deadline;
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        withdrawInfoStruct memory withdrawInfo = abi.decode(
            encodedData,
            (withdrawInfoStruct)
        );
        pullAndApprove(
            withdrawInfo.assetAddress,
            account,
            withdrawInfo.routerAddress,
            withdrawInfo.liquidity
        );
        if (withdrawInfo.receiveETH) {
            uint256 withdrawAmount = IPlatypussavaxPoolRouter(
                withdrawInfo.routerAddress
            ).withdrawETH(
                    withdrawInfo.liquidity,
                    withdrawInfo.minAmount,
                    account,
                    withdrawInfo.deadline
                );
            emit PlatypusWithdrawEvent(
                avaxAddr,
                withdrawInfo.assetAddress,
                withdrawAmount,
                withdrawInfo.liquidity,
                withdrawInfo.routerAddress,
                account
            );
            return;
        } else {
            uint256 withdrawAmount = IPlatypusMainPoolRouter(
                withdrawInfo.routerAddress
            ).withdraw(
                    withdrawInfo.tokenAddress,
                    withdrawInfo.liquidity,
                    withdrawInfo.minAmount,
                    account,
                    withdrawInfo.deadline
                );
            emit PlatypusWithdrawEvent(
                withdrawInfo.tokenAddress,
                withdrawInfo.assetAddress,
                withdrawAmount,
                withdrawInfo.liquidity,
                withdrawInfo.routerAddress,
                account
            );
            return;
        }
    }

    function stake(uint256 pid, uint256 depositAmount) external onlyDelegation {
        require(
            pid != 3 && pid != 8 && pid != 9 && pid != 14 && pid != 15,
            "Pool Deprecated."
        );
        (uint256 receivedPTP, ) = IMasterPlatypusV3(farmAddress).deposit(
            pid,
            depositAmount
        );
        emit PlatypusStakeEvent(
            pid,
            depositAmount,
            receivedPTP,
            farmAddress,
            address(this)
        );
    }

    function unstake(uint256 pid, uint256 unstakeAmount)
        external
        onlyDelegation
    {
        (uint256 receivedPTP, ) = IMasterPlatypusV3(farmAddress).withdraw(
            pid,
            unstakeAmount
        );
        emit PlatypusUnstakeEvent(
            pid,
            unstakeAmount,
            receivedPTP,
            farmAddress,
            address(this)
        );
    }
}
