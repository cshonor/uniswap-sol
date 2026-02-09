# Uniswap V3 流动性计算详解

本文档详细说明 Uniswap V3 中流动性的计算方法，包括如何根据代币数量计算流动性，以及如何根据流动性计算代币数量。

## 📋 概述

在 Uniswap V3 中，**流动性（Liquidity）** 是核心概念。与 V2 不同，V3 的流动性计算需要考虑价格区间，不同价格区间和价格位置需要不同的计算方法。

---

## 🎯 什么是流动性？

### 定义

**流动性（Liquidity，用 L 表示）** 是衡量价格区间内代币数量的抽象概念。

**关键点：**
- 流动性决定代币数量
- 不同价格区间有不同的流动性
- 流动性可以累加（多个区间）

### 为什么需要流动性？

**原因：**
1. **集中流动性**：只在选定价格区间提供流动性
2. **精确计算**：使用流动性可以精确计算代币数量
3. **效率优化**：避免重复计算

---

## 📐 流动性公式

### V3 的流动性公式

V3 使用改进的恒定乘积公式：

```
(x + L / √p_b) * (y + L * √p_a) = L²
```

其中：
- `x`：token0 的数量
- `y`：token1 的数量
- `L`：流动性数量
- `p_a`：价格下限（tickLower 对应的价格）
- `p_b`：价格上限（tickUpper 对应的价格）

### 公式推导

**恒定乘积：**
```
x * y = k
```

**在价格区间 [p_a, p_b] 内：**
```
x = L * (1/√p - 1/√p_b)
y = L * (√p - √p_a)
```

**验证：**
```
x * y = L² * (1/√p - 1/√p_b) * (√p - √p_a)
      = L² * (1 - √p/√p_b - √p_a/√p + √p_a/√p_b)
      ≈ L² (当 p 在区间内时)
```

---

## 🔢 根据代币数量计算流动性

### 场景 1：当前价格低于价格区间

**条件：** `p < p_a`

**公式：**
```
L = amount0 / (1/√p_a - 1/√p_b)
```

**特点：**
- 只需要 token0
- token1 = 0

**实现：**
```solidity
function getLiquidityForAmount0(
    uint160 sqrtRatioAX96,  // √p_a * 2^96
    uint160 sqrtRatioBX96,  // √p_b * 2^96
    uint256 amount0
) internal pure returns (uint128 liquidity) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }
    uint256 intermediate = FullMath.mulDiv(
        sqrtRatioAX96, 
        sqrtRatioBX96, 
        FixedPoint96.Q96
    );
    return toUint128(FullMath.mulDiv(
        amount0, 
        intermediate, 
        sqrtRatioBX96 - sqrtRatioAX96
    ));
}
```

### 场景 2：当前价格高于价格区间

**条件：** `p > p_b`

**公式：**
```
L = amount1 / (√p_b - √p_a)
```

**特点：**
- 只需要 token1
- token0 = 0

**实现：**
```solidity
function getLiquidityForAmount1(
    uint160 sqrtRatioAX96,  // √p_a * 2^96
    uint160 sqrtRatioBX96,  // √p_b * 2^96
    uint256 amount1
) internal pure returns (uint128 liquidity) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }
    return toUint128(FullMath.mulDiv(
        amount1, 
        FixedPoint96.Q96, 
        sqrtRatioBX96 - sqrtRatioAX96
    ));
}
```

### 场景 3：当前价格在价格区间内

**条件：** `p_a ≤ p ≤ p_b`

**公式：**
```
L0 = amount0 / (1/√p - 1/√p_b)
L1 = amount1 / (√p - √p_a)
L = min(L0, L1)
```

**特点：**
- 需要两种代币
- 取较小值，确保比例正确

**实现：**
```solidity
function getLiquidityForAmounts(
    uint160 sqrtRatioX96,   // 当前 √p * 2^96
    uint160 sqrtRatioAX96,  // √p_a * 2^96
    uint160 sqrtRatioBX96,  // √p_b * 2^96
    uint256 amount0,
    uint256 amount1
) internal pure returns (uint128 liquidity) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }

    if (sqrtRatioX96 <= sqrtRatioAX96) {
        // 价格低于区间，只用 token0
        liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
    } else if (sqrtRatioX96 < sqrtRatioBX96) {
        // 价格在区间内，需要两种代币
        uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
        uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
        liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    } else {
        // 价格高于区间，只用 token1
        liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
    }
}
```

---

## 🔄 根据流动性计算代币数量

### 场景 1：当前价格低于价格区间

**公式：**
```
amount0 = L * (1/√p_a - 1/√p_b)
amount1 = 0
```

### 场景 2：当前价格高于价格区间

**公式：**
```
amount0 = 0
amount1 = L * (√p_b - √p_a)
```

### 场景 3：当前价格在价格区间内

**公式：**
```
amount0 = L * (1/√p - 1/√p_b)
amount1 = L * (√p - √p_a)
```

**实现：**
```solidity
function getAmountsForLiquidity(
    uint160 sqrtRatioX96,
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity
) internal pure returns (uint256 amount0, uint256 amount1) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }

    if (sqrtRatioX96 <= sqrtRatioAX96) {
        amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    } else if (sqrtRatioX96 < sqrtRatioBX96) {
        amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
        amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
    } else {
        amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}
```

---

## 💡 实际计算示例

### 示例 1：价格在区间内

**场景：**
- 价格区间：[$1900, $2100]
- 当前价格：$2000
- 提供：1000 USDC

**计算：**
```
1. 转换为 sqrtPrice（Q96 格式）
   √p_a = √1900 * 2^96
   √p = √2000 * 2^96
   √p_b = √2100 * 2^96

2. 计算流动性
   L0 = 1000 / (1/√2000 - 1/√2100)
   L1 = ? / (√2000 - √1900)
   
   由于只提供了 USDC，需要计算需要多少 ETH
   假设需要 amount1 ETH
   L1 = amount1 / (√2000 - √1900)
   
   取 L = min(L0, L1)
```

### 示例 2：价格低于区间

**场景：**
- 价格区间：[$1900, $2100]
- 当前价格：$1800
- 提供：1 ETH

**计算：**
```
由于 p < p_a，只需要 ETH
L = 1 / (1/√1900 - 1/√2100)
```

### 示例 3：价格高于区间

**场景：**
- 价格区间：[$1900, $2100]
- 当前价格：$2200
- 提供：2200 USDC

**计算：**
```
由于 p > p_b，只需要 USDC
L = 2200 / (√2100 - √1900)
```

---

## 📊 流动性累加

### 多个价格区间

当多个价格区间有流动性时：

```solidity
// 总流动性 = 所有区间的流动性之和
uint128 totalLiquidity = 0;
for (每个价格区间) {
    totalLiquidity += 该区间的流动性;
}
```

### 当前活跃流动性

**定义：**
- 当前价格所在的区间的流动性总和

**计算：**
```solidity
uint128 activeLiquidity = 0;
for (每个包含当前价格的价格区间) {
    activeLiquidity += 该区间的流动性;
}
```

---

## 🔍 精度考虑

### Q96 格式

**为什么使用 Q96？**
- 提高计算精度
- 避免浮点数运算
- 使用定点数表示

**格式：**
```
实际值 = 存储值 / 2^96
```

**示例：**
```
实际价格：2000
sqrtPrice = √2000 * 2^96
```

### 溢出保护

**注意事项：**
- 流动性使用 `uint128` 存储
- 需要检查溢出
- 使用 SafeMath 或检查

---

## ⚠️ 注意事项

### 1. 价格区间对齐

- 价格区间必须对齐到 tickSpacing
- 否则无法计算

### 2. 代币比例

- 价格在区间内时，必须按比例提供两种代币
- 取较小值确保比例正确

### 3. 价格变化

- 价格超出区间时，流动性变为单一代币
- 需要重新计算

### 4. 精度损失

- 使用整数运算，可能有精度损失
- 需要合理处理

---

## 🔗 相关文档

- [集中流动性](./CONCENTRATED_LIQUIDITY.md) - 理解价格区间的作用
- [Tick 与价格表示](./TICK_AND_PRICE.md) - 理解价格表示方式
- [添加流动性案例](./ADD_LIQUIDITY_CASE.md) - 实际应用案例

---

## 🎓 总结

流动性计算是 Uniswap V3 的核心：

1. **流动性公式**：基于改进的恒定乘积公式
2. **三种场景**：价格低于/在/高于区间
3. **双向计算**：代币数量 ↔ 流动性
4. **精度处理**：使用 Q96 格式
5. **实际应用**：添加/移除流动性时使用

理解流动性计算对于有效使用 Uniswap V3 至关重要。

