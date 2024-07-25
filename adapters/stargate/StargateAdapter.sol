// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/stargate/IStargateRouter.sol";

contract StargateAdapter is AdapterBase {
    address public constant router = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    mapping(uint256 => address) public srcTokenAddr;
    mapping(uint256 => address) public srcPoolAddr;

    event Initialize(
        uint256[] srcPoolId,
        address[] srcTokenAddr,
        address[] srcPoolAddr
    );

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Stargate")
    {}

    function initialize(
        uint256[] calldata _srcPoolId,
        address[] calldata _srcTokenAddr,
        address[] calldata _srcPoolAddr
    ) external onlyTimelock {
        require(
            _srcPoolId.length == _srcTokenAddr.length &&
                _srcTokenAddr.length == _srcPoolAddr.length,
            "Set length mismatch."
        );
        for (uint256 i = 0; i < _srcPoolId.length; i++) {
            srcTokenAddr[_srcPoolId[i]] = _srcTokenAddr[i];
            srcPoolAddr[_srcPoolId[i]] = _srcPoolAddr[i];
        }

        emit Initialize(_srcPoolId, _srcTokenAddr, _srcPoolAddr);
    }

    function swap(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (
            uint16 _dstChainId,
            uint256 _srcPoolId,
            uint256 _dstPoolId,
            address payable _refundAddress,
            uint256 _amountLD,
            uint256 _minAmountLD,
            IStargateRouter.lzTxObj memory _lzTxParams,
            bytes memory _to,
            bytes memory _payload
        ) = abi.decode(
                encodedData,
                (
                    uint16,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    uint256,
                    IStargateRouter.lzTxObj,
                    bytes,
                    bytes
                )
            );
        pullAndApprove(srcTokenAddr[_srcPoolId], account, router, _amountLD);
        IStargateRouter(router).swap{value: msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            _amountLD,
            _minAmountLD,
            _lzTxParams,
            _to,
            _payload
        );
    }
}
