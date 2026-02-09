# Uniswap V3 添加流动性案例详解

本文档通过实际案例详细说明如何在 Uniswap V3 中添加流动性，包括参数选择、计算过程和注意事项。

## 📋 概述

添加流动性是 Uniswap V3 的核心操作之一。与 V2 不同，V3 需要选择价格区间，这使得操作更复杂但也更灵活。

---

## 🎯 案例 1：ETH/USDC 池子 - 价格在区间内

### 场景设置

**参数：**
- 交易对：ETH/USDC
- 当前价格：$2000
- 手续费层级：0.3% (tickSpacing = 60)
- 价格区间：[$1900, $2100]
- 提供代币：1 ETH + 2000 USDC

### 步骤 1：确定 Tick 值

**计算 Tick：**
```
tickLower = floor(log_{1.0001}(1900)) ≈ 75900
tickUpper = floor(log_{1.0001}(2100)) ≈ 76100

对齐到 tickSpacing (60):
tickLower = floor(75900 / 60) * 60 = 75900
tickUpper = floor(76100 / 60) * 60 = 76100
```

### 步骤 2：计算流动性

**当前价格在区间内，需要两种代币：**

```solidity
// 转换为 sqrtPrice (Q96)
uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(76000);  // 当前价格
uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(75900);  // 下限
uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(76100);  // 上限

// 计算流动性
uint128 liquidity0 = SqrtPriceMath.getLiquidityForAmount0(
    sqrtPriceX96,
    sqrtRatioBX96,
    1 * 10**18  // 1 ETH
);

uint128 liquidity1 = SqrtPriceMath.getLiquidityForAmount1(
    sqrtRatioAX96,
    sqrtPriceX96,
    2000 * 10**6  // 2000 USDC
);

uint128 liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
```

**结果：**
- liquidity ≈ 44721 (假设值)
- 实际使用：1 ETH + 2000 USDC（按比例）

### 步骤 3：执行添加流动性

```solidity
NonfungiblePositionManager positionManager = ...;

INonfungiblePositionManager.MintParams memory params = 
    INonfungiblePositionManager.MintParams({
        token0: WETH,
        token1: USDC,
        fee: 3000,  // 0.3%
        tickLower: 75900,
        tickUpper: 76100,
        amount0Desired: 1 * 10**18,
        amount1Desired: 2000 * 10**6,
        amount0Min: 0.95 * 10**18,  // 滑点保护
        amount1Min: 1900 * 10**6,
        recipient: msg.sender,
        deadline: block.timestamp + 300
    });

(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
    positionManager.mint(params);
```

### 结果

- **获得 NFT**：tokenId（代表这个流动性仓位）
- **流动性**：liquidity
- **实际使用**：amount0 ETH + amount1 USDC

---

## 🎯 案例 2：稳定币对 - 窄价格区间

### 场景设置

**参数：**
- 交易对：USDC/USDT
- 当前价格：$1.0
- 手续费层级：0.05% (tickSpacing = 10)
- 价格区间：[$0.995, $1.005]（非常窄）
- 提供代币：10,000 USDC + 10,000 USDT

### 步骤 1：确定 Tick 值

**计算 Tick：**
```
tickLower = floor(log_{1.0001}(0.995)) ≈ -50
tickUpper = floor(log_{1.0001}(1.005)) ≈ 50

对齐到 tickSpacing (10):
tickLower = floor(-50 / 10) * 10 = -50
tickUpper = floor(50 / 10) * 10 = 50
```

### 步骤 2：计算流动性

**当前价格在区间内：**

```solidity
uint128 liquidity0 = SqrtPriceMath.getLiquidityForAmount0(...);
uint128 liquidity1 = SqrtPriceMath.getLiquidityForAmount1(...);
uint128 liquidity = min(liquidity0, liquidity1);
```

**特点：**
- 价格区间非常窄
- 资本效率极高
- 需要精确的代币比例

### 结果

- **流动性**：非常高（因为区间窄）
- **资本效率**：接近 100%
- **风险**：价格容易超出区间

---

## 🎯 案例 3：价格低于区间

### 场景设置

**参数：**
- 交易对：ETH/USDC
- 当前价格：$1800
- 价格区间：[$1900, $2100]
- 提供代币：1 ETH

### 步骤 1：计算流动性

**由于价格 < p_a，只需要 ETH：**

```solidity
uint128 liquidity = SqrtPriceMath.getLiquidityForAmount0(
    sqrtRatioAX96,  // √1900
    sqrtRatioBX96,  // √2100
    1 * 10**18      // 1 ETH
);
```

### 步骤 2：执行添加

```solidity
// 只需要提供 ETH，不需要 USDC
params = {
    amount0Desired: 1 * 10**18,
    amount1Desired: 0,
    // ...
};
```

### 结果

- **流动性**：全部是 ETH
- **等待价格上升**：当价格进入区间 [$1900, $2100] 时，ETH 会逐渐转换为 USDC
- **获得手续费**：价格在区间内时开始获得手续费

---

## 🎯 案例 4：价格高于区间

### 场景设置

**参数：**
- 交易对：ETH/USDC
- 当前价格：$2200
- 价格区间：[$1900, $2100]
- 提供代币：2200 USDC

### 步骤 1：计算流动性

**由于价格 > p_b，只需要 USDC：**

```solidity
uint128 liquidity = SqrtPriceMath.getLiquidityForAmount1(
    sqrtRatioAX96,  // √1900
    sqrtRatioBX96,  // √2100
    2200 * 10**6    // 2200 USDC
);
```

### 结果

- **流动性**：全部是 USDC
- **等待价格下降**：当价格进入区间 [$1900, $2100] 时，USDC 会逐渐转换为 ETH

---

## 💡 参数选择策略

### 1. 价格区间选择

**窄区间（稳定币对）：**
- 优势：资本效率高
- 劣势：价格容易超出区间
- 适用：稳定币对、价格波动小的交易对

**中等区间（主流交易对）：**
- 优势：平衡收益和风险
- 劣势：资本效率中等
- 适用：ETH/USDC、主流交易对

**宽区间（高风险代币）：**
- 优势：价格不易超出区间
- 劣势：资本效率低
- 适用：新代币、高波动性代币

### 2. 当前价格位置

**价格在区间内：**
- 需要两种代币
- 立即开始获得手续费
- 推荐：大多数情况

**价格低于区间：**
- 只需要 token0
- 等待价格上升
- 适用：看涨策略

**价格高于区间：**
- 只需要 token1
- 等待价格下降
- 适用：看跌策略

### 3. 滑点保护

**参数：**
- `amount0Min`：最小 token0 数量
- `amount1Min`：最小 token1 数量

**设置建议：**
- 通常设置为期望值的 95-99%
- 根据市场波动调整

---

## 📊 完整流程示例

### 使用 Position Manager

```solidity
// 1. 准备参数
INonfungiblePositionManager.MintParams memory params = 
    INonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
        fee: 3000,  // 0.3%
        tickLower: -60,   // 价格下限
        tickUpper: 60,    // 价格上限
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: amount0 * 95 / 100,  // 5% 滑点
        amount1Min: amount1 * 95 / 100,
        recipient: msg.sender,
        deadline: block.timestamp + 300
    });

// 2. 授权代币
IERC20(token0).approve(address(positionManager), amount0);
IERC20(token1).approve(address(positionManager), amount1);

// 3. 添加流动性
(uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) = 
    positionManager.mint(params);

// 4. 获得 NFT
// tokenId 代表这个流动性仓位
```

---

## ⚠️ 注意事项

### 1. 价格区间对齐

- 必须对齐到 tickSpacing
- 否则交易会失败

### 2. 代币比例

- 价格在区间内时，必须按比例提供
- 多余的代币会被退回

### 3. Gas 成本

- 添加流动性需要较多 Gas
- 考虑 Gas 成本是否值得

### 4. 价格超出区间

- 价格超出区间时，流动性变为单一代币
- 不再获得手续费
- 需要主动管理

### 5. 无常损失

- V3 仍然有无常损失
- 集中流动性可能放大损失
- 需要评估风险

---

## 🔗 相关文档

- [流动性计算](./LIQUIDITY_CALCULATION.md) - 了解流动性计算公式
- [集中流动性](./CONCENTRATED_LIQUIDITY.md) - 理解价格区间的作用
- [Tick 与价格表示](./TICK_AND_PRICE.md) - 理解 Tick 系统

---

## 🎓 总结

添加流动性是 Uniswap V3 的核心操作：

1. **选择价格区间**：根据策略选择合适的价格区间
2. **计算流动性**：根据代币数量和价格区间计算流动性
3. **执行添加**：通过 Position Manager 添加流动性
4. **获得 NFT**：获得代表流动性仓位的 NFT
5. **管理仓位**：需要主动管理价格区间

理解添加流动性的流程对于有效使用 Uniswap V3 至关重要。

