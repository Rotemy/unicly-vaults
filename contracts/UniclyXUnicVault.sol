// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./Interfaces.sol";
import "hardhat/console.sol";

contract UniclyXUnicVault {
    using SafeERC20 for IERC20;

    uint256 public constant PERCENT = 100_000; // percentmil, 1/100,000

    address public constant XUNIC = address(0xA62fB0c2Fb3C7b27797dC04e1fEA06C0a2Db919a);
    address public constant UNIC = address(0x94E0BAb2F6Ab1F19F4750E42d7349f2740513aD5);
    address public constant UNIC_MASTERCHEF = address(0x4A25E4DF835B605A5848d2DB450fA600d96ee818);

    // TODO: ADD EVENTS
    // TODO: ADD COMMENTS
    // TODO: Adding emergency

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

    // Current rate of xUNIC
    function getxUNICRate() public view returns (uint256) {
        uint256 xUNICBalance = IERC20(UNIC).balanceOf(XUNIC);
        uint256 xUNICSupply = IERC20(XUNIC).totalSupply();

        return (xUNICBalance * PERCENT) / xUNICSupply;
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
            IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid).lpToken.safeTransfer(address(msg.sender), _amount);
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
            IUnicFarm(UNIC_MASTERCHEF).poolInfo(_pid).lpToken.safeTransferFrom(
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
            IxUNIC(XUNIC).enter(balanceOfUNIC);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 currentBalanceOfUNICs = IERC20(UNIC).balanceOf(address(this));
        IUnicFarm(UNIC_MASTERCHEF).deposit(_pid, 0);
        uint256 addedUNICs = IERC20(UNIC).balanceOf(address(this)) - currentBalanceOfUNICs;

        pool.accUNICPerShare += (addedUNICs / pool.totalLPTokens);

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
        require(xUNICRate >= user.xUNICRate, "xUNIC rate lower??");

        uint256 notClaimedUNICs = IUnicFarm(UNIC_MASTERCHEF).pendingUnic(_pid, address(this));
        uint256 accUNICPerShare = pool.accUNICPerShare + (notClaimedUNICs / pool.totalLPTokens);
        uint256 pendingUNICs = ((accUNICPerShare * user.amount) / 1e12) - user.rewardDebt;

        return ((xUNICRate * PERCENT) / user.xUNICRate) * pendingUNICs;
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

    //
    //    uint256 public constant PERCENT = 100_000; // percentmil, 1/100,000
    //    address public constant USDC = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
    //    address public constant VUSDC = address(0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8);
    //    address public constant UNITROLLER = address(0xfD36E2c2a6789Db23113685031d7F16329158384);
    //    address public constant XVS = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    //    address public immutable owner;
    //    address public admin;
    //
    //    event LogSupply(uint256 amount);
    //    event LogBorrow(uint256 amount);
    //    event LogRedeem(uint256 amount);
    //    event LogRedeemVTokens(uint256 amount);
    //    event LogRepay(uint256 amount);
    //    event LogSetAdmin(address newAdmin);
    //
    //    modifier restricted() {
    //        require(msg.sender == owner || msg.sender == admin, "restricted");
    //        _;
    //    }
    //
    //    constructor(address _owner) {
    //        owner = _owner;
    //        admin = _owner;
    //
    //        IERC20(USDC).safeApprove(VUSDC, type(uint256).max);
    //        _enterMarkets();
    //    }
    //
    //    // ------------------------ main ------------------------
    //
    //    /**
    //     * iterations: number of leverage loops
    //     * ratio: percent of liquidity to borrow each iteration. 100% == 100,000
    //     */
    //    function enterPosition(uint256 iterations, uint256 ratio) external restricted returns (uint256 endLiquidity) {
    //        _supply(getBalanceUSDC());
    //        for (uint256 i = 0; i < iterations; i++) {
    //            _borrowAndSupply(ratio);
    //        }
    //        return getAccountLiquidityAccrued();
    //    }
    //
    //    /**
    //     * Supports partial exits
    //     * maxIterations: max (upper bound) of exit deleverage loops
    //     * ratio: percent of liquidity to redeem each iteration. 100% == 100,000
    //     */
    //    function exitPosition(uint256 maxIterations, uint256 ratio) external restricted returns (uint256 endBalanceUSDC) {
    //        for (uint256 i = 0; getTotalBorrowedAccrued() > 0 && i < maxIterations; i++) {
    //            _redeemAndRepay(ratio);
    //        }
    //        if (getTotalBorrowedAccrued() == 0) {
    //            _redeemVTokens(IERC20(VUSDC).balanceOf(address(this)));
    //        }
    //        return getBalanceUSDC();
    //    }
    //
    //    function withdrawAllUSDCToOwner() external restricted {
    //        withdrawToOwner(USDC);
    //    }
    //
    //    function setAdmin(address newAdmin) external restricted {
    //        admin = newAdmin;
    //        emit LogSetAdmin(newAdmin);
    //    }
    //
    //    // ------------------------ unrestricted ------------------------
    //
    //    /**
    //     * Underlying balance
    //     */
    //    function getBalanceUSDC() public view returns (uint256) {
    //        return IERC20(USDC).balanceOf(address(this));
    //    }
    //
    //    /**
    //     * Total underlying (USDC) supplied balance
    //     */
    //    function getTotalSupplied() external view returns (uint256) {
    //        return (IVToken(VUSDC).exchangeRateStored() * IERC20(VUSDC).balanceOf(address(this))) / 1e18;
    //    }
    //
    //    /**
    //     * Total borrowed balance (USDC) debt
    //     */
    //    function getTotalBorrowed() external view returns (uint256) {
    //        return IVToken(VUSDC).borrowBalanceStored(address(this));
    //    }
    //
    //    /**
    //     * Total underlying (USDC) supplied balance - with state update
    //     */
    //    function getTotalSuppliedAccrued() public returns (uint256) {
    //        return IVToken(VUSDC).balanceOfUnderlying(address(this));
    //    }
    //
    //    /**
    //     * Total borrowed balance (USDC) debt - with state update
    //     */
    //    function getTotalBorrowedAccrued() public returns (uint256) {
    //        return IVToken(VUSDC).borrowBalanceCurrent(address(this));
    //    }
    //
    //    function getBalanceXVS() public view returns (uint256) {
    //        return IERC20(XVS).balanceOf(address(this));
    //    }
    //
    //    /**
    //     * Unclaimed reward balance
    //     */
    //    function getClaimableXVS() external view returns (uint256) {
    //        return IComptroller(UNITROLLER).venusAccrued(address(this));
    //    }
    //
    //    function claimRewardsToOwner() external returns (uint256 rewards) {
    //        IVToken(VUSDC).accrueInterest();
    //        IComptroller(UNITROLLER).claimVenus(address(this));
    //        rewards = getBalanceXVS();
    //        IERC20(XVS).safeTransfer(owner, rewards);
    //    }
    //
    //    /**
    //     * Account liquidity in USD, using Venus price oracle
    //     */
    //    function getAccountLiquidity() public view returns (uint256) {
    //        (uint256 err, uint256 liquidity, uint256 shortfall) = IComptroller(UNITROLLER).getAccountLiquidity(
    //            address(this)
    //        );
    //        require(err == 0 && shortfall == 0, "getAccountLiquidity failed");
    //
    //        uint256 price = PriceOracle(IComptroller(UNITROLLER).oracle()).getUnderlyingPrice(VUSDC);
    //        liquidity = (liquidity * 1e18) / price;
    //
    //        return liquidity;
    //    }
    //
    //    function getAccountLiquidityAccrued() public returns (uint256) {
    //        IVToken(VUSDC).accrueInterest();
    //        return getAccountLiquidity();
    //    }
    //
    //    // ------------------------ internals, exposed in case of emergency ------------------------
    //
    //    /**
    //     * amount: USDC
    //     * generates interest
    //     */
    //    function _supply(uint256 amount) public restricted {
    //        require(IVToken(VUSDC).mint(amount) == 0, "mint failed");
    //        emit LogSupply(amount);
    //    }
    //
    //    /**
    //     * withdraw from supply
    //     * amount: USDC
    //     */
    //    function _redeem(uint256 amount) public restricted {
    //        require(IVToken(VUSDC).redeemUnderlying(amount) == 0, "redeem failed");
    //        emit LogRedeem(amount);
    //    }
    //
    //    /**
    //     * withdraw from supply
    //     * amount: VUSDC
    //     */
    //    function _redeemVTokens(uint256 amountVUSDC) public restricted {
    //        require(IVToken(VUSDC).redeem(amountVUSDC) == 0, "redeemVTokens failed");
    //        emit LogRedeemVTokens(amountVUSDC);
    //    }
    //
    //    /**
    //     * amount: USDC
    //     */
    //    function _borrow(uint256 amount) public restricted {
    //        require(IVToken(VUSDC).borrow(amount) == 0, "borrow failed");
    //        emit LogBorrow(amount);
    //    }
    //
    //    /**
    //     * pay back debt
    //     * amount: USDC
    //     */
    //    function _repay(uint256 amount) public restricted {
    //        require(IVToken(VUSDC).repayBorrow(amount) == 0, "repay failed");
    //        emit LogRepay(amount);
    //    }
    //
    //    /**
    //     * ratio: 100% == 100,000
    //     */
    //    function _borrowAndSupply(uint256 ratio) public restricted {
    //        uint256 liquidity = getAccountLiquidityAccrued();
    //
    //        uint256 borrowAmount = (liquidity * ratio) / PERCENT;
    //        _borrow(borrowAmount);
    //
    //        _supply(getBalanceUSDC());
    //    }
    //
    //    /**
    //     * ratio: 100% == 100,000
    //     */
    //    function _redeemAndRepay(uint256 ratio) public restricted {
    //        uint256 liquidity = getAccountLiquidityAccrued();
    //
    //        (, uint256 collateralFactor) = IComptroller(UNITROLLER).markets(VUSDC);
    //        uint256 canWithdraw = ((liquidity * 1e18) / collateralFactor);
    //
    //        uint256 redeemAmount = (canWithdraw * ratio) / PERCENT;
    //        _redeem(redeemAmount);
    //
    //        uint256 usdc = getBalanceUSDC();
    //        uint256 borrowed = getTotalBorrowedAccrued();
    //        if (usdc < borrowed) {
    //            _repay(usdc);
    //        } else {
    //            _repay(type(uint256).max);
    //        }
    //    }
    //
    //    function _enterMarkets() private {
    //        address[] memory markets = new address[](1);
    //        markets[0] = VUSDC;
    //        IComptroller(UNITROLLER).enterMarkets(markets);
    //    }
    //
    //    // ------------------------ emergency ------------------------
    //
    //    function withdrawToOwner(address asset) public restricted {
    //        uint256 balance = IERC20(asset).balanceOf(address(this));
    //        IERC20(asset).safeTransfer(owner, balance);
    //    }
    //
    //    function emergencyFunctionCall(address target, bytes memory data) external restricted {
    //        Address.functionCall(target, data);
    //    }
    //
    //    function emergencyFunctionDelegateCall(address target, bytes memory data) external restricted {
    //        Address.functionDelegateCall(target, data);
    //    }
}
