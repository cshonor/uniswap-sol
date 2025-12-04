# Uniswap V3 架构学习指南

本文档详细说明 Uniswap V3 的核心架构，包括与 V2 的区别、关键概念和实现细节。

## 📚 目录

1. [V3 与 V2 的主要区别](#v3-与-v2-的主要区别)
2. [核心概念](#核心概念)
3. [V3 架构概述](#v3-架构概述)
4. [Core 合约](#core-合约)
5. [Periphery 合约](#periphery-合约)
6. [关键算法](#关键算法)

---

## V3 与 V2 的主要区别

### 1. 集中流动性（Concentrated Liquidity）

**V2**：流动性均匀分布在整个价格区间 `[0, ∞]`
- LP 需要提供两种代币，比例固定
- 流动性利用效率较低

**V3**：LP 可以选择价格区间 `[p_a, p_b]`
- 只需要在选定价格区间提供流动性
- 流动性利用效率大幅提升（最高可达 4000 倍）

```
V2: 流动性分布
价格: 0 ────────────────────────────────────> ∞
流动性: ████████████████████████████████

V3: 集中流动性
价格: 0 ────────────────────────────────────> ∞
      [区间1: p1-p2]    [区间2: p3-p4]
流动性: ████                    ████
```

### 2. 流动性代币表示

**V2**：使用 ERC20 LP Token
- 每个 LP 获得相同比例的 LP tokens
- 可以转账、交易 LP tokens

**V3**：使用 ERC721 NFT
- 每个流动性仓位是一个 NFT
- 每个仓位有独立的参数（价格区间、流动性等）
- 更灵活的流动性管理

### 3. 手续费层级

**V2**：单一手续费率（通常 0.3%）

**V3**：三个手续费层级
- **0.05%**：稳定币对（USDC/USDT）
- **0.3%**：常见交易对（ETH/USDC）
- **1%**：非常规/高风险代币对

### 4. 价格表示

**V2**：直接使用储备量比例
- `price = reserve1 / reserve0`

**V3**：使用平方根价格（√P）和 Tick
- `sqrtPrice = sqrt(price)`
- `tick = log_{1.0001}(price)`
- 更精确的价格计算

---

## 核心概念

### 1. Tick 系统

**Tick**：价格被离散化为 ticks，每个 tick 对应一个价格。

```
tick = floor(log_{1.0001}(price))
price = 1.0001^tick
```

**Tick Spacing**：每个手续费层级有不同的 tick 间隔
- 0.05% fee: tickSpacing = 10
- 0.3% fee: tickSpacing = 60
- 1% fee: tickSpacing = 200

**示例**：
```
当前价格: $2000 (ETH/USDC)
对应的 tick: log_{1.0001}(2000) ≈ 76000

价格范围 [1990, 2010] 对应 ticks:
- tick_lower = 76000 - 10 = 75990
- tick_upper = 76000 + 10 = 76010
```

### 2. 集中流动性公式

V3 使用改进的恒定乘积公式：

```
(x + L / √p_b) * (y + L * √p_a) = L²
```

其中：
- `x`: token0 的数量
- `y`: token1 的数量
- `L`: 流动性数量（liquidity）
- `p_a`: 价格下限
- `p_b`: 价格上限

**关键公式**：
```solidity
// 在价格区间 [p_a, p_b] 内，给定流动性 L，计算代币数量

// 当前价格 p < p_a 时，全部是 token0
x = L * (1/√p_a - 1/√p_b)

// 当前价格 p > p_b 时，全部是 token1
y = L * (√p_b - √p_a)

// 当前价格 p 在 [p_a, p_b] 内时
x = L * (1/√p - 1/√p_b)
y = L * (√p - √p_a)
```

### 3. 流动性计算

**添加流动性时**：
```solidity
// 给定代币数量和价格区间，计算流动性 L
if (currentPrice <= priceLower) {
    L = amount0 / (1/√p_a - 1/√p_b)
} else if (currentPrice >= priceUpper) {
    L = amount1 / (√p_b - √p_a)
} else {
    // 价格在区间内，需要两种代币
    L0 = amount0 / (1/√p - 1/√p_b)
    L1 = amount1 / (√p - √p_a)
    L = min(L0, L1)
}
```

### 4. 手续费累积

V3 在每次交换时累积手续费：
- 手续费以两种代币的形式累积
- 按流动性份额分配给 LP
- 累积在全局变量中，按比例分配

---

## V3 架构概述

### Core 合约

1. **UniswapV3Pool** - 交易池合约
   - 管理单个交易对的流动性
   - 存储所有 tick 的状态
   - 执行交换操作
   - 累积手续费

2. **UniswapV3Factory** - 工厂合约
   - 创建新的交易池
   - 管理所有池子
   - 设置手续费层级

3. **UniswapV3PoolDeployer** - 池子部署器（内部合约）

### Periphery 合约

1. **NonfungiblePositionManager** - NFT 仓位管理器
   - 创建和管理流动性仓位
   - 每个仓位是一个 NFT
   - 添加/移除流动性
   - 收集手续费

2. **SwapRouter** - 交换路由
   - 执行代币交换
   - 支持多跳交换
   - 滑点保护

3. **Libraries** - 工具库
   - **TickMath** - Tick 和价格转换
   - **SqrtPriceMath** - 平方根价格计算
   - **LiquidityMath** - 流动性计算

---

## Core 合约详解

### UniswapV3Pool

#### 核心状态变量

```solidity
struct Slot0 {
    uint160 sqrtPriceX96;  // 当前价格的平方根，Q96 格式
    int24 tick;            // 当前 tick
    uint16 observationIndex;
    uint16 observationCardinality;
    uint16 observationCardinalityNext;
    uint8 feeProtocol;     // 协议手续费
    bool unlocked;
}

struct Info {
    uint128 liquidity;     // 当前 tick 的流动性
}

mapping(int24 => Tick.Info) public ticks;      // 每个 tick 的信息
mapping(int16 => uint256) public tickBitmap;   // Tick 位图
```

#### 关键函数

**1. swap()** - 执行交换
```solidity
function swap(
    address recipient,
    bool zeroForOne,  // true: token0 -> token1
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
) external returns (int256 amount0, int256 amount1)
```

**流程**：
1. 验证调用者权限
2. 计算交换步数
3. 遍历 ticks，执行交换
4. 更新价格和 tick
5. 转移代币

**2. mint()** - 添加流动性
```solidity
function mint(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount,
    bytes calldata data
) external returns (uint256 amount0, uint256 amount1)
```

**3. burn()** - 移除流动性
```solidity
function burn(
    int24 tickLower,
    int24 tickUpper,
    uint128 amount
) external returns (uint256 amount0, uint256 amount1)
```

---

### UniswapV3Factory

```solidity
mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

function createPool(
    address tokenA,
    address tokenB,
    uint24 fee  // 手续费层级：500, 3000, 10000
) external returns (address pool)
```

**关键点**：
- 使用 CREATE2 确保池子地址可预测
- 支持多个手续费层级的池子（同一对代币可以有多个池子）
- 地址格式：`keccak256(abi.encode(token0, token1, fee))`

---

## Periphery 合约详解

### NonfungiblePositionManager

**继承关系**：
- ERC721 (NFT 标准)
- PeripheryImmutableState
- PoolInitializer

#### 核心功能

**1. mint()** - 创建新的流动性仓位
```solidity
function mint(MintParams calldata params)
    external
    payable
    returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    )
```

**参数**：
```solidity
struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;      // 价格区间下限
    int24 tickUpper;      // 价格区间上限
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;   // 滑点保护
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
}
```

**流程**：
1. 创建/获取池子地址
2. 计算需要的流动性
3. 调用池子的 mint() 函数
4. 铸造 NFT 给用户
5. 存储仓位信息到 NFT

**2. increaseLiquidity()** - 增加流动性
```solidity
function increaseLiquidity(IncreaseLiquidityParams calldata params)
    external
    payable
    returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    )
```

**3. decreaseLiquidity()** - 减少流动性
```solidity
function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1)
```

**4. collect()** - 收集手续费
```solidity
function collect(CollectParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1)
```

---

## 关键算法

### 1. Tick 查找算法

使用位图（Bitmap）快速查找下一个有流动性的 tick：

```solidity
// 查找下一个已初始化的 tick
function nextInitializedTickWithinOneWord(
    mapping(int16 => uint256) storage self,
    int24 tick,
    int24 tickSpacing,
    bool lte
) internal view returns (int24 next, bool initialized)
```

### 2. 价格计算

```solidity
// Tick 转价格
function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
    // price = 1.0001^tick
    // sqrtPrice = sqrt(1.0001^tick) = 1.0001^(tick/2)
}

// 价格转 Tick
function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
    // 二分查找或使用数学公式
}
```

### 3. 流动性计算

```solidity
// 根据代币数量计算流动性
function getLiquidityForAmount0(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint256 amount0
) internal pure returns (uint128 liquidity) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }
    uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
    return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
}
```

---

## V3 vs V2 对比表

| 特性 | V2 | V3 |
|------|----|----|
| 流动性分布 | 全价格区间 | 可选择价格区间 |
| LP Token | ERC20 | ERC721 NFT |
| 手续费层级 | 1 个 (0.3%) | 3 个 (0.05%, 0.3%, 1%) |
| 价格表示 | 储备量比例 | 平方根价格 + Tick |
| 资本效率 | 基础 | 最高 4000 倍 |
| 复杂度 | 简单 | 复杂 |
| Gas 成本 | 较低 | 较高 |

---

## 学习路径建议

### 第一步：理解核心概念
1. 集中流动性的原理
2. Tick 系统和价格表示
3. 流动性计算公式

### 第二步：学习 Core 合约
1. Pool 合约的状态管理
2. swap() 函数的实现
3. 流动性添加/移除机制

### 第三步：学习 Periphery 合约
1. PositionManager 的 NFT 管理
2. 流动性仓位操作
3. 手续费收集

### 第四步：实践应用
1. 部署 V3 合约
2. 创建流动性仓位
3. 执行交换操作

---

## 参考资料

- [Uniswap V3 官方文档](https://docs.uniswap.org/contracts/v3/overview)
- [Uniswap V3 核心合约代码](https://github.com/Uniswap/v3-core)
- [Uniswap V3 Periphery 代码](https://github.com/Uniswap/v3-periphery)
- [Uniswap V3 白皮书](https://uniswap.org/whitepaper-v3.pdf)

---

## 总结

Uniswap V3 的核心创新是**集中流动性**：

1. **更高的资本效率**：LP 可以将流动性集中在价格区间内
2. **更灵活的策略**：LP 可以选择不同的价格区间和手续费层级
3. **更复杂的实现**：需要 Tick 系统、位图等复杂数据结构

V3 适合：
- 专业做市商
- 需要高资本效率的场景
- 稳定币对等低波动交易对

V2 仍然适合：
- 简单的流动性提供
- 低 Gas 成本的场景
- 学习 AMM 的基础概念

