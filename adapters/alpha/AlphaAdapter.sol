// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/alpha/ISafeBox.sol";
import "../../interfaces/alpha/ISafeBoxAVAX.sol";
import "../../interfaces/IWAVAX.sol";
import "../../interfaces/alpha/IHomoraBank.sol";
import "../../interfaces/alpha/IUnilikeSpell.sol";
import "../../interfaces/alpha/ILendReward.sol";

contract AlphaAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    address public constant homoraBankAddr =
        0x376d16C7dE138B01455a51dA79AD65806E9cd694;
    address public constant lendRewardAddr =
        0x7424DDc7Ac9f60B3d0f7bCA9e438Dc2c1D44d043;
    mapping(address => address) public trustIbTokenAddr;

    uint256 positionIdNext;

    struct Position {
        address owner; // The account of this position.
        uint256 homoraBankId; // The positionId in homoraBank contract.
    }

    mapping(uint256 => Position) public PositionInfo;
    mapping(address => uint256[]) public adapterPositionIds;

    event AlphaExecute(
        address account,
        uint256 adapterPositionId,
        uint256 homoraBankId
    );

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Alpha")
    {
        positionIdNext = 10;
    }

    function initialize(
        address[] calldata tokenAddr,
        address[] calldata ibTokenAddr
    ) external onlyTimelock {
        require(
            tokenAddr.length > 0 && tokenAddr.length == ibTokenAddr.length,
            "Set length mismatch."
        );
        for (uint256 i = 0; i < tokenAddr.length; i++) {
            if (tokenAddr[i] == avaxAddr || tokenAddr[i] == wavaxAddr) {
                require(
                    ISafeBoxAVAX(ibTokenAddr[i]).weth() == wavaxAddr,
                    "Address mismatch."
                );
            } else {
                require(
                    ISafeBox(ibTokenAddr[i]).uToken() == tokenAddr[i],
                    "Address mismatch."
                );
            }
            trustIbTokenAddr[tokenAddr[i]] = ibTokenAddr[i];
        }
    }

    function deposit(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (address tokenAddr, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        require(trustIbTokenAddr[tokenAddr] != address(0), "Token invalid.");
        IERC20 ibToken = IERC20(trustIbTokenAddr[tokenAddr]);
        uint256 tokenBefore = ibToken.balanceOf(address(this));
        if (tokenAddr == avaxAddr) {
            require(
                ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).weth() == wavaxAddr,
                "Not AVAX."
            );
            ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).deposit{
                value: msg.value
            }();
        } else if (tokenAddr == wavaxAddr) {
            require(
                ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).weth() == wavaxAddr,
                "Not WAVAX."
            );
            pullAndApprove(
                tokenAddr,
                account,
                trustIbTokenAddr[tokenAddr],
                amount
            );
            IWAVAX(wavaxAddr).withdraw(amount);
            ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).deposit{value: amount}();
        } else {
            require(
                ISafeBox(trustIbTokenAddr[tokenAddr]).uToken() == tokenAddr,
                "Not token."
            );
            pullAndApprove(
                tokenAddr,
                account,
                trustIbTokenAddr[tokenAddr],
                amount
            );
            ISafeBox(trustIbTokenAddr[tokenAddr]).deposit(amount);
        }
        uint256 tokenDiff = ibToken.balanceOf(address(this)) - tokenBefore;
        ibToken.safeTransfer(account, tokenDiff);
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address tokenAddr, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        require(trustIbTokenAddr[tokenAddr] != address(0), "Token invalid.");

        if (tokenAddr == avaxAddr || tokenAddr == wavaxAddr) {
            require(
                ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).weth() == wavaxAddr,
                "Not AVAX."
            );
            pullAndApprove(
                trustIbTokenAddr[tokenAddr],
                account,
                trustIbTokenAddr[tokenAddr],
                amount
            );
            uint256 amountBefore = address(this).balance;
            ISafeBoxAVAX(trustIbTokenAddr[tokenAddr]).withdraw(amount);
            uint256 amountDiff = address(this).balance - amountBefore;
            require(amountDiff > 0, "amount error");
            if (tokenAddr == avaxAddr) {
                safeTransferAVAX(account, amountDiff);
            } else {
                IWAVAX(wavaxAddr).deposit{value: amountDiff}();
                IWAVAX(wavaxAddr).transfer(account, amountDiff);
            }
        } else {
            require(
                ISafeBox(trustIbTokenAddr[tokenAddr]).uToken() == tokenAddr,
                "Not token."
            );
            pullAndApprove(
                trustIbTokenAddr[tokenAddr],
                account,
                trustIbTokenAddr[tokenAddr],
                amount
            );
            IERC20 token = IERC20(tokenAddr);
            uint256 tokenBefore = token.balanceOf(address(this));
            ISafeBox(trustIbTokenAddr[tokenAddr]).withdraw(amount);
            uint256 tokenDiff = token.balanceOf(address(this)) - tokenBefore;
            token.safeTransfer(account, tokenDiff);
        }
    }

    function executeCallHomoraBank(
        address account,
        HomoraBankData memory data,
        address[3] memory tokenAddresses,
        uint256[3] memory tokenAmountConsumption
    ) internal returns (uint256 returnId) {
        IERC20 tokenA = IERC20(tokenAddresses[0]);
        uint256 tokenABefore = tokenA.balanceOf(address(this)) -
            tokenAmountConsumption[0];

        IERC20 tokenB = IERC20(tokenAddresses[1]);
        uint256 tokenBBefore = tokenB.balanceOf(address(this)) -
            tokenAmountConsumption[1];

        IERC20 lpToken = IERC20(tokenAddresses[2]);
        uint256 lpTokenBefore = lpToken.balanceOf(address(this)) -
            tokenAmountConsumption[2];

        bytes memory spellBytes = abi.encodePacked(
            data.spellSelector,
            data.spellArgs
        );

        uint256 valueBefore = address(this).balance - msg.value;
        returnId = IHomoraBank(homoraBankAddr).execute{value: msg.value}(
            data.homoraBankId,
            data.spellAddr,
            spellBytes
        );
        safeTransferAVAX(account, address(this).balance - valueBefore);
        tokenA.safeTransfer(
            account,
            tokenA.balanceOf(address(this)) - tokenABefore
        );
        tokenB.safeTransfer(
            account,
            tokenB.balanceOf(address(this)) - tokenBBefore
        );
        lpToken.safeTransfer(
            account,
            lpToken.balanceOf(address(this)) - lpTokenBefore
        );
    }

    struct Amounts {
        uint256 amtAUser; // Supplied tokenA amount
        uint256 amtBUser; // Supplied tokenB amount
        uint256 amtLPUser; // Supplied LP token amount
        uint256 amtABorrow; // Borrow tokenA amount
        uint256 amtBBorrow; // Borrow tokenB amount
        uint256 amtLPBorrow; // Borrow LP token amount
        uint256 amtAMin; // Desired tokenA amount (slippage control)
        uint256 amtBMin; // Desired tokenB amount (slippage control)
    }

    function addLiquidityInternal(address account, HomoraBankData memory data)
        internal
        returns (uint256 returnId)
    {
        (address tokenA, address tokenB, Amounts memory amounts, ) = abi.decode(
            data.spellArgs,
            (address, address, Amounts, uint256)
        );

        pullAndApprove(tokenA, account, homoraBankAddr, amounts.amtAUser);
        pullAndApprove(tokenB, account, homoraBankAddr, amounts.amtBUser);
        address lpToken = IUnilikeSpell(data.spellAddr).getAndApprovePair(
            tokenA,
            tokenB
        );
        pullAndApprove(lpToken, account, homoraBankAddr, amounts.amtLPUser);

        address[3] memory tokenAddresses = [tokenA, tokenB, lpToken];

        uint256[3] memory tokenAmountConsumption = [
            amounts.amtAUser,
            amounts.amtBUser,
            amounts.amtLPUser
        ];

        returnId = executeCallHomoraBank(
            account,
            data,
            tokenAddresses,
            tokenAmountConsumption
        );
    }

    struct RepayAmounts {
        uint256 amtLPTake; // Take out LP token amount (from Homora)
        uint256 amtLPWithdraw; // Withdraw LP token amount (back to caller)
        uint256 amtARepay; // Repay tokenA amount
        uint256 amtBRepay; // Repay tokenB amount
        uint256 amtLPRepay; // Repay LP token amount
        uint256 amtAMin; // Desired tokenA amount
        uint256 amtBMin; // Desired tokenB amount
    }

    function removeLiquidityInternal(
        address account,
        HomoraBankData memory data
    ) internal returns (uint256 returnId) {
        (address tokenA, address tokenB, ) = abi.decode(
            data.spellArgs,
            (address, address, RepayAmounts)
        );

        address lpTokenAddr = IUnilikeSpell(data.spellAddr).getAndApprovePair(
            tokenA,
            tokenB
        );

        address[3] memory tokenAddresses = [tokenA, tokenB, lpTokenAddr];

        uint256[3] memory tokenAmountConsumption = [
            uint256(0),
            uint256(0),
            uint256(0)
        ];

        returnId = executeCallHomoraBank(
            account,
            data,
            tokenAddresses,
            tokenAmountConsumption
        );
    }

    struct HomoraBankData {
        address spellAddr;
        bytes4 spellSelector;
        bytes spellArgs;
        uint256 homoraBankId;
    }

    function execute(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (
            bool isAdd,
            uint256 adapterPositionId,
            address spellAddr,
            bytes4 spellSelector,
            bytes memory spellArgs
        ) = abi.decode(encodedData, (bool, uint256, address, bytes4, bytes));
        if (adapterPositionId == 0) {
            adapterPositionId = positionIdNext++;
            PositionInfo[adapterPositionId].owner = account;
        } else {
            require(
                adapterPositionId < positionIdNext,
                "position id not exists"
            );
            require(
                account == PositionInfo[adapterPositionId].owner,
                "not position account"
            );
        }
        uint256 homoraBankId = PositionInfo[adapterPositionId].homoraBankId;
        HomoraBankData memory data = HomoraBankData(
            spellAddr,
            spellSelector,
            spellArgs,
            homoraBankId
        );
        if (isAdd) {
            uint256 returnId = addLiquidityInternal(account, data);
            if (homoraBankId == 0) {
                PositionInfo[adapterPositionId].homoraBankId = returnId;
                adapterPositionIds[account].push(adapterPositionId);
            }
        } else {
            require(homoraBankId != 0, "position id not exists");
            removeLiquidityInternal(account, data);
        }
        emit AlphaExecute(account, adapterPositionId, homoraBankId);
    }

    function getAdapterPositionInfo(uint256 adapterPositionId)
        external
        view
        returns (
            uint256 homoraBankId,
            address account,
            address collToken,
            uint256 collId,
            uint256 collateralSize
        )
    {
        homoraBankId = PositionInfo[adapterPositionId].homoraBankId;
        (, collToken, collId, collateralSize) = IHomoraBank(homoraBankAddr)
            .getPositionInfo(homoraBankId);
        account = PositionInfo[adapterPositionId].owner;
    }

    // function getAdapterPositionIds(address account)
    //     external
    //     view
    //     returns (uint256[] memory)
    // {
    //     return adapterPositionIds[account];
    // }

    function claim(uint256 reward, bytes32[] memory proof)
        external
        onlyDelegation
    {
        ILendReward(lendRewardAddr).claim(address(this), reward, proof);
    }
}
