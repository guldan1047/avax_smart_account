// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../base/AdapterBase.sol";
import "../../../interfaces/aave/v2/IAToken.sol";
import "../../../interfaces/aave/stakingPool/IFlashLoanRecipient.sol";
import "hardhat/console.sol";

contract AaveStakingCollERC20 {
    using SafeMath for uint256;

    string public constant name = "AaveStakingColl Token";
    string public constant symbol = "aaveColl";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        _transfer(from, to, value);
        uint256 currentAllowance = allowance[from][msg.sender];
        require(
            currentAllowance >= value,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(from, msg.sender, currentAllowance - value);
        }
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "stakingColl: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "Joe: INVALID_SIGNATURE"
        );
        _approve(owner, spender, value);
    }
}

contract AaveStakingPool is AaveStakingCollERC20, AdapterBase, ReentrancyGuard {
    address internal immutable aaveAdapter;
    address public constant stakeToken =
        0x53f7c5869a859F0AeC3D334ee8B4Cf01E3492f21;
    uint256 public feeRate; //eg:feeRate = 1e14 ~ 1e14/1e18 = 1/10000

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 uToken = IERC20(stakeToken);

    constructor(
        address _adapterManager,
        address _adapter,
        address _timelock
    ) AdapterBase(_adapterManager, _timelock, "AaveV2") AaveStakingCollERC20() {
        aaveAdapter = _adapter;
    }

    mapping(address => uint256) private debtBalances;

    function initialize() external onlyTimelock {
        approveToken(stakeToken, aaveAdapter, type(uint256).max);
    }

    function setLoanFee(uint256 _feeRate) external onlyTimelock {
        require(_feeRate < 1e13, "Fee rate too high!");
        feeRate = _feeRate;
    }

    modifier onlyAdapter() {
        require(
            msg.sender == aaveAdapter,
            "Only the Adapter can call this function"
        );
        _;
    }

    function flashLoan(
        address receiver,
        uint256 amount,
        bytes calldata userData
    ) external nonReentrant {
        uint256 feeAmount = (amount * feeRate) / 1e18;
        uint256 amountBefore = uToken.balanceOf(address(this));
        IERC20(stakeToken).safeTransfer(receiver, amount);
        IFlashLoanRecipient(receiver).receiveFlashLoan(
            IERC20(stakeToken),
            amount,
            feeAmount,
            userData
        );
        console.log("amountBefore = ", amountBefore);
        console.log(
            "amountAfter = ",
            IERC20(stakeToken).balanceOf(address(this))
        );
        require(
            IERC20(stakeToken).balanceOf(address(this)) ==
                amountBefore + feeAmount,
            "Flash loan operation failed."
        );
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount error!");
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceIn = uToken.balanceOf(address(this)) - uBalanceBefore;

        uint256 mintAmount;
        if (IERC20(stakeToken).balanceOf(address(this)) == 0) {
            mintAmount = amount;
        } else {
            mintAmount = uBalanceIn.mul(totalSupply).div(
                IERC20(stakeToken).balanceOf(address(this))
            );
        }

        _mint(msg.sender, mintAmount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, "amount error!");
        uint256 burnAmount = amount.mul(totalSupply).div(
            IERC20(stakeToken).balanceOf(address(this))
        );
        require(balanceOf[msg.sender] >= burnAmount, "!redeem");
        _burn(msg.sender, burnAmount);
        uToken.safeTransfer(msg.sender, amount);
    }

    function getAmount() external view returns (uint256) {
        return IERC20(stakeToken).balanceOf(address(this));
    }
}
