// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../core/interfaces/IUniswapV3Pool.sol";
import "../core/interfaces/IERC20Minimal.sol";
import "../core/UniswapV3Factory.sol";
import "../core/libraries/TickMath.sol";
import "./libraries/PoolAddress.sol";

/// @title SwapRouter
/// @dev 交换路由合约，用于执行代币交换
contract SwapRouter {
    UniswapV3Factory public immutable factory;

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1);

    constructor(address _factory) {
        factory = UniswapV3Factory(_factory);
    }

    /// @notice 单跳交换
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        require(params.deadline >= block.timestamp, "SwapRouter: EXPIRED");

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                params.tokenIn < params.tokenOut ? params.tokenIn : params.tokenOut,
                params.tokenIn < params.tokenOut ? params.tokenOut : params.tokenIn,
                params.fee
            )
        );

        require(address(pool) != address(0), "SwapRouter: POOL_NOT_FOUND");

        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 批准池子使用输入代币
        IERC20Minimal(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20Minimal(params.tokenIn).approve(address(pool), params.amountIn);

        // 执行交换（池子会从路由合约转移输入代币，并转移输出代币到接收者）
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            params.recipient,
            zeroForOne,
            int256(params.amountIn),
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            ""
        );

        amountOut = uint256(-(zeroForOne ? amount1Delta : amount0Delta));
        require(amountOut >= params.amountOutMinimum, "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");

        emit Swap(msg.sender, params.recipient, amount0Delta, amount1Delta);
    }

    /// @notice 多跳交换（简化实现）
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut) {
        require(params.deadline >= block.timestamp, "SwapRouter: EXPIRED");
        // 简化实现：只支持单跳
        // 完整实现需要解析 path 并执行多跳交换
        revert("SwapRouter: NOT_IMPLEMENTED");
    }
}

