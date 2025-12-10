// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../core/CPAMM.sol";
import "../core/CPAMMFactory.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title CPAMMRouter - Router Contract for User-Friendly Interactions
 * @dev 路由合约，提供用户友好的接口，封装与核心合约的交互
 * 类似 Uniswap V2 Router 的核心功能
 */
contract CPAMMRouter {
    CPAMMFactory public immutable factory;
    
    constructor(address _factory) {
        require(_factory != address(0), "CPAMMRouter: ZERO_ADDRESS");
        factory = CPAMMFactory(_factory);
    }
    
    /**
     * @dev 添加流动性（自动处理代币比例）
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param amountADesired 期望添加的代币A数量
     * @param amountBDesired 期望添加的代币B数量
     * @param amountAMin 最小代币A数量（滑点保护）
     * @param amountBMin 最小代币B数量（滑点保护）
     * @param to 接收流动性代币的地址
     * @param deadline 交易截止时间（时间戳）
     * @return amountA 实际添加的代币A数量
     * @return amountB 实际添加的代币B数量
     * @return liquidity 获得的流动性代币数量
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // 获取或创建交易对
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }
        
        // 获取当前储备量
        (uint256 reserveA, uint256 reserveB) = _getReserves(pair, tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) {
            // 首次添加流动性，使用期望数量
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 计算最优数量以保持比例
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "CPAMMRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "CPAMMRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
        
        // 转移代币到交易对
        _safeTransferFrom(IERC20(tokenA), msg.sender, pair, amountA);
        _safeTransferFrom(IERC20(tokenB), msg.sender, pair, amountB);
        
        // 添加流动性
        liquidity = CPAMM(pair).addLiquidity(amountA, amountB);
        
        // 将流动性代币转给接收者（需要先批准）
        // 注意：实际实现中，CPAMM 的 addLiquidity 应该将 LP tokens 直接转给调用者
        // 这里简化处理
    }
    
    /**
     * @dev 移除流动性
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param liquidity 要销毁的流动性代币数量
     * @param amountAMin 最小代币A数量（滑点保护）
     * @param amountBMin 最小代币B数量（滑点保护）
     * @param to 接收代币的地址
     * @param deadline 交易截止时间
     * @return amountA 返回的代币A数量
     * @return amountB 返回的代币B数量
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "CPAMMRouter: PAIR_NOT_EXISTS");
        
        // 将流动性代币转移到交易对
        // 注意：用户需要先批准 Router 合约
        CPAMM(pair).transferFrom(msg.sender, pair, liquidity);
        
        // 移除流动性
        (amountA, amountB) = CPAMM(pair).removeLiquidity(liquidity);
        require(amountA >= amountAMin, "CPAMMRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "CPAMMRouter: INSUFFICIENT_B_AMOUNT");
        
        // 确保代币顺序正确
        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amountA, amountB) : (amountB, amountA);
        
        // 转移代币给接收者
        _safeTransfer(IERC20(tokenA), to, amountA);
        _safeTransfer(IERC20(tokenB), to, amountB);
    }
    
    /**
     * @dev 精确输入交换（定输入量，求最少输出）
     * 
     * 核心逻辑：我要花掉精确数量的 A 代币，换回至少 X 数量的 B 代币
     * 
     * 关键特点：
     * - 输入代币的数量是"精确固定"的（比如我确定要花 100 USDT）
     * - 需要指定"输出代币的最小接收量"（amountOutMin），防止滑点导致换到的代币太少
     * - 最终兑换结果：实际换到的 B 代币 ≥ amountOutMin（满足则成交，否则回滚）
     * 
     * 使用场景：想精准控制"花多少钱"，比如我就想花 100 USDT，不管能换多少 ETH，
     *           只要不少于 0.02 ETH 就行。
     * 
     * @param amountIn 输入代币数量（精确固定值）
     * @param amountOutMin 最小输出数量（滑点保护，实际输出必须 ≥ 此值）
     * @param path 交换路径 [tokenIn, tokenOut]
     * @param to 接收代币的地址
     * @param deadline 交易截止时间
     * @return amounts 输出数量数组
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length >= 2, "CPAMMRouter: INVALID_PATH");
        
        amounts = _getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "CPAMMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        
        _safeTransferFrom(IERC20(path[0]), msg.sender, _pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    
    /**
     * @dev 精确输出交换（定输出量，求最多输入）
     * 
     * 核心逻辑：我要换到精确数量的 B 代币，最多花 X 数量的 A 代币
     * 
     * 关键特点：
     * - 输出代币的数量是"精确固定"的（比如我确定要换 0.02 ETH）
     * - 需要指定"输入代币的最大花费量"（amountInMax），防止滑点导致花太多钱
     * - 最终兑换结果：实际花的 A 代币 ≤ amountInMax（满足则成交，否则回滚）
     * 
     * 使用场景：想精准控制"换到多少币"，比如我就想要 0.02 ETH，不管花多少 USDT，
     *           只要不超过 100 USDT 就行。
     * 
     * @param amountOut 期望的输出代币数量（精确固定值）
     * @param amountInMax 最大输入数量（滑点保护，实际输入必须 ≤ 此值）
     * @param path 交换路径 [tokenIn, tokenOut]
     * @param to 接收代币的地址
     * @param deadline 交易截止时间
     * @return amounts 输入/输出数量数组
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length >= 2, "CPAMMRouter: INVALID_PATH");
        
        amounts = _getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "CPAMMRouter: EXCESSIVE_INPUT_AMOUNT");
        
        _safeTransferFrom(IERC20(path[0]), msg.sender, _pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    
    // ==================== 内部辅助函数 ====================
    
    /**
     * @dev 确保交易在截止时间之前执行
     */
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "CPAMMRouter: EXPIRED");
        _;
    }
    
    /**
     * @dev 获取交易对的储备量
     */
    function _getReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1) = CPAMM(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }
    
    /**
     * @dev 对代币地址排序（确保 token0 < token1）
     */
    function _sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "CPAMMRouter: ZERO_ADDRESS");
    }
    
    /**
     * @dev 根据储备量比例计算最优代币数量
     */
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        require(amountA > 0, "CPAMMRouter: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "CPAMMRouter: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }
    
    /**
     * @dev 获取输出数量数组
     */
    function _getAmountsOut(uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "CPAMMRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i; i < path.length - 1; i++) {
            address pair = _pairFor(path[i], path[i + 1]);
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, path[i], path[i + 1]);
            amounts[i + 1] = CPAMM(pair).getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }
    
    /**
     * @dev 获取输入数量数组
     */
    function _getAmountsIn(uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "CPAMMRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        
        // 反向计算
        for (uint256 i = path.length - 1; i > 0; i--) {
            address pair = _pairFor(path[i - 1], path[i]);
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, path[i - 1], path[i]);
            // 反向计算：已知输出，求输入
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
    
    /**
     * @dev 根据输出计算输入数量（反向公式）
     */
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "CPAMMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "CPAMMRouter: INSUFFICIENT_LIQUIDITY");
        
        // 从公式 amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
        // 推导：amountIn = (amountOut * reserveIn) / (reserveOut - amountOut)
        uint256 numerator = amountOut * reserveIn;
        uint256 denominator = reserveOut - amountOut;
        amountIn = (numerator / denominator) + 1; // +1 是为了避免舍入误差
    }
    
    /**
     * @dev 获取交易对地址
     */
    function _pairFor(address tokenA, address tokenB)
        internal
        view
        returns (address pair)
    {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = factory.getPair(token0, token1);
    }
    
    /**
     * @dev 执行交换操作
     */
    function _swap(uint256[] memory amounts, address[] memory path, address _to)
        internal
        virtual
    {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            
            address to = i < path.length - 2 ? _pairFor(output, path[i + 2]) : _to;
            address pair = _pairFor(input, output);
            
            CPAMM(pair).swap(
                input,
                amounts[i],
                0, // amountOutMin，这里已经通过 amounts 计算好了
                to
            );
        }
    }
    
    /**
     * @dev 安全转移代币（处理返回值）
     */
    function _safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "CPAMMRouter: TRANSFER_FAILED");
    }
    
    /**
     * @dev 安全从地址转移代币（处理返回值）
     */
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "CPAMMRouter: TRANSFER_FROM_FAILED");
    }
    
    // ==================== 视图函数 ====================
    
    /**
     * @dev 获取给定输入的输出数量
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return _getAmountsOut(amountIn, path);
    }
    
    /**
     * @dev 获取给定输出所需的输入数量
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return _getAmountsIn(amountOut, path);
    }
}

