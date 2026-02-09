# Uniswap V3 Tick 与价格表示详解

本文档详细说明 Uniswap V3 中的 Tick 系统和价格表示方式，这是理解 V3 的关键。

## 📋 概述

Uniswap V3 使用 **Tick** 系统来表示价格，而不是像 V2 那样直接使用储备量比例。这种设计提供了更高的精度和更灵活的价格管理。

---

## 🎯 为什么需要 Tick？

### V2 的问题

**V2 价格表示：**
```
price = reserve1 / reserve0
```

**问题：**
- 精度有限
- 难以表示极端价格
- 价格计算不够精确

### V3 的解决方案

**V3 价格表示：**
```
price = 1.0001^tick
sqrtPrice = sqrt(price) = 1.0001^(tick/2)
```

**优势：**
- 高精度（使用 Q96 格式）
- 可以表示极端价格
- 精确的价格计算

---

## 🔢 Tick 系统

### Tick 定义

**Tick** 是一个整数，表示价格的离散化值：

```
tick = floor(log_{1.0001}(price))
price = 1.0001^tick
```

**关键参数：**
- 基础：`1.0001`（每个 tick 价格变化 0.01%）
- Tick 范围：`[-887272, 887272]`
- 对应价格范围：约 `[2^-128, 2^128]`

### Tick 到价格转换

**公式：**
```
price = 1.0001^tick
```

**示例：**
```
tick = 0    → price = 1.0001^0 = 1.0
tick = 6931 → price = 1.0001^6931 ≈ 2.0
tick = 13863 → price = 1.0001^13863 ≈ 4.0
```

### 价格到 Tick 转换

**公式：**
```
tick = floor(log_{1.0001}(price))
```

**示例：**
```
price = 1.0  → tick = 0
price = 2.0  → tick ≈ 6931
price = 2000 → tick ≈ 76000
```

---

## 📊 平方根价格（sqrtPrice）

### 为什么使用 sqrtPrice？

**原因：**
1. **计算效率**：避免频繁开方运算
2. **精度**：使用 Q96 格式（96 位小数）
3. **存储**：更紧凑的存储方式

### sqrtPrice 定义

```
sqrtPrice = sqrt(price) = 1.0001^(tick/2)
```

**格式：** Q96（96 位定点数）

**示例：**
```
price = 1.0  → sqrtPrice = 1.0 * 2^96 = 79228162514264337593543950336
price = 4.0  → sqrtPrice = 2.0 * 2^96 = 158456325028528675187087900672
```

### Tick 到 sqrtPrice 转换

**公式：**
```
sqrtPrice = 1.0001^(tick/2) * 2^96
```

**实现：**
```solidity
function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
    // 使用近似算法计算 sqrtPrice
    // ...
}
```

---

## 🔧 Tick Spacing

### 定义

**Tick Spacing** 是 tick 的间隔，用于限制可用的 tick 值。

**不同手续费层级的 Tick Spacing：**
- **0.05% fee**: tickSpacing = 10
- **0.3% fee**: tickSpacing = 60
- **1% fee**: tickSpacing = 200

### 为什么需要 Tick Spacing？

**原因：**
1. **Gas 优化**：减少需要存储的 tick 数量
2. **流动性集中**：鼓励流动性集中在特定 tick
3. **计算效率**：简化计算

### Tick 对齐

**规则：**
```
tick % tickSpacing == 0
```

**示例（tickSpacing = 60）：**
```
有效 tick: ..., -120, -60, 0, 60, 120, ...
无效 tick: ..., -90, -30, 30, 90, ...
```

---

## 💡 价格区间表示

### 使用 Tick 表示价格区间

**价格区间：** `[p_a, p_b]`

**转换为 Tick：**
```
tickLower = floor(log_{1.0001}(p_a))
tickUpper = floor(log_{1.0001}(p_b))
```

**示例：**
```
价格区间: [$1900, $2100]
tickLower = floor(log_{1.0001}(1900)) ≈ 75900
tickUpper = floor(log_{1.0001}(2100)) ≈ 76100
```

### 价格区间对齐

**规则：**
- tickLower 和 tickUpper 必须对齐到 tickSpacing
- 使用 `floor(tick / tickSpacing) * tickSpacing`

**示例（tickSpacing = 60）：**
```
原始: tickLower = 75923, tickUpper = 76145
对齐: tickLower = 75900, tickUpper = 76140
```

---

## 📐 价格计算示例

### 示例 1：ETH/USDC

**当前价格：** $2000

**计算 Tick：**
```
tick = floor(log_{1.0001}(2000)) ≈ 76000
```

**计算 sqrtPrice：**
```
sqrtPrice = sqrt(2000) * 2^96
```

**价格区间 [$1900, $2100]：**
```
tickLower = floor(log_{1.0001}(1900)) ≈ 75900
tickUpper = floor(log_{1.0001}(2100)) ≈ 76100
```

### 示例 2：稳定币对

**当前价格：** $1.0

**计算 Tick：**
```
tick = floor(log_{1.0001}(1.0)) = 0
```

**价格区间 [$0.99, $1.01]：**
```
tickLower = floor(log_{1.0001}(0.99)) ≈ -100
tickUpper = floor(log_{1.0001}(1.01)) ≈ 100
```

---

## 🔍 实现细节

### TickMath 库

Uniswap V3 提供了 `TickMath` 库来处理 Tick 和价格转换：

```solidity
library TickMath {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;
    
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96);
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick);
}
```

### 精度考虑

**Q96 格式：**
- 使用 160 位整数存储 sqrtPrice
- 96 位用于小数部分
- 提供高精度计算

**示例：**
```
实际价格: 2000.0
sqrtPrice: 447213595499957939281834733746 * 2^96
```

---

## ⚠️ 注意事项

### 1. Tick 范围限制

- Tick 必须在 `[-887272, 887272]` 范围内
- 超出范围会导致计算错误

### 2. Tick Spacing 对齐

- 价格区间必须对齐到 tickSpacing
- 否则无法创建流动性仓位

### 3. 精度损失

- Tick 是离散的，可能无法精确表示所有价格
- 每个 tick 对应 0.01% 的价格变化

### 4. Gas 成本

- Tick 计算需要 Gas
- 复杂的价格区间可能增加 Gas 成本

---

## 🔗 相关文档

- [Uniswap V3 简介](./INTRODUCTION.md) - 了解 V3 整体架构
- [集中流动性](./CONCENTRATED_LIQUIDITY.md) - 理解价格区间的作用
- [流动性计算](./LIQUIDITY_CALCULATION.md) - 学习如何使用 Tick 计算流动性
- [Tick Bitmap](./TICK_BITMAP.md) - 了解 Tick 的存储和查找

---

## 🎓 总结

Tick 和价格表示是 Uniswap V3 的核心：

1. **Tick 系统**：使用离散的 tick 值表示价格
2. **价格公式**：`price = 1.0001^tick`
3. **sqrtPrice**：使用平方根价格提高计算效率
4. **Tick Spacing**：不同手续费层级有不同的间隔
5. **价格区间**：使用 tickLower 和 tickUpper 表示

理解 Tick 系统对于有效使用 Uniswap V3 至关重要。

