// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/defrost/ICollateralVault.sol";
import "../../interfaces/defrost/ISmeltSavingsFarm.sol";

contract DefrostAdapter is AdapterBase {
    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Defrost")
    {}

    /// @dev add collateral
    function join(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        ICollateralVault(stakePoolAddr).join(address(this), amount);
    }

    /// @dev mint H2O
    function mintSystemCoin(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        ICollateralVault(stakePoolAddr).mintSystemCoin(address(this), amount);
    }

    /// @dev add collateral and mint H2O
    function joinAndMint(
        address stakePoolAddr,
        uint256 collateralAmount,
        uint256 systemCoinAmount
    ) external onlyDelegation {
        ICollateralVault(stakePoolAddr).joinAndMint(
            collateralAmount,
            systemCoinAmount
        );
    }

    /// @dev add collateral using AVAX, and mint H2O
    function joinAndMintAVAX(
        address stakePoolAddr,
        uint256 collateralAmount,
        uint256 systemCoinAmount
    ) external onlyDelegation {
        ICollateralVault(stakePoolAddr).joinAndMint{value: collateralAmount}(
            collateralAmount,
            systemCoinAmount
        );
    }

    /// @dev repay H2O
    function repaySystemCoin(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        ICollateralVault(stakePoolAddr).repaySystemCoin(address(this), amount);
    }

    /// @dev deposit MELT or other lp tokens
    function deposit(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        ISmeltSavingsFarm(stakePoolAddr).deposit(amount);
    }

    /// @dev withdraw the deposits
    function withdraw(address stakePoolAddr, uint256 amount)
        external
        onlyDelegation
    {
        ISmeltSavingsFarm(stakePoolAddr).withdraw(amount);
    }
}
