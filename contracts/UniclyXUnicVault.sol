// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUnicFarm.sol";
import "./interfaces/IUnicGallery.sol";
import "hardhat/console.sol"; // TODO: Remove

contract UniclyXUnicVault is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public constant XUNIC = address(0xA62fB0c2Fb3C7b27797dC04e1fEA06C0a2Db919a);
    address public constant UNIC = address(0x94E0BAb2F6Ab1F19F4750E42d7349f2740513aD5);
    address public constant UNIC_MASTERCHEF = address(0x4A25E4DF835B605A5848d2DB450fA600d96ee818);

    // TODO: ADD EVENTS - Deposit, withdraw, doHardWork

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // How much to remove when calculating user shares
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 totalLPTokens; // The total LP tokens staked
        uint256 accXUNICPerShare; //Accumulated UNICs per share, times 1e12
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Info of each pool.
    mapping(uint256 => PoolInfo) public poolInfo;

    // Gas optimization for approving tokens to unic chef
    mapping(address => bool) public haveApprovedToken;

    // dev fee
    address public devAddress;
    uint public devFee; // TODO: hardcoded 10 percetnage
    uint public maxDevFee = 150;
    uint public devFeeDenominator = 1000;

    // TODO: Add update _devAddress

    function initialize(address _devAddress, uint _devFee) external initializer {
        __Ownable_init();
        devAddress = _devAddress;
        devFee = _devFee;
        console.log("_devFee", _devFee);
        require(devFee <= maxDevFee, "dev fee");
        IERC20(UNIC).approve(XUNIC, uint(~0));
    }

    // Current rate of xUNIC
    function getxUNICRate() public view returns (uint256) {
        uint256 xUNICBalance = IERC20(UNIC).balanceOf(XUNIC);
        uint256 xUNICSupply = IERC20(XUNIC).totalSupply();

        return xUNICBalance.mul(1e18).div(xUNICSupply);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = pendingxUNICs(_pid, msg.sender);
        if (pending > 0) {
            safexUNICTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalLPTokens = pool.totalLPTokens.sub(_amount);
            IUnicFarm(UNIC_MASTERCHEF).withdraw(_pid, _amount);
            (IERC20 lpToken,,,,) = IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid);
            lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXUNICPerShare).div(1e12);
    }

    // Deposit LP tokens to MasterChef for unics allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = pendingxUNICs(_pid, msg.sender);
            console.log("rotem", pending);
            if (pending > 0) {
                safexUNICTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            (IERC20 lpToken,,,,) = IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid);
            lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            if (!haveApprovedToken[address(lpToken)]) {
                lpToken.approve(UNIC_MASTERCHEF, uint(~0));
                haveApprovedToken[address(lpToken)] = true;
            }
            IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, _amount);
            user.amount = user.amount.add(_amount);
            pool.totalLPTokens = pool.totalLPTokens.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXUNICPerShare).div(1e12);
    }

    function doHardWork() public {
        for (uint256 i = 0; i < IUnicFarm(UNIC_MASTERCHEF).poolLength(); i++) {
            if (poolInfo[i].totalLPTokens > 0) {
                // TODO: If 12h passed only
                updatePool(i);
            }
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint prevXUNICBalance = IERC20(XUNIC).balanceOf(address(this));
        IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, 0);
        uint256 UNICBalance = IERC20(UNIC).balanceOf(address(this));
        if (UNICBalance > 0) {
            IUnicGallery(XUNIC).enter(UNICBalance);
            uint addedXUNICs = IERC20(XUNIC).balanceOf(address(this)).sub(prevXUNICBalance);
            uint devAmount = addedXUNICs.mul(devFee).div(devFeeDenominator);
            IERC20(XUNIC).transfer(devAddress, devAmount);
            addedXUNICs = addedXUNICs.sub(devAmount);
            pool.accXUNICPerShare = pool.accXUNICPerShare.add(addedXUNICs.mul(1e12).div(pool.totalLPTokens));
        }
    }

    // withdraws without xUNIC reward, emergency only
    function emergencyWithdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalLPTokens = pool.totalLPTokens.sub(_amount);
            IUnicFarm(UNIC_MASTERCHEF).withdraw(_pid, _amount);
            (IERC20 lpToken,,,,) = IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid);
            lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXUNICPerShare).div(1e12);
    }

    // salvage purpose only for when stupid people send tokens here
    function withdrawToken(address tokenToWithdraw, uint amount) external onlyOwner {
        require(tokenToWithdraw != XUNIC, "Can't salvage xunic");
        IERC20(tokenToWithdraw).transfer(msg.sender, amount);
    }

    function pendingxUNICs(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        // for frontend
        uint256 notClaimedUNICs = IUnicFarm(UNIC_MASTERCHEF).pendingUnic(_pid, address(this));
        if (notClaimedUNICs > 0) {
            uint256 xUNICRate = getxUNICRate();
            uint256 accXUNICPerShare = pool.accXUNICPerShare.add(notClaimedUNICs.mul(1e18).div(xUNICRate).mul(1e12).div(pool.totalLPTokens));
            uint256 pendingXUNICs = ((accXUNICPerShare.mul(user.amount)).div(1e12)).sub(user.rewardDebt);
            console.log("pendingXUNICs 1", pendingXUNICs);
            return pendingXUNICs;
        }
        uint256 pendingXUNICs = (pool.accXUNICPerShare.mul(user.amount).div(1e12)).sub(user.rewardDebt);
        console.log("pendingXUNICs 2", pendingXUNICs);
        return pendingXUNICs;
    }

    // Safe unic transfer function, just in case if rounding error causes pool to not have enough xUNICs.
    function safexUNICTransfer(address _to, uint256 _amount) internal {
        uint256 xUNICBal = IERC20(XUNIC).balanceOf(address(this));
        if (_amount > xUNICBal) {
            IERC20(XUNIC).transfer(_to, xUNICBal);
        } else {
            IERC20(XUNIC).transfer(_to, _amount);
        }
    }
}
