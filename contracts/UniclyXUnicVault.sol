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

    mapping(address => bool) public haveApprovedToken;

    function initialize() external initializer {
        __Ownable_init();
        IERC20(UNIC).approve(XUNIC, uint(~0));
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
        user.rewardDebt = (user.amount * pool.accXUNICPerShare) / 1e12;
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
            if (!haveApprovedToken[address(lpToken)]) {
                lpToken.approve(UNIC_MASTERCHEF, uint(~0));
                haveApprovedToken[address(lpToken)] = true;
            }
            IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, _amount);
            user.amount += _amount;
            pool.totalLPTokens += _amount;
        }
        user.rewardDebt = (user.amount * pool.accXUNICPerShare) / 1e12;
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

        uint prevXUNICBalance = IERC20(XUNIC).balanceOf(address(this));
        IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, 0);
        uint256 UNICBalance = IERC20(UNIC).balanceOf(address(this));
        if (UNICBalance > 0) {
            IUnicGallery(XUNIC).enter(UNICBalance);
            uint addedXUNICs = IERC20(XUNIC).balanceOf(address(this)) - prevXUNICBalance;
            pool.accXUNICPerShare += ((addedXUNICs * 1e12) / pool.totalLPTokens);
        }
    }

    function pendingxUNICs(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        // for frontend
        uint256 notClaimedUNICs = IUnicFarm(UNIC_MASTERCHEF).pendingUnic(_pid, address(this));
        if (notClaimedUNICs > 0) {
            uint256 xUNICRate = getxUNICRate();
            uint256 accXUNICPerShare = pool.accXUNICPerShare + ((notClaimedUNICs * 1e18 / xUNICRate) * 1e12 / pool.totalLPTokens);
            uint256 pendingXUNICs = ((accXUNICPerShare * user.amount) / 1e12) - user.rewardDebt;
            return pendingXUNICs;
        }
        uint256 pendingXUNICs = ((pool.accXUNICPerShare * user.amount) / 1e12) - user.rewardDebt;
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
