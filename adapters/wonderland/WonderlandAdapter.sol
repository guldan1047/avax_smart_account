// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/wonderland/ITimeBondDepository.sol";
import "../../interfaces/wonderland/IStakingHelper.sol";
import "../../interfaces/wonderland/ITimeStaking.sol";

contract WonderlandAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    address public constant timeAddr =
        0xb54f16fB19478766A268F172C9480f8da1a7c9C3;
    address public constant memoAddr =
        0x136Acd46C134E8269052c62A67042D6bDeDde3C9;
    address public constant stakePoolAddr =
        0x096BBfB78311227b805c968b070a81D358c13379;
    address public constant timeStakingAddr =
        0x4456B87Af11e87E329AB7d7C7A246ed1aC2168B9;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Wonderland")
    {}

    function stake(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        uint256 amount = abi.decode(encodedData, (uint256));
        pullAndApprove(timeAddr, account, stakePoolAddr, amount);
        IStakingHelper(stakePoolAddr).stake(amount, account);
    }

    function unstake(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        uint256 amount = abi.decode(encodedData, (uint256));
        pullAndApprove(memoAddr, account, timeStakingAddr, amount);
        IERC20 time = IERC20(timeAddr);
        uint256 unstakeBefore = time.balanceOf(address(this));
        ITimeStaking(timeStakingAddr).unstake(amount, true);
        uint256 unstakeAfter = time.balanceOf(address(this));
        time.safeTransfer(account, unstakeAfter - unstakeBefore);
    }

    function deposit(bytes calldata encodedData) external onlyDelegation {
        (address poolAddr, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        ITimeBondDepository depository = ITimeBondDepository(poolAddr);
        depository.deposit(amount, depository.bondPrice(), address(this));
    }

    /// @dev deposit using AVAX
    function depositAVAX(bytes calldata encodedData) external onlyDelegation {
        (address poolAddr, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        ITimeBondDepository depository = ITimeBondDepository(poolAddr);
        depository.deposit{value: amount}(
            amount,
            depository.bondPrice(),
            address(this)
        );
    }

    function redeem(bytes calldata encodedData) external onlyDelegation {
        (address poolAddr, address recipient, bool stakeFlag) = abi.decode(
            encodedData,
            (address, address, bool)
        );
        uint256 amountOut = ITimeBondDepository(poolAddr).redeem(
            recipient,
            stakeFlag
        );
    }
}
