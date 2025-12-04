# Uniswap V3 Core 合约

本目录包含 Uniswap V3 的核心合约实现。

## 目录结构

```
core/
├── libraries/          # 数学和工具库
│   ├── BitMath.sol           # 位操作工具
│   ├── TickMath.sol          # Tick 和价格转换
│   ├── SqrtPriceMath.sol     # 平方根价格计算
│   ├── LiquidityMath.sol     # 流动性计算
│   ├── Tick.sol              # Tick 信息管理
│   ├── TickBitmap.sol        # Tick 位图
│   ├── FullMath.sol          # 高精度数学运算
│   └── FixedPoint96.sol      # 固定点数常量
├── interfaces/        # 接口定义
│   ├── IERC20Minimal.sol
│   └── IUniswapV3Pool.sol
├── UniswapV3Factory.sol      # 工厂合约
└── UniswapV3Pool.sol         # 池子核心合约
```

## 核心合约

### UniswapV3Factory

工厂合约用于创建和管理交易池。

**主要功能：**
- `createPool(tokenA, tokenB, fee)`: 创建新的交易池
- `getPool(token0, token1, fee)`: 获取池子地址
- `allPoolsLength()`: 获取所有池子数量

**手续费层级：**
- `500` (0.05%): tickSpacing = 10
- `3000` (0.3%): tickSpacing = 60
- `10000` (1%): tickSpacing = 200

### UniswapV3Pool

池子核心合约，管理单个交易对的流动性。

**主要功能：**
- `initialize(sqrtPriceX96)`: 初始化池子（设置初始价格）
- `mint(recipient, tickLower, tickUpper, amount, data)`: 添加流动性
- `burn(tickLower, tickUpper, amount)`: 移除流动性
- `swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data)`: 执行交换
- `collect(recipient, tickLower, tickUpper, amount0Requested, amount1Requested)`: 收集手续费

## 使用示例

### 1. 部署工厂合约

```solidity
UniswapV3Factory factory = new UniswapV3Factory();
```

### 2. 创建池子

```solidity
address pool = factory.createPool(tokenA, tokenB, 3000); // 0.3% fee
```

### 3. 初始化池子

```solidity
// 计算初始价格的 sqrtPriceX96
uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0); // 价格 = 1
IUniswapV3Pool(pool).initialize(sqrtPriceX96);
```

### 4. 添加流动性

```solidity
IUniswapV3Pool(pool).mint(
    recipient,
    tickLower,  // 价格区间下限
    tickUpper,  // 价格区间上限
    liquidity,  // 流动性数量
    ""
);
```

### 5. 执行交换

```solidity
IUniswapV3Pool(pool).swap(
    recipient,
    true,       // zeroForOne: token0 -> token1
    amountIn,   // 输入数量
    sqrtPriceLimitX96, // 价格限制
    ""
);
```

## 注意事项

1. **价格表示**：V3 使用 sqrtPriceX96 (Q96 格式的平方根价格)
2. **Tick 系统**：价格被离散化为 ticks，每个 tick 对应一个价格
3. **集中流动性**：LP 可以选择价格区间提供流动性
4. **重入保护**：所有状态修改函数都使用 lock 修饰符

