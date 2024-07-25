// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../base/AdapterBase.sol";
import "../../../interfaces/aave/v2/IAToken.sol";
import "../../../interfaces/aave/v3/ILendingPoolV3.sol";
import "../../../interfaces/aave/v3/IRewardsController.sol";
import "../../../interfaces/aave/v2/IWAVAXGateway.sol";
import "../../../interfaces/aave/v2/IVariableDebtToken.sol";

contract AaveV3Adapter is AdapterBase {
    using SafeERC20 for IERC20;

    mapping(address => address) public trustATokenAddr;

    event AaveDeposit(address token, uint256 amount, address account);
    event AaveWithDraw(address token, uint256 amount, address account);
    event AaveBorrow(
        address token,
        uint256 amount,
        address account,
        uint256 rateMode
    );
    event AaveRepay(
        address token,
        uint256 amount,
        address account,
        uint256 rateMode
    );
    event AaveClaim(address target, uint256 amount);

    constructor(address _adapterManager, address _timelock)
        AdapterBase(_adapterManager, _timelock, "AaveV3")
    {}

    function initialize(
        address[] calldata tokenAddr,
        address[] calldata aTokenAddr
    ) external onlyTimelock {
        require(
            tokenAddr.length > 0 && tokenAddr.length == aTokenAddr.length,
            "Set length mismatch."
        );
        for (uint256 i = 0; i < tokenAddr.length; i++) {
            if (tokenAddr[i] == avaxAddr) {
                require(
                    IAToken(aTokenAddr[i]).UNDERLYING_ASSET_ADDRESS() ==
                        wavaxAddr,
                    "Address mismatch."
                );
            } else {
                require(
                    IAToken(aTokenAddr[i]).UNDERLYING_ASSET_ADDRESS() ==
                        tokenAddr[i],
                    "Address mismatch."
                );
            }
            trustATokenAddr[tokenAddr[i]] = aTokenAddr[i];
        }
    }

    /**
     * @dev Aave Lending Pool Provider
     */
    address public constant wavaxGatewayAddr =
        0xa938d8536aEed1Bd48f548380394Ab30Aa11B00E;

    address public constant aaveV3PoolAddr =
        0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    address public constant debtAvaxAddr =
        0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8;

    address public constant incentivesController =
        0x929EC64c34a17401F460460D4B9390518E5B473e;

    /// @dev Aave Referral Code
    uint16 internal constant referralCode = 0;

    function deposit(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (address token, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        require(trustATokenAddr[token] != address(0), "token error");
        ILendingPoolV3 aave = ILendingPoolV3(aaveV3PoolAddr);

        if (token == avaxAddr) {
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            wavaxGateway.depositETH{value: msg.value}(
                aaveV3PoolAddr,
                account,
                referralCode
            );
            emit AaveDeposit(token, msg.value, account);
        } else {
            pullAndApprove(token, account, aaveV3PoolAddr, amount);
            aave.supply(token, amount, account, referralCode);
            emit AaveDeposit(token, amount, account);
        }
    }

    function setCollateral(address token, bool isCollateral)
        external
        onlyDelegation
    {
        ILendingPoolV3 aave = ILendingPoolV3(aaveV3PoolAddr);
        aave.setUserUseReserveAsCollateral(token, isCollateral);
    }

    function withdraw(address account, bytes calldata encodedData)
        external
        onlyAdapterManager
    {
        (address token, uint256 amount) = abi.decode(
            encodedData,
            (address, uint256)
        );

        address atoken = trustATokenAddr[token];
        require(atoken != address(0), "token error!");

        ILendingPoolV3 aave = ILendingPoolV3(aaveV3PoolAddr);

        if (token == avaxAddr) {
            pullAndApprove(atoken, account, wavaxGatewayAddr, amount);
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            wavaxGateway.withdrawETH(aaveV3PoolAddr, amount, account);
        } else {
            pullAndApprove(atoken, account, aaveV3PoolAddr, amount);
            aave.withdraw(token, amount, account);
        }
        emit AaveWithDraw(token, amount, account);
    }

    function borrow(
        address token,
        uint256 amount,
        uint256 rateMode
    ) external onlyDelegation {
        if (token == avaxAddr) {
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            wavaxGateway.borrowETH(
                aaveV3PoolAddr,
                amount,
                rateMode,
                referralCode
            );
        } else {
            ILendingPoolV3 aave = ILendingPoolV3(aaveV3PoolAddr);
            aave.borrow(token, amount, rateMode, referralCode, address(this));
        }
        emit AaveBorrow(token, amount, address(this), rateMode);
    }

    function approveDelegation(uint256 amount) external onlyDelegation {
        IVariableDebtToken(debtAvaxAddr).approveDelegation(
            wavaxGatewayAddr,
            amount
        );
    }

    function payback(
        address tokenAddr,
        uint256 amount,
        uint256 rateMode
    ) external onlyDelegation {
        if (tokenAddr == avaxAddr) {
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            if (amount == type(uint256).max) {
                uint256 repayValue = IERC20(debtAvaxAddr).balanceOf(
                    address(this)
                );
                wavaxGateway.repayETH{value: repayValue}(
                    aaveV3PoolAddr,
                    repayValue,
                    rateMode,
                    address(this)
                );
            } else {
                wavaxGateway.repayETH{value: amount}(
                    aaveV3PoolAddr,
                    amount,
                    rateMode,
                    address(this)
                );
            }
        } else {
            ILendingPoolV3(aaveV3PoolAddr).repay(
                tokenAddr,
                amount,
                rateMode,
                address(this)
            );
        }
        emit AaveRepay(tokenAddr, amount, address(this), rateMode);
    }

    function claimRewards(
        address[] calldata assetAddress,
        uint256 amount,
        address reward
    ) external onlyDelegation {
        IRewardsController(incentivesController).claimRewardsToSelf(
            assetAddress,
            amount,
            reward
        );
        emit AaveClaim(incentivesController, amount);
    }

    function setUserEMode(uint8 categoryId) external onlyDelegation {
        ILendingPoolV3(aaveV3PoolAddr).setUserEMode(categoryId);
    }
}
