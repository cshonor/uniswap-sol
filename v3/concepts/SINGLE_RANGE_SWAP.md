# Uniswap V3 单价格区间内的 Swap 详解

本文档详细说明 Uniswap V3 中在单个价格区间内执行交换的机制，这是理解跨 tick 交换的基础。

## 📋 概述

**单价格区间内的 Swap** 是指交换过程中价格始终在一个价格区间内，不跨越任何 tick 边界的情况。这是最简单的交换场景，也是理解更复杂交换的基础。

---

## 🎯 什么是单价格区间内的 Swap？

### 定义

**单价格区间内的 Swap：**
- 价格在区间 `[tickLower, tickUpper]` 内变化
- 不跨越任何 tick 边界
- 流动性保持不变

### 与跨 Tick 交换的区别

**单区间交换：**
```
价格: tickLower ──────→ tickUpper
流动性: 保持不变
```

**跨 Tick 交换：**
```
价格: tick1 → tick2 → tick3 → ...
流动性: 在每个 tick 处变化
```

---

## 🔧 单区间交换的工作原理

### 核心公式

在单个价格区间内，使用改进的恒定乘积公式：

```
(x + L / √p_b) * (y + L * √p_a) = L²
```

其中：
- `x`：token0 的数量
- `y`：token1 的数量
- `L`：流动性（保持不变）
- `p_a`：价格下限
- `p_b`：价格上限

### 价格变化

**交换前：**
```
价格: p1
token0: x1 = L * (1/√p1 - 1/√p_b)
token1: y1 = L * (√p1 - √p_a)
```

**交换后：**
```
价格: p2
token0: x2 = L * (1/√p2 - 1/√p_b)
token1: y2 = L * (√p2 - √p_a)
```

**交换量：**
```
Δx = x2 - x1 = L * (1/√p2 - 1/√p1)
Δy = y2 - y1 = L * (√p2 - √p1)
```

---

## 📊 交换计算

### 根据输入计算输出

**已知：** 输入数量 `amountIn`，当前价格 `sqrtPriceX96`，流动性 `L`

**计算新价格：**
```solidity
function getNextSqrtPriceFromInput(
    uint160 sqrtPX96,    // 当前 sqrtPrice
    uint128 liquidity,   // 流动性
    uint256 amountIn,    // 输入数量
    bool zeroForOne     // 交换方向
) internal pure returns (uint160 sqrtQX96) {
    if (zeroForOne) {
        // token0 → token1，价格上升
        // 公式: sqrtQ = (L * sqrtP) / (L + amountIn * sqrtP)
        sqrtQX96 = getNextSqrtPriceFromAmount0RoundingUp(
            sqrtPX96, liquidity, amountIn, true
        );
    } else {
        // token1 → token0，价格下降
        // 公式: sqrtQ = sqrtP + amountIn / L
        sqrtQX96 = getNextSqrtPriceFromAmount1RoundingDown(
            sqrtPX96, liquidity, amountIn, true
        );
    }
}
```

### 根据输出计算输入

**已知：** 输出数量 `amountOut`，当前价格 `sqrtPriceX96`，流动性 `L`

**计算新价格：**
```solidity
function getNextSqrtPriceFromOutput(
    uint160 sqrtPX96,
    uint128 liquidity,
    uint256 amountOut,
    bool zeroForOne
) internal pure returns (uint160 sqrtQX96) {
    // 反向计算
    // ...
}
```

---

## 💡 实际示例

### 示例 1：ETH → USDC（价格上升）

**初始状态：**
- 价格区间：[$1900, $2100]
- 当前价格：$2000
- 流动性：L = 10000
- 交换：1 ETH → USDC

**计算：**

**步骤 1：计算当前代币数量**
```
x1 = L * (1/√2000 - 1/√2100) ≈ 0.5 ETH
y1 = L * (√2000 - √1900) ≈ 1000 USDC
```

**步骤 2：计算新价格**
```
输入：1 ETH
新价格：p2 ≈ $2100（接近区间上限）
```

**步骤 3：计算输出**
```
y2 = L * (√2100 - √1900) ≈ 2000 USDC
输出：y2 - y1 ≈ 1000 USDC
```

### 示例 2：USDC → ETH（价格下降）

**初始状态：**
- 价格区间：[$1900, $2100]
- 当前价格：$2000
- 流动性：L = 10000
- 交换：2000 USDC → ETH

**计算：**

**步骤 1：计算新价格**
```
输入：2000 USDC
新价格：p2 ≈ $1900（接近区间下限）
```

**步骤 2：计算输出**
```
x2 = L * (1/√1900 - 1/√2100) ≈ 1 ETH
x1 = L * (1/√2000 - 1/√2100) ≈ 0.5 ETH
输出：x2 - x1 ≈ 0.5 ETH
```

---

## 🔍 价格限制

### 价格不能超出区间

**限制：**
- 交换后的价格必须在区间 `[p_a, p_b]` 内
- 如果计算出的价格超出区间，只能交换到区间边界

**处理：**
```solidity
uint160 sqrtPriceNext = getNextSqrtPriceFromInput(...);

// 检查是否超出区间
if (zeroForOne) {
    // token0 → token1，价格上升
    if (sqrtPriceNext > sqrtRatioBX96) {
        sqrtPriceNext = sqrtRatioBX96;  // 限制到上限
    }
} else {
    // token1 → token0，价格下降
    if (sqrtPriceNext < sqrtRatioAX96) {
        sqrtPriceNext = sqrtRatioAX96;  // 限制到下限
    }
}
```

### 部分交换

**如果价格到达边界：**
- 只能执行部分交换
- 剩余部分需要跨 tick 处理

---

## 📈 流动性不变性

### 关键特性

**在单区间内：**
- 流动性 `L` 保持不变
- 只有代币比例变化
- 价格在区间内变化

**验证：**
```
交换前: (x1 + L/√p_b) * (y1 + L*√p_a) = L²
交换后: (x2 + L/√p_b) * (y2 + L*√p_a) = L²
```

---

## ⚡ 实现细节

### 交换步骤

```solidity
function swapInSingleRange(
    uint160 sqrtPriceCurrent,
    uint160 sqrtPriceTarget,
    uint128 liquidity,
    uint256 amountIn,
    bool zeroForOne
) internal pure returns (uint256 amountOut) {
    // 1. 计算新价格
    uint160 sqrtPriceNew = getNextSqrtPriceFromInput(
        sqrtPriceCurrent,
        liquidity,
        amountIn,
        zeroForOne
    );
    
    // 2. 限制到目标价格（如果超出区间）
    if (zeroForOne) {
        if (sqrtPriceNew > sqrtPriceTarget) {
            sqrtPriceNew = sqrtPriceTarget;
        }
    } else {
        if (sqrtPriceNew < sqrtPriceTarget) {
            sqrtPriceNew = sqrtPriceTarget;
        }
    }
    
    // 3. 计算输出数量
    amountOut = getAmountOut(
        sqrtPriceCurrent,
        sqrtPriceNew,
        liquidity,
        zeroForOne
    );
    
    return amountOut;
}
```

---

## ⚠️ 注意事项

### 1. 价格边界

- 价格不能超出区间
- 需要检查并限制价格

### 2. 流动性要求

- 需要足够的流动性
- 流动性不足可能导致价格大幅变化

### 3. 滑点

- 大额交换可能导致较大滑点
- 需要设置滑点保护

### 4. 精度

- 使用 Q96 格式保证精度
- 注意舍入误差

---

## 🔗 相关文档

- [流动性计算](./LIQUIDITY_CALCULATION.md) - 了解流动性公式
- [Cross Tick Swap](./CROSS_TICK_SWAP.md) - 了解跨 tick 交换
- [Tick 与价格表示](./TICK_AND_PRICE.md) - 理解价格系统

---

## 🎓 总结

单价格区间内的 Swap 是 Uniswap V3 交换的基础：

1. **定义**：价格在单个区间内变化，不跨越 tick
2. **公式**：使用改进的恒定乘积公式
3. **计算**：根据输入/输出计算新价格
4. **限制**：价格不能超出区间
5. **特性**：流动性保持不变

理解单区间交换是理解更复杂交换机制的基础。

