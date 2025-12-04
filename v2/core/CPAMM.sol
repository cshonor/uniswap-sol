// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title CPAMM - Constant Product Automated Market Maker
 * @dev 实现恒定乘积自动做市商算法 x * y = k
 */
contract CPAMM {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    
    uint256 public reserve0;
    uint256 public reserve1;
    
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);
    
    constructor(address _token0, address _token1) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token address");
        require(_token0 != _token1, "Tokens must be different");
        
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }
    
    /**
     * @dev 更新储备量
     */
    function _update(uint256 _reserve0, uint256 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        emit Sync(_reserve0, _reserve1);
    }
    
    /**
     * @dev 铸造流动性代币
     */
    function _mint(address to, uint256 amount) private {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    /**
     * @dev 销毁流动性代币
     */
    function _burn(address from, uint256 amount) private {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }
    
    /**
     * @dev 添加流动性
     * @param amount0 代币0的数量
     * @param amount1 代币1的数量
     * @return liquidity 返回铸造的流动性代币数量
     */
    function addLiquidity(uint256 amount0, uint256 amount1) external returns (uint256 liquidity) {
        // 将代币转入合约
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        
        uint256 _reserve0 = reserve0;
        uint256 _reserve1 = reserve1;
        
        if (_reserve0 == 0 && _reserve1 == 0) {
            // 首次添加流动性
            liquidity = _sqrt(amount0 * amount1);
        } else {
            // 计算流动性代币数量，保持比例一致
            uint256 liquidity0 = (amount0 * totalSupply) / _reserve0;
            uint256 liquidity1 = (amount1 * totalSupply) / _reserve1;
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }
        
        require(liquidity > 0, "Insufficient liquidity");
        _mint(msg.sender, liquidity);
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        emit Mint(msg.sender, amount0, amount1);
    }
    
    /**
     * @dev 移除流动性
     * @param liquidity 要销毁的流动性代币数量
     * @return amount0 返回的代币0数量
     * @return amount1 返回的代币1数量
     */
    function removeLiquidity(uint256 liquidity) external returns (uint256 amount0, uint256 amount1) {
        uint256 _totalSupply = totalSupply;
        require(_totalSupply > 0, "No liquidity");
        
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");
        
        _burn(msg.sender, liquidity);
        
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
        
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        emit Burn(msg.sender, amount0, amount1, msg.sender);
    }
    
    /**
     * @dev 计算交换后的输出数量（恒定乘积公式）
     * @param amountIn 输入数量
     * @param reserveIn 输入代币的储备量
     * @param reserveOut 输出代币的储备量
     * @return amountOut 输出数量
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        // 恒定乘积公式: (x + Δx) * (y - Δy) = x * y
        // 计算: Δy = (y * Δx) / (x + Δx)
        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        amountOut = numerator / denominator;
    }
    
    /**
     * @dev 交换代币
     * @param tokenIn 输入代币地址
     * @param amountIn 输入数量
     * @param amountOutMin 最小输出数量（滑点保护）
     * @param to 接收地址
     * @return amountOut 实际输出数量
     */
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external returns (uint256 amountOut) {
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");
        require(to != address(0) && to != address(this), "Invalid recipient");
        
        bool isToken0 = tokenIn == address(token0);
        (IERC20 tokenIn_, IERC20 tokenOut_, uint256 reserveIn, uint256 reserveOut) = isToken0
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);
        
        // 将输入代币转入合约
        tokenIn_.transferFrom(msg.sender, address(this), amountIn);
        
        // 计算输出数量
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // 转出代币
        tokenOut_.transfer(to, amountOut);
        
        // 更新储备量
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        emit Swap(
            msg.sender,
            isToken0 ? amountIn : 0,
            isToken0 ? 0 : amountIn,
            isToken0 ? 0 : amountOut,
            isToken0 ? amountOut : 0,
            to
        );
    }
    
    /**
     * @dev 计算平方根（用于首次添加流动性）
     */
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    
    /**
     * @dev 获取储备量
     */
    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }
}

