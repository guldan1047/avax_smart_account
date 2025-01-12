// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../base/AdapterBase.sol";
import "./VerifierBasic.sol";
import "../../interfaces/traderJoe/IJoeRouter02.sol";

/*
Users deposit some token as gas fee to support automatic contract calls in the background
*/
contract Verifier is VerifierBasic {
    function getMessageHash(
        address _account,
        address _token,
        uint256 _amount,
        bool _access,
        uint256 _deadline,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _account,
                    _token,
                    _amount,
                    _access,
                    _deadline,
                    _nonce
                )
            );
    }

    function verify(
        address _signer,
        address _account,
        address _token,
        uint256 _amount,
        bool _access,
        uint256 _deadline,
        bytes memory signature
    ) internal returns (bool) {
        require(_deadline >= block.timestamp, "Signature expired");
        bytes32 messageHash = getMessageHash(
            _account,
            _token,
            _amount,
            _access,
            _deadline,
            nonces[_account]++
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        return recoverSigner(ethSignedMessageHash, signature) == _signer;
    }
}

contract FeeBoxToken is Verifier, AdapterBase {
    using SafeERC20 for IERC20;

    event FeeBoxTokenDeposit(
        address account,
        uint256 amount,
        uint256 consumedAmount
    );
    event FeeBoxTokenWithdraw(
        address account,
        uint256 amount,
        uint256 consumedAmount
    );

    address public balanceController;
    address public feeReceiver;
    address public feeTokenAddr;
    address public swapRouter;

    mapping(address => uint256) public tokenBlance;

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "feeBoxToken")
    {}

    function initialize(
        address _balanceController,
        address _feeReceiver,
        address _feeTokenAddr,
        address _swapRouter
    ) external onlyTimelock {
        balanceController = _balanceController;
        feeReceiver = _feeReceiver;
        feeTokenAddr = _feeTokenAddr;
        swapRouter = _swapRouter;
    }

    modifier onlySigner() {
        require(balanceController == msg.sender, "!Signer");
        _;
    }

    function setAdapterManager(address newAdapterManger) external onlyTimelock {
        ADAPTER_MANAGER = newAdapterManger;
    }

    function setBalance(address[] memory users, uint256[] memory balance)
        external
        onlySigner
    {
        require(users.length == balance.length, "length error!");
        for (uint256 i = 0; i < users.length; i++) {
            tokenBlance[users[i]] = balance[i];
        }
    }

    function _paymentCheck(address account, uint256 consumedAmount) internal {
        if (consumedAmount != 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (feeTokenAddr, wavaxAddr);
            uint256[] memory amounts = IJoeRouter02(swapRouter).getAmountsIn(
                consumedAmount,
                path
            );
            require(tokenBlance[account] >= amounts[0], "Insolvent!");
            approveToken(feeTokenAddr, swapRouter, amounts[0]);
            uint256[] memory amountsResult = IJoeRouter02(swapRouter)
                .swapTokensForExactAVAX(
                    consumedAmount,
                    amounts[0],
                    path,
                    feeReceiver,
                    block.timestamp
                );
            require(tokenBlance[account] >= amountsResult[0], "Insolvent!");
            tokenBlance[account] -= amountsResult[0];
        }
    }

    function paymentCheck(address account, uint256 consumedAmount)
        external
        onlySigner
    {
        _paymentCheck(account, consumedAmount);
    }

    function depositWithPermit(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            uint256 amount,
            uint256 consumedAmount,
            bool access,
            uint256 deadline,
            bytes memory signature
        ) = abi.decode(encodedData, (uint256, uint256, bool, uint256, bytes));
        require(access, "Not deposit method.");
        require(
            verify(
                balanceController,
                account,
                feeTokenAddr,
                consumedAmount,
                access,
                deadline,
                signature
            ),
            "Verify failed!"
        );

        pullTokensIfNeeded(feeTokenAddr, account, amount);
        tokenBlance[account] += amount;
        _paymentCheck(account, consumedAmount);
        emit FeeBoxTokenDeposit(account, amount, consumedAmount);
    }

    function withdrawWithPermit(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (
            uint256 amount,
            uint256 consumedAmount,
            bool access,
            uint256 deadline,
            bytes memory signature
        ) = abi.decode(encodedData, (uint256, uint256, bool, uint256, bytes));
        require(!access, "Not withdraw method.");
        require(
            verify(
                balanceController,
                account,
                feeTokenAddr,
                consumedAmount,
                access,
                deadline,
                signature
            ),
            "Verify failed!"
        );
        require(tokenBlance[account] >= amount, "token is not enough!");
        tokenBlance[account] -= amount;
        _paymentCheck(account, consumedAmount);
        IERC20(feeTokenAddr).safeTransfer(account, amount);
        emit FeeBoxTokenWithdraw(account, amount, consumedAmount);
    }

    function userInfo(address account)
        external
        view
        returns (uint256, uint256)
    {
        address[] memory path = new address[](2);
        (path[0], path[1]) = (feeTokenAddr, wavaxAddr);
        if (tokenBlance[account] == 0) {
            return (0, 0);
        }
        uint256[] memory amounts = IJoeRouter02(swapRouter).getAmountsOut(
            tokenBlance[account],
            path
        );
        return (tokenBlance[account], amounts[1]);
    }
}
