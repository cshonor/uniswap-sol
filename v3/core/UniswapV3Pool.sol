// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IERC20Minimal.sol";
import "./libraries/TickMath.sol";
import "./libraries/SqrtPriceMath.sol";
import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/FullMath.sol";
import "./libraries/FixedPoint96.sol";

/// @title UniswapV3Pool
/// @dev Uniswap V3 池子核心合约
contract UniswapV3Pool is IUniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    /// @dev 池子的两个代币
    address public override token0;
    address public override token1;
    
    /// @dev 手续费层级
    uint24 public override fee;
    
    /// @dev Tick 间隔
    int24 public override tickSpacing;

    /// @dev 池子的核心状态
    struct Slot0 {
        uint160 sqrtPriceX96;  // 当前价格的平方根，Q96 格式
        int24 tick;            // 当前 tick
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;     // 协议手续费
        bool unlocked;         // 重入锁
    }

    Slot0 public override slot0;

    /// @dev 当前活跃的流动性
    uint128 public override liquidity;

    /// @dev Tick 信息映射
    mapping(int24 => Tick.Info) public override ticks;
    
    /// @dev Tick 位图
    mapping(int16 => uint256) public override tickBitmap;

    /// @dev 手续费累积
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    /// @dev 事件
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    modifier lock() {
        require(slot0.unlocked, "Pool: LOCKED");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        require(_token0 < _token1, "Pool: TOKEN_ORDER");
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        slot0.unlocked = true;
    }

    /// @notice 初始化池子（设置初始价格）
    function initialize(uint160 sqrtPriceX96) external {
        require(slot0.sqrtPriceX96 == 0, "Pool: ALREADY_INITIALIZED");
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: 1,
            observationCardinalityNext: 1,
            feeProtocol: 0,
            unlocked: true
        });
    }

    /// @notice 添加流动性
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(tickLower < tickUpper, "Pool: INVALID_TICK_RANGE");
        require(tickLower >= TickMath.MIN_TICK && tickUpper <= TickMath.MAX_TICK, "Pool: TICK_OUT_OF_RANGE");
        require(amount > 0, "Pool: INSUFFICIENT_LIQUIDITY_MINTED");

        Slot0 memory slot0_ = slot0;
        uint128 liquidityBefore = liquidity;

        // 更新 tick 信息
        bool flippedLower = ticks.update(tickLower, int128(int256(uint256(amount))), false);
        bool flippedUpper = ticks.update(tickUpper, -int128(int256(uint256(amount))), true);

        if (flippedLower) {
            tickBitmap.flipTick(tickLower, tickSpacing);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(tickUpper, tickSpacing);
        }

        // 计算需要转移的代币数量
        (amount0, amount1) = SqrtPriceMath.getAmountsForLiquidity(
            slot0_.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount
        );

        // 更新流动性
        liquidity = LiquidityMath.addDelta(liquidityBefore, int128(int256(uint256(amount))));

        // 转移代币
        if (amount0 > 0) {
            IERC20Minimal(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20Minimal(token1).transferFrom(msg.sender, address(this), amount1);
        }

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @notice 移除流动性
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(tickLower < tickUpper, "Pool: INVALID_TICK_RANGE");

        Slot0 memory slot0_ = slot0;
        uint128 liquidityBefore = liquidity;

        // 更新 tick 信息
        bool flippedLower = ticks.update(tickLower, -int128(int256(uint256(amount))), false);
        bool flippedUpper = ticks.update(tickUpper, int128(int256(uint256(amount))), true);

        if (flippedLower) {
            tickBitmap.flipTick(tickLower, tickSpacing);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(tickUpper, tickSpacing);
        }

        // 计算返回的代币数量
        (amount0, amount1) = SqrtPriceMath.getAmountsForLiquidity(
            slot0_.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount
        );

        // 更新流动性
        liquidity = LiquidityMath.addDelta(liquidityBefore, -int128(int256(uint256(amount))));

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @notice 执行交换
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override lock returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "Pool: INVALID_AMOUNT");

        Slot0 memory slot0Start = slot0;
        require(slot0Start.unlocked, "Pool: LOCKED");
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "Pool: INVALID_PRICE_LIMIT"
        );

        // 简化的交换逻辑（完整实现需要更复杂的 tick 遍历）
        uint160 sqrtPriceX96 = slot0Start.sqrtPriceX96;
        uint128 liquidity_ = liquidity;

        // 计算交换后的价格和数量
        if (zeroForOne) {
            // token0 -> token1
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountOut = getAmountOut(amountIn, sqrtPriceX96, liquidity_);
            sqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity_,
                amountIn,
                true
            );
            amount0 = int256(amountIn);
            amount1 = -int256(amountOut);
        } else {
            // token1 -> token0
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountOut = getAmountOut(amountIn, sqrtPriceX96, liquidity_);
            sqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity_,
                amountIn,
                false
            );
            amount0 = -int256(amountOut);
            amount1 = int256(amountIn);
        }

        // 更新状态
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0.sqrtPriceX96 = sqrtPriceX96;
        slot0.tick = tick;

        // 转移输入代币（从调用者到池子）
        if (amount0 > 0) {
            IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(amount0));
        } else if (amount1 > 0) {
            IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(amount1));
        }

        // 转移输出代币（从池子到接收者）
        if (amount0 < 0) {
            IERC20Minimal(token0).transfer(recipient, uint256(-amount0));
        }
        if (amount1 < 0) {
            IERC20Minimal(token1).transfer(recipient, uint256(-amount1));
        }

        emit Swap(msg.sender, recipient, amount0, amount1, sqrtPriceX96, liquidity_, tick);
    }

    /// @notice 收集手续费
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 简化实现：返回请求的数量（完整实现需要计算累积的手续费）
        amount0 = amount0Requested;
        amount1 = amount1Requested;
        
        if (amount0 > 0) {
            IERC20Minimal(token0).transfer(recipient, amount0);
        }
        if (amount1 > 0) {
            IERC20Minimal(token1).transfer(recipient, amount1);
        }
    }

    /// @dev 简化的输出数量计算（完整实现需要更复杂的逻辑）
    function getAmountOut(
        uint256 amountIn,
        uint160 sqrtPriceX96,
        uint128 liquidity_
    ) private pure returns (uint256) {
        // 简化公式：实际实现需要考虑手续费和更精确的计算
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;
        return (amountIn * price) / (1e18 + price);
    }
}

