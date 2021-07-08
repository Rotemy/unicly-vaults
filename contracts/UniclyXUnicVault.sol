// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IUnicFarm.sol";
import "./interfaces/IUnicGallery.sol";
import "hardhat/console.sol";

contract UniclyXUnicVault is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant PERCENT = 100_000; // percentmil, 1/100,000

    address public constant XUNIC = address(0xA62fB0c2Fb3C7b27797dC04e1fEA06C0a2Db919a);
    address public constant UNIC = address(0x94E0BAb2F6Ab1F19F4750E42d7349f2740513aD5);
    address public constant UNIC_MASTERCHEF = address(0x4A25E4DF835B605A5848d2DB450fA600d96ee818);

    // TODO: ADD EVENTS
    // TODO: ADD COMMENTS
    // TODO: Adding emergency
    // TODO: Add readme

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 xUNICRate; // What was the rate when the user staked LP tokens
        uint256 rewardDebt; // How much to remove when calculating user shares

        // Every time users stake LP tokens or withdraw xUNICs,
        // we are sending xUNICs to them and resetting the xUNICRate
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 totalLPTokens; // The total LP tokens staked
        uint256 accUNICPerShare; //Accumulated UNICs per share, times 1e12
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    function initialize() external initializer {
        __Ownable_init();
    }

    // Current rate of xUNIC
    function getxUNICRate() public view returns (uint256) {
        uint256 xUNICBalance = IERC20(UNIC).balanceOf(XUNIC);
        uint256 xUNICSupply = IERC20(XUNIC).totalSupply();

        return (xUNICBalance * 1e18) / xUNICSupply;
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
            user.amount -= _amount;
            pool.totalLPTokens -= _amount;
            IUnicFarm(UNIC_MASTERCHEF).withdraw(_pid, _amount);
            (IERC20 lpToken,,,,) = IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid);
            lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.xUNICRate = getxUNICRate();
        user.rewardDebt = (user.amount * pool.accUNICPerShare) / 1e12;

        //        PoolInfo storage pool = poolInfo[_pid];
        //        UserInfo storage user = userInfo[_pid][msg.sender];
        //        require(user.amount >= _amount, "withdraw: not good");
        //        updatePool(_pid);
        //        uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.rewardDebt);
        //        safeSushiTransfer(msg.sender, pending);
        //        user.amount = user.amount.sub(_amount);
        //        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        //        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        //        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef for unics allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = pendingxUNICs(_pid, msg.sender);
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
            IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, _amount);
            user.amount += _amount;
            pool.totalLPTokens += _amount;
        }
        user.xUNICRate = getxUNICRate();
        user.rewardDebt = (user.amount * pool.accUNICPerShare) / 1e12;

        //        PoolInfo storage pool = poolInfo[_pid];
        //        UserInfo storage user = userInfo[_pid][msg.sender];
        //        updatePool(_pid);
        //        if (user.amount > 0) {
        //            uint256 pending = user.amount.mul(pool.accUnicPerShare).div(1e12).sub(user.rewardDebt);
        //            if(pending > 0) {
        //                safeUnicTransfer(msg.sender, pending);
        //            }
        //        }
        //        if(_amount > 0) {
        //            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        //            user.amount = user.amount.add(_amount);
        //        }
        //        user.rewardDebt = user.amount.mul(pool.accUnicPerShare).div(1e12);
        //        emit Deposit(msg.sender, _pid, _amount);
    }

    function doHardWork() public {
        for (uint256 i = 0; i < IUnicFarm(UNIC_MASTERCHEF).poolLength(); i++) {
            if (poolInfo[i].totalLPTokens > 0) {
                updatePool(i);
            }
        }
        uint256 balanceOfUNIC = IERC20(UNIC).balanceOf(address(this));
        if (balanceOfUNIC > 0) {
            IUnicGallery(XUNIC).enter(balanceOfUNIC);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 currentBalanceOfUNICs = IERC20(UNIC).balanceOf(address(this));
        IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, 0);
        uint256 addedUNICs = IERC20(UNIC).balanceOf(address(this)) - currentBalanceOfUNICs;
        IUnicGallery(XUNIC).enter(addedUNICs);

        pool.accUNICPerShare += ((addedUNICs * 1e12) / pool.totalLPTokens);

        //        PoolInfo storage pool = poolInfo[_pid];
        //        if (block.number <= pool.lastRewardBlock) {
        //            return;
        //        }
        //        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        //        if (lpSupply == 0) {
        //            pool.lastRewardBlock = block.number;
        //            return;
        //        }
        //        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        //        uint256 sushiReward = multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        //        sushi.mint(devaddr, sushiReward.div(10));
        //        sushi.mint(address(this), sushiReward);
        //        pool.accSushiPerShare = pool.accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
        //        pool.lastRewardBlock = block.number;
    }

    function pendingxUNICs(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 xUNICRate = getxUNICRate();
        // in case of a vulnerability in xUNIC would we want to disable withdrawals like this?
        require(xUNICRate >= user.xUNICRate, "xUNIC rate lower??");

        uint256 notClaimedUNICs = IUnicFarm(UNIC_MASTERCHEF).pendingUnic(_pid, address(this));
        uint256 accUNICPerShare = pool.accUNICPerShare + (notClaimedUNICs / pool.totalLPTokens);
        uint256 pendingUNICs = ((accUNICPerShare * user.amount) / 1e12) - user.rewardDebt;

        return ((xUNICRate * pendingUNICs) / user.xUNICRate) / xUNICRate;
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
