// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../../../interfaces/aave/stakingPool/IFlashLoanRecipient.sol";

interface IAaveStakingPool {
    function flashLoan(
        IFlashLoanRecipient receiver,
        uint256 amount,
        bytes calldata userData
    ) external;

    function getAmount() external view returns (uint256);

    function getUserLoan(address user) external view returns (uint256);

    function repay(address user) external;

    function stakeToken() external view returns (address);
}
