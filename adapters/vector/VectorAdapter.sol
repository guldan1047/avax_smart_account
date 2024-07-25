// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "../../interfaces/vector/IMasterChefVTX.sol";
import "../../interfaces/vector/IZJoe.sol";
import "../../interfaces/vector/IXPTP.sol";
import "../../interfaces/vector/IPoolHelper.sol";
import "../../interfaces/vector/IPoolHelperAVAX.sol";

interface IVectorAdapter {
    function isTrustPlatypusPool(address tokenAddr)
        external
        view
        returns (bool);
}

contract VectorAdapter is AdapterBase {
    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "Vector")
    {}

    address public constant masterChefVTX =
        0x423D0FE33031aA4456a17b150804aA57fc157d97;
    address public constant vtxAddr =
        0x5817D4F0b62A59b17f75207DA1848C2cE75e7AF4;
    address public constant joeAddr =
        0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address public constant zjoeAddr =
        0x769bfeb9fAacD6Eb2746979a8dD0b7e9920aC2A4;
    address public constant ptpAddr =
        0x22d4002028f537599bE9f666d1c4Fa138522f9c8;
    address public constant xptpAddr =
        0x060556209E507d30f2167a101bFC6D256Ed2f3e1;
    address public constant avaxPoolOnPlatypus =
        0xff5386aF93cF4bD8d5AeCad6df7F4f4be381fD69;

    mapping(address => bool) public isTrustPlatypusPool;

    function initialize(address[] calldata platypusPoolTokenAddr)
        external
        onlyTimelock
    {
        for (uint256 i = 0; i < platypusPoolTokenAddr.length; i++) {
            isTrustPlatypusPool[platypusPoolTokenAddr[i]] = true;
        }
    }

    function convert(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address token, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        if (token == joeAddr) {
            pullAndApprove(joeAddr, account, zjoeAddr, amount);
            IZJoe(zjoeAddr).depositFor(amount, account);
        } else if (token == ptpAddr) {
            pullAndApprove(ptpAddr, account, xptpAddr, amount);
            IXPTP xptp = IXPTP(xptpAddr);
            uint256 amountBefore = xptp.balanceOf(ADAPTER_ADDRESS);
            xptp.deposit(amount);
            uint256 amountDiff = xptp.balanceOf(ADAPTER_ADDRESS) - amountBefore;
            xptp.transfer(account, amountDiff);
        } else {
            revert("Invalid token!");
        }
    }

    function depositJoe(uint256 amount) external onlyDelegation {
        IZJoe zjoe = IZJoe(zjoeAddr);
        zjoe.depositFor(amount, address(this));
        if (zjoe.allowance(address(this), masterChefVTX) < amount) {
            zjoe.approve(masterChefVTX, type(uint256).max);
        }

        IMasterChefVTX(masterChefVTX).deposit(zjoeAddr, amount);
    }

    function depositPtp(uint256 amount) external onlyDelegation {
        IXPTP xptp = IXPTP(xptpAddr);
        xptp.deposit(amount);
        if (xptp.allowance(address(this), masterChefVTX) < amount) {
            xptp.approve(masterChefVTX, type(uint256).max);
        }

        IMasterChefVTX(masterChefVTX).deposit(xptpAddr, amount);
    }

    function deposit(address token, uint256 amount) external onlyDelegation {
        IMasterChefVTX(masterChefVTX).deposit(token, amount);
    }

    function withdraw(address token, uint256 amount) external onlyDelegation {
        IMasterChefVTX(masterChefVTX).withdraw(token, amount);
    }

    function multiclaim(address[] calldata _lps) external onlyDelegation {
        IMasterChefVTX(masterChefVTX).multiclaim(_lps, address(this));
    }

    function emergencyWithdraw(address token) external onlyDelegation {
        IMasterChefVTX(masterChefVTX).emergencyWithdraw(token);
    }

    function depositPlatypus(
        address pool,
        address token,
        uint256 amount
    ) external onlyDelegation {
        require(
            IVectorAdapter(ADAPTER_ADDRESS).isTrustPlatypusPool(pool),
            "Invalid pool!"
        );
        if (token == avaxAddr) {
            IPoolHelperAVAX(pool).depositAVAX{value: amount}();
        } else {
            IPoolHelper(pool).deposit(amount);
        }
    }

    function withdrawPlatypus(
        address pool,
        address token,
        uint256 amount,
        uint256 minAmount
    ) external onlyDelegation {
        require(
            IVectorAdapter(ADAPTER_ADDRESS).isTrustPlatypusPool(pool),
            "Invalid pool!"
        );
        if (pool == avaxPoolOnPlatypus && token == avaxAddr) {
            IPoolHelperAVAX(pool).withdrawAVAX(amount, minAmount);
        } else {
            IPoolHelper(pool).withdraw(amount, minAmount);
        }
    }
}
