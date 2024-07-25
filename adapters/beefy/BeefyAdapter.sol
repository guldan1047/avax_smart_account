// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import {IBeefyVaultV6} from "../../interfaces/beefy/IBeefyVaultV6.sol";

contract BeefyAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Beefy")
    {}

    mapping(address => address) public trustMooTokenAddr;

    event BeefyWithdrawEvent(
        address token,
        address mooToken,
        uint256 amount,
        address owner
    );

    event BeefyDepositEvent(
        address token,
        address mooToken,
        uint256 amount,
        address owner
    );

    function initialize(
        address[] calldata tokenAddr,
        address[] calldata mooTokenAddr
    ) external onlyTimelock {
        require(
            tokenAddr.length > 0 && tokenAddr.length == mooTokenAddr.length,
            "Set length mismatch."
        );
        for (uint256 i = 0; i < tokenAddr.length; i++) {
            if (tokenAddr[i] == avaxAddr) {
                require(
                    IBeefyVaultV6(mooTokenAddr[i]).want() == wavaxAddr,
                    "Address mismatch."
                );
            } else {
                require(
                    IBeefyVaultV6(mooTokenAddr[i]).want() == tokenAddr[i],
                    "Address mismatch."
                );
            }
            trustMooTokenAddr[tokenAddr[i]] = mooTokenAddr[i];
        }
    }

    function deposit(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address tokenAddr, uint256 tokenAmount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        address mooTokenAddr = trustMooTokenAddr[tokenAddr];
        require(mooTokenAddr != address(0), "Token invalid.");

        pullAndApprove(tokenAddr, account, mooTokenAddr, tokenAmount);
        IBeefyVaultV6 mooToken = IBeefyVaultV6(mooTokenAddr);
        uint256 amountBefore = mooToken.balanceOf(address(this));
        mooToken.deposit(tokenAmount);
        uint256 amountDiff = mooToken.balanceOf(address(this)) - amountBefore;
        require(amountDiff >= 0, "amount error");
        mooToken.transfer(account, amountDiff);
        emit BeefyDepositEvent(tokenAddr, mooTokenAddr, tokenAmount, account);
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address tokenAddr, uint256 mooTokenAmount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        address mooTokenAddr = trustMooTokenAddr[tokenAddr];
        require(mooTokenAddr != address(0), "Token invalid.");

        pullAndApprove(mooTokenAddr, account, mooTokenAddr, mooTokenAmount);
        IERC20 token = IERC20(tokenAddr);
        uint256 amountBefore = token.balanceOf(address(this));
        IBeefyVaultV6(mooTokenAddr).withdraw(mooTokenAmount);
        uint256 amountDiff = token.balanceOf(address(this)) - amountBefore;
        require(amountDiff >= 0, "amount error");
        token.safeTransfer(account, amountDiff);
        emit BeefyWithdrawEvent(
            tokenAddr,
            mooTokenAddr,
            mooTokenAmount,
            account
        );
    }
}
