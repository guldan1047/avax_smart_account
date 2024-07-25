// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/IWAVAX.sol";
import "../../interfaces/anchor/IAnchorBridge.sol";
import "../../interfaces/anchor/IWormholeTokenBridge.sol";

contract AnchorAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Anchor")
    {}

    address public constant bridgeAddress =
        0x95aE712C309D33de0250Edd0C2d7Cb1ceAFD4550;
    address public constant wormholeTokenBridge =
        0x0e082F06FF657D94310cB8cE8B0D9a04541d8052;

    function lockCollateral(address token, uint256 amount)
        external
        onlyDelegation
    {
        IAnchorBridge(bridgeAddress).lockCollateral(token, amount);
    }

    function unlockCollateral(bytes32 tokenTerraAddress, uint128 amount)
        external
        onlyDelegation
    {
        // tokenTerraAddress: "0x0000000000000000000000001472acd641b566f3084efd9184b305a0714fb40f" for savax
        IAnchorBridge(bridgeAddress).unlockCollateral(
            tokenTerraAddress,
            amount
        );
    }

    // not tested
    function borrowStable(uint256 amount) external onlyDelegation {
        IAnchorBridge(bridgeAddress).borrowStable(amount);
    }

    // not tested
    function lockAndBorrow(
        address token,
        uint256 lockAmount,
        uint256 borrowAmount
    ) external onlyDelegation {
        IAnchorBridge(bridgeAddress).lockAndBorrow(
            token,
            lockAmount,
            borrowAmount
        );
    }

    function depositStable(address token, uint256 amount)
        external
        onlyDelegation
    {
        IAnchorBridge(bridgeAddress).depositStable(token, amount);
    }

    function repayStable(address token, uint256 amount)
        external
        onlyDelegation
    {
        IAnchorBridge(bridgeAddress).repayStable(token, amount);
    }

    function redeemStable(address token, uint256 amount)
        external
        onlyDelegation
    {
        IAnchorBridge(bridgeAddress).redeemStable(token, amount);
    }

    // not tested
    function claimRewards() external onlyDelegation {
        IAnchorBridge(bridgeAddress).claimRewards();
    }

    // not tested
    function processTokenTransferInstruction(
        bytes calldata encodedIncomingTokenTransferInfo,
        bytes calldata encodedTokenTransfer
    ) external onlyDelegation {
        IAnchorBridge(bridgeAddress).processTokenTransferInstruction(
            encodedIncomingTokenTransferInfo,
            encodedTokenTransfer
        );
    }
}
