// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IZap.sol";
import "./interfaces/IUniclyXUnicVault.sol";
import "./interfaces/IUnicSwapV2Pair.sol";
import "./interfaces/IUnicSwapV2Router02.sol";
import "./interfaces/IWETH.sol";


contract Zap is IZap, OwnableUpgradeable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant UNIC = 0x94E0BAb2F6Ab1F19F4750E42d7349f2740513aD5;
    address private constant XUNIC = 0x4A25E4DF835B605A5848d2DB450fA600d96ee818;

    IUnicSwapV2Router02 private constant ROUTER = IUnicSwapV2Router02(0xE6E90bC9F3b95cdB69F48c7bFdd0edE1386b135a);
    // TODO: address! for now must be configurable
    // IUniclyXUnicVault private constant XUNICVAULT = IUniclyXUnicVault();

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private notLP;
    mapping(address => address) private routePairAddresses;
    mapping(address => bool) private haveApprovedToken;
    address[] public tokens;
    // TODO: remove? hardcode once unicly vault is deployed
    IUniclyXUnicVault private xUnicVault;

    /* ========== INITIALIZER ========== */

    function initialize(address _xUnicVault) external initializer {
        __Ownable_init();
        require(owner() != address(0), "Zap: owner must be set");

        setNotLP(WETH);
        setNotLP(USDT);
        setNotLP(USDC);
        setNotLP(DAI);
        setNotLP(UNIC);
        setNotLP(XUNIC);

        xUnicVault = IUniclyXUnicVault(_xUnicVault);
    }

    receive() external payable {}

    /* ========== View Functions ========== */

    function isLP(address _address) public view returns (bool) {
        return !notLP[_address];
    }

    function routePair(address _address) external view returns(address) {
        return routePairAddresses[_address];
    }

    /* ========== External Functions ========== */

    function zapInTokenAndDeposit(address _from, uint amount, address _to, uint _pid) external {
        zapInTokenFor(_from, amount, _to, address(this));
        _approveTokenIfNeeded(_to);
        uint depositAmount = IERC20(_to).balanceOf(address(this));
        xUnicVault.depositFor(_pid, depositAmount, msg.sender);
    }

    function zapInAndDeposit(address _to, uint _pid) external payable {
        _swapETHToLP(_to, msg.value, address(this));
        _approveTokenIfNeeded(_to);
        uint depositAmount = IERC20(_to).balanceOf(address(this));
        xUnicVault.depositFor(_pid, depositAmount, msg.sender);
    }

    function zapInToken(address _from, uint amount, address _to) external override {
        zapInTokenFor(_from, amount, _to, msg.sender);
    }

    function zapInTokenFor(address _from, uint amount, address _to, address _recipient) internal {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (isLP(_to)) {
            IUnicSwapV2Pair pair = IUnicSwapV2Pair(_to);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (_from == token0 || _from == token1) {
                // swap half amount for other
                address other = _from == token0 ? token1 : token0;
                _approveTokenIfNeeded(other);
                uint sellAmount = amount.div(2);
                uint otherAmount = _swap(_from, sellAmount, other, address(this));
                ROUTER.addLiquidity(_from, other, amount.sub(sellAmount), otherAmount, 0, 0, _recipient, block.timestamp);
            } else {
                uint ethAmount = _swapTokenForETH(_from, amount, address(this));
                _swapETHToLP(_to, ethAmount, _recipient);
            }
        } else {
            _swap(_from, amount, _to, _recipient);
        }
    }

    function zapIn(address _to) external payable override {
        _swapETHToLP(_to, msg.value, msg.sender);
    }

    function zapOut(address _from, uint amount) external override {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (!isLP(_from)) {
            _swapTokenForETH(_from, amount, msg.sender);
        } else {
            IUnicSwapV2Pair pair = IUnicSwapV2Pair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WETH || token1 == WETH) {
                ROUTER.removeLiquidityETH(token0 != WETH ? token0 : token1, amount, 0, 0, msg.sender, block.timestamp);
            } else {
                ROUTER.removeLiquidity(token0, token1, amount, 0, 0, msg.sender, block.timestamp);
            }
        }
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token) private {
        if (!haveApprovedToken[token]) {
            IERC20(token).safeApprove(address(ROUTER), uint(- 1));
            IERC20(token).safeApprove(address(xUnicVault), uint(- 1));
            haveApprovedToken[token] = true;
        }
    }

    function _swapETHToLP(address lp, uint amount, address receiver) private {
        if (!isLP(lp)) {
            _swapETHForToken(lp, amount, receiver);
        } else {
            // lp
            IUnicSwapV2Pair pair = IUnicSwapV2Pair(lp);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WETH || token1 == WETH) {
                address token = token0 == WETH ? token1 : token0;
                uint swapValue = amount.div(2);
                uint tokenAmount = _swapETHForToken(token, swapValue, address(this));

                _approveTokenIfNeeded(token);
                ROUTER.addLiquidityETH{value : amount.sub(swapValue)}(token, tokenAmount, 0, 0, receiver, block.timestamp);
            } else {
                uint swapValue = amount.div(2);
                uint token0Amount = _swapETHForToken(token0, swapValue, address(this));
                uint token1Amount = _swapETHForToken(token1, amount.sub(swapValue), address(this));

                _approveTokenIfNeeded(token0);
                _approveTokenIfNeeded(token1);
                ROUTER.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
            }
        }
    }

    function _swapETHForToken(address token, uint value, address receiver) private returns (uint) {
        address[] memory path;

        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = WETH;
            path[1] = routePairAddresses[token];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = WETH;
            path[1] = token;
        }

        uint[] memory amounts = ROUTER.swapExactETHForTokens{value : value}(0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForETH(address token, uint amount, address receiver) private returns (uint) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = WETH;
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = WETH;
        }

        uint[] memory amounts = ROUTER.swapExactTokensForETH(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint amount, address _to, address receiver) private returns (uint) {
        address intermediate = routePairAddresses[_from];
        if (intermediate == address(0)) {
            intermediate = routePairAddresses[_to];
        }

        address[] memory path;
        if (intermediate != address(0) && (_from == WETH || _to == WETH)) {
            // [WETH, BUSD, VAI] or [VAI, BUSD, WETH]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (intermediate != address(0) && (_from == intermediate || _to == intermediate)) {
            // [VAI, BUSD] or [BUSD, VAI]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] == routePairAddresses[_to]) {
            // [VAI, DAI] or [VAI, USDC]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (routePairAddresses[_from] != address(0) && routePairAddresses[_from] != address(0) && routePairAddresses[_from] != routePairAddresses[_to]) {
            // routePairAddresses[xToken] = xRoute
            // [VAI, BUSD, WETH, xRoute, xToken]
            path = new address[](5);
            path[0] = _from;
            path[1] = routePairAddresses[_from];
            path[2] = WETH;
            path[3] = routePairAddresses[_to];
            path[4] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] != address(0)) {
            // [VAI, BUSD, WETH, BUNNY]
            path = new address[](4);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = WETH;
            path[3] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_to] != address(0)) {
            // [BUNNY, WETH, BUSD, VAI]
            path = new address[](4);
            path[0] = _from;
            path[1] = WETH;
            path[2] = intermediate;
            path[3] = _to;
        } else if (_from == WETH || _to == WETH) {
            // [WETH, BUNNY] or [BUNNY, WETH]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // [USDT, BUNNY] or [BUNNY, USDT]
            path = new address[](3);
            path[0] = _from;
            path[1] = WETH;
            path[2] = _to;
        }

        uint[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRoutePairAddress(address asset, address route) external onlyOwner {
        routePairAddresses[asset] = route;
    }

    function setNotLP(address token) public onlyOwner {
        bool needPush = notLP[token] == false;
        notLP[token] = true;
        if (needPush) {
            tokens.push(token);
        }
    }

    function removeToken(uint i) external onlyOwner {
        address token = tokens[i];
        notLP[token] = false;
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();
    }

    function sweep() external onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                if (token == WETH) {
                    IWETH(token).withdraw(amount);
                } else {
                    _swapTokenForETH(token, amount, owner());
                }
            }
        }

        uint balance = address(this).balance;
        if (balance > 0) {
            payable(owner()).transfer(balance);
        }
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
