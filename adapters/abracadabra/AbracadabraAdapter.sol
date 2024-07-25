// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/abracadabra/ISorbettiere.sol";
import "../../interfaces/abracadabra/IBentoBoxV1.sol";
import "../../interfaces/abracadabra/ICauldronV2.sol";

contract AbracadabraAdapter is AdapterBase {
    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Abracadabra")
    {}

    address public constant sorbettiereAddr =
        0x06408571E0aD5e8F52eAd01450Bde74E5074dC74;

    function deposit(uint256 tokenType, uint256 amount)
        external
        onlyDelegation
    {
        ISorbettiere(sorbettiereAddr).deposit(tokenType, amount);
    }

    function withdraw(uint256 tokenType, uint256 amount)
        external
        onlyDelegation
    {
        ISorbettiere(sorbettiereAddr).withdraw(tokenType, amount);
    }

    function harvest() external onlyDelegation {
        ISorbettiere(sorbettiereAddr).claimOwnership();
    }

    function setMasterContractApproval(address boxAddr, address masterContract)
        external
        onlyDelegation
    {
        IBentoBoxV1(boxAddr).setMasterContractApproval(
            (address(this)),
            masterContract,
            true,
            0,
            0,
            0
        );
    }

    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas,
        address cauldronAddr
    ) external onlyDelegation {
        uint256 totalValue;
        for (uint256 i = 0; i < values.length; i++) {
            totalValue += values[i];
        }
        ICauldronV2(cauldronAddr).cook{value: totalValue}(
            actions,
            values,
            datas
        );
    }
}
