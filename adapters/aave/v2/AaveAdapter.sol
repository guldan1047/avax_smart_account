// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../base/AdapterBase.sol";
import "../../../interfaces/aave/v2/IProtocolDataProvider.sol";
import "../../../interfaces/aave/v2/IIncentivesController.sol";
import "../../../interfaces/aave/v2/ILendingPool.sol";
import "../../../interfaces/aave/v2/IWAVAXGateway.sol";
import "../../../interfaces/aave/v2/IAToken.sol";
import "../../../interfaces/aave/v2/IVariableDebtToken.sol";
import "../../../interfaces/aave/v2/IOracle.sol";
import "../../../interfaces/aave/stakingPool/IFlashLoanRecipient.sol";
import "./IAaveStakingPool.sol";
import "../../../core/controller/IAccount.sol";
import "./IAaveAdapter.sol";

contract AaveAdapter is AdapterBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    mapping(address => address) public trustATokenAddr;

    address public constant debtAvaxAddr =
        0x66A0FE52Fb629a6cB4D10B8580AFDffE888F5Fd4;

    address public constant aaveProviderAddr =
        0xb6A86025F0FE1862B372cb0ca18CE3EDe02A318f;

    address public constant aaveDataAddr =
        0x65285E9dfab318f57051ab2b139ccCf232945451;

    address public constant wavaxGatewayAddr =
        0x8a47F74d1eE0e2edEB4F3A7e64EF3bD8e11D27C8;

    address public constant aaveOracleAddr =
        0xdC336Cd4769f4cC7E9d726DA53e6d3fC710cEB89;

    address public constant aaveLendingPoolAddr =
        0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;

    address public constant incentivesController =
        0x01D83Fe6A10D2f2B7AF17034343746188272cAc9;

    address public executor; //for flashloan
    address public flashLoanVault; //for flashloan

    /// @dev Aave Referral Code
    uint16 internal constant referralCode = 0;

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
        AdapterBase(_adapterManager, _timelock, "AaveV2")
    {}

    function initialize(
        address[] calldata tokenAddr,
        address[] calldata aTokenAddr
    ) external onlyTimelock {
        require(
            tokenAddr.length > 0 && tokenAddr.length == aTokenAddr.length,
            "Set length mismatch."
        );
        IProtocolDataProvider dataProvider = IProtocolDataProvider(
            aaveDataAddr
        );
        for (uint256 i = 0; i < tokenAddr.length; i++) {
            (address _aTokenAddr, , ) = dataProvider.getReserveTokensAddresses(
                tokenAddr[i]
            );
            if (tokenAddr[i] == avaxAddr) {
                (address _awavaxAddr, , ) = dataProvider
                    .getReserveTokensAddresses(wavaxAddr);
                require(aTokenAddr[i] == _awavaxAddr, "Address mismatch.");
            } else {
                require(_aTokenAddr == aTokenAddr[i], "Address mismatch.");
            }
            trustATokenAddr[tokenAddr[i]] = aTokenAddr[i];
        }
    }

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
        ILendingPool aave = ILendingPool(aaveLendingPoolAddr);

        if (token == avaxAddr) {
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            wavaxGateway.depositETH{value: msg.value}(
                aaveLendingPoolAddr,
                account,
                referralCode
            );
            emit AaveDeposit(token, msg.value, account);
        } else {
            require(msg.value == 0, "Unnecessary ether!");
            pullAndApprove(token, account, aaveLendingPoolAddr, amount);
            aave.deposit(token, amount, account, referralCode);
            emit AaveDeposit(token, amount, account);
        }
    }

    function setCollateral(address token, bool isCollateral)
        external
        onlyDelegation
    {
        ILendingPool aave = ILendingPool(aaveLendingPoolAddr);
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

        if (token == avaxAddr) {
            pullAndApprove(atoken, account, wavaxGatewayAddr, amount);
            IWAVAXGateway wavaxGateway = IWAVAXGateway(wavaxGatewayAddr);
            wavaxGateway.withdrawETH(aaveLendingPoolAddr, amount, account);
        } else {
            pullAndApprove(atoken, account, aaveLendingPoolAddr, amount);
            ILendingPool(aaveLendingPoolAddr).withdraw(token, amount, account);
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
                aaveLendingPoolAddr,
                amount,
                rateMode,
                referralCode
            );
        } else {
            ILendingPool(aaveLendingPoolAddr).borrow(
                token,
                amount,
                rateMode,
                referralCode,
                address(this)
            );
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
                    aaveLendingPoolAddr,
                    repayValue,
                    rateMode,
                    address(this)
                );
            } else {
                wavaxGateway.repayETH{value: amount}(
                    aaveLendingPoolAddr,
                    amount,
                    rateMode,
                    address(this)
                );
            }
        } else {
            ILendingPool(aaveLendingPoolAddr).repay(
                tokenAddr,
                amount,
                rateMode,
                address(this)
            );
        }
        emit AaveRepay(tokenAddr, amount, address(this), rateMode);
    }

    function claimRewards(address[] calldata assetAddress, uint256 amount)
        external
        onlyDelegation
    {
        IIncentivesController(incentivesController).claimRewards(
            assetAddress,
            amount,
            address(this)
        );
        emit AaveClaim(incentivesController, amount);
    }

    function positionTransfer(address account, bytes calldata encodedData)
        external
        payable
        onlyAdapterManager
    {
        (address loanVault, uint256 loanAmount) = abi.decode(
            encodedData,
            (address, uint256)
        );
        require(executor == address(0), "Reentrant call!");
        executor = msg.sender;
        flashLoanVault = loanVault;
        IAaveStakingPool pool = IAaveStakingPool(loanVault);
        address loanToken = pool.stakeToken();
        IERC20 token = IERC20(loanToken);
        bytes memory callbackData = abi.encode(
            loanVault,
            loanAmount,
            account,
            IAccount(account).owner()
        );

        uint256 tokenBefore = token.balanceOf(ADAPTER_ADDRESS);
        IAaveStakingPool(flashLoanVault).flashLoan(
            this,
            loanAmount,
            callbackData
        );
        uint256 tokenAfter = token.balanceOf(ADAPTER_ADDRESS);
        require(
            executor == address(0) && tokenBefore == tokenAfter,
            "Flash loan execution failed!"
        );
    }

    function receiveFlashLoan(
        IERC20 _token,
        uint256 _amount,
        uint256 _feeAmount,
        bytes memory _callbackData
    ) external override {
        require(
            executor != address(0) && msg.sender == flashLoanVault,
            "Reentrant call!"
        );
        (, , address account, ) = abi.decode(
            _callbackData,
            (address, uint256, address, address)
        );
        _token.safeTransfer(account, _amount);
        toCallback(account, AaveAdapter.exchangeDebt.selector, _callbackData);
        executor = address(0);
    }

    function exchangeDebt(
        address collateralPool,
        uint256 loanAmount,
        address account,
        address user
    ) external onlyDelegation {
        require(
            account == address(this) &&
                tx.origin == user &&
                IAaveAdapter(ADAPTER_ADDRESS).executor() != address(0),
            "Invalid call!"
        );
        IProtocolDataProvider aaveDataProvider = IProtocolDataProvider(
            aaveDataAddr
        );
        ILendingPool aave = ILendingPool(aaveLendingPoolAddr);
        address[] memory tokens = aave.getReservesList();
        for (uint256 i = 0; i < tokens.length; i++) {
            (, , address variableDebtTokenAddress) = aaveDataProvider
                .getReserveTokensAddresses(tokens[i]);
            uint256 debtAmount = IERC20(variableDebtTokenAddress).balanceOf(
                user
            );
            if (debtAmount != 0) {
                uint256 rateMode = 2;
                aave.borrow(
                    tokens[i],
                    debtAmount,
                    rateMode,
                    referralCode,
                    address(this)
                );
                IERC20(tokens[i]).safeApprove(aaveLendingPoolAddr, 0);
                IERC20(tokens[i]).safeApprove(aaveLendingPoolAddr, debtAmount);
                aave.repay(tokens[i], debtAmount, rateMode, user);
            }
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            (address aTokenAddress, , ) = aaveDataProvider
                .getReserveTokensAddresses(tokens[i]);
            uint256 aTokenAmount = IAToken(aTokenAddress).balanceOf(user);
            if (aTokenAmount != 0) {
                IAToken(aTokenAddress).transferFrom(
                    user,
                    address(this),
                    aTokenAmount
                );
            }
        }
        IERC20 token = IERC20(IAaveStakingPool(collateralPool).stakeToken());
        token.safeTransfer(collateralPool, loanAmount);
    }
}
