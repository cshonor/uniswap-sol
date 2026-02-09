# Uniswap V3 LiquidityNet 详解

本文档详细说明 Uniswap V3 中的 LiquidityNet（净流动性）概念，这是理解流动性变化的关键。

## 📋 概述

**LiquidityNet** 是 Uniswap V3 中用于跟踪流动性变化的重要概念。它表示当价格跨越某个 tick 时，活跃流动性的净变化量。

---

## 🎯 什么是 LiquidityNet？

### 定义

**LiquidityNet** 表示当价格从 tick 的一侧移动到另一侧时，活跃流动性的净变化。

**关键点：**
- **正值**：价格向上跨越 tick 时，流动性增加
- **负值**：价格向上跨越 tick 时，流动性减少
- **零值**：跨越 tick 时，流动性不变

### 为什么需要 LiquidityNet？

在交换过程中，价格会跨越多个 tick：
- 每个 tick 可能对应一个价格区间的边界
- 跨越 tick 时，活跃流动性会发生变化
- 需要快速更新当前活跃流动性

---

## 🔧 LiquidityNet 的工作原理

### Tick 信息结构

```solidity
struct Info {
    uint128 liquidityGross;  // 总流动性（双向）
    int128 liquidityNet;     // 净流动性变化
    // ... 其他字段
}
```

### 流动性边界

**价格区间边界：**
- 每个价格区间有两个边界：`tickLower` 和 `tickUpper`
- 当价格跨越边界时，流动性会变化

**示例：**
```
价格区间: [tickLower, tickUpper]
         ↓              ↓
价格:    tickLower    tickUpper
流动性:  开始          结束
```

### LiquidityNet 的计算

**添加流动性时：**
```solidity
// 在 tickLower
liquidityNet += liquidity  // 价格向上跨越时，流动性增加

// 在 tickUpper
liquidityNet -= liquidity  // 价格向上跨越时，流动性减少
```

**移除流动性时：**
```solidity
// 在 tickLower
liquidityNet -= liquidity  // 价格向上跨越时，流动性减少

// 在 tickUpper
liquidityNet += liquidity  // 价格向上跨越时，流动性增加
```

---

## 📊 实际示例

### 示例 1：添加流动性

**场景：**
- 价格区间：[$1900, $2100]
- 添加流动性：L = 1000

**Tick 更新：**
```
tickLower = 75900:
  liquidityGross += 1000
  liquidityNet += 1000  // 价格向上跨越时，流动性增加

tickUpper = 76100:
  liquidityGross += 1000
  liquidityNet -= 1000  // 价格向上跨越时，流动性减少
```

### 示例 2：交换过程

**初始状态：**
- 当前价格：$2000 (tick = 76000)
- 当前活跃流动性：L = 5000

**价格区间分布：**
```
区间1: [75800, 76000] - L = 2000
区间2: [75900, 76100] - L = 3000
当前价格: 76000
```

**执行交换（ETH → USDC，价格下降）：**

**跨越 tick = 76000：**
```
检查 tick 76000 的 liquidityNet
liquidityNet = -2000  // 区间1 的上边界
活跃流动性: 5000 - 2000 = 3000
```

**跨越 tick = 75900：**
```
检查 tick 75900 的 liquidityNet
liquidityNet = +3000  // 区间2 的下边界
活跃流动性: 3000 + 3000 = 6000
```

---

## 🔄 在 Swap 中的应用

### 交换流程

```solidity
function swap(...) external {
    // 1. 获取当前活跃流动性
    uint128 liquidity = slot0.liquidity;
    
    // 2. 查找下一个 tick
    (int24 nextTick, bool initialized) = 
        TickBitmap.nextInitializedTickWithinOneWord(...);
    
    // 3. 计算到下一个 tick 的交换
    // ...
    
    // 4. 跨越 tick 时更新流动性
    if (tick == nextTick) {
        // 获取 tick 的 liquidityNet
        int128 liquidityNet = ticks[nextTick].liquidityNet;
        
        // 更新活跃流动性
        if (zeroForOne) {
            liquidity = LiquidityMath.addDelta(liquidity, liquidityNet);
        } else {
            liquidity = LiquidityMath.addDelta(liquidity, -liquidityNet);
        }
    }
}
```

### 方向性

**重要：** LiquidityNet 的方向取决于交换方向：

**zeroForOne（token0 → token1，价格下降）：**
```
liquidity += liquidityNet
```

**oneForZero（token1 → token0，价格上升）：**
```
liquidity -= liquidityNet
```

---

## 💡 为什么是"Net"？

### Gross vs Net

**liquidityGross（总流动性）：**
- 该 tick 上所有价格区间的流动性总和
- 不考虑方向

**liquidityNet（净流动性）：**
- 价格向上跨越 tick 时的净变化
- 考虑方向（增加或减少）

### 示例

**场景：**
- tick = 76000 上有两个价格区间：
  - 区间1: [75800, 76000] - L = 2000
  - 区间2: [76000, 76200] - L = 3000

**计算：**
```
liquidityGross = 2000 + 3000 = 5000
liquidityNet = -2000 + 3000 = +1000
```

**解释：**
- 价格向上跨越 76000 时：
  - 离开区间1：-2000
  - 进入区间2：+3000
  - 净变化：+1000

---

## 📈 流动性累积

### 多个价格区间

当多个价格区间共享同一个 tick 时：

```solidity
// 添加流动性时
info.liquidityGross = LiquidityMath.addDelta(
    info.liquidityGross, 
    liquidityDelta
);

info.liquidityNet = upper
    ? info.liquidityNet - liquidityDelta  // 上边界
    : info.liquidityNet + liquidityDelta; // 下边界
```

### 移除流动性

当流动性变为 0 时：
```solidity
if (liquidityGrossAfter == 0) {
    // 清除 tick 信息
    delete self[tick];
    // 从 Bitmap 中移除
    TickBitmap.flipTick(tickBitmap, tick, tickSpacing);
}
```

---

## ⚠️ 注意事项

### 1. 方向性

- LiquidityNet 的方向很重要
- 必须根据交换方向正确应用

### 2. 符号

- LiquidityNet 可以是正数或负数
- 使用 `int128` 类型存储

### 3. 初始化

- 只有当 tick 有流动性时才会初始化
- 流动性为 0 时，tick 会被清除

### 4. Gas 优化

- 只在跨越 tick 时更新流动性
- 避免频繁的状态更新

---

## 🔗 相关文档

- [Tick 与价格表示](./TICK_AND_PRICE.md) - 理解 Tick 系统
- [Tick Bitmap](./TICK_BITMAP.md) - 了解如何查找 tick
- [Cross Tick Swap](./CROSS_TICK_SWAP.md) - 了解跨 tick 交换

---

## 🎓 总结

LiquidityNet 是 Uniswap V3 流动性管理的核心：

1. **定义**：价格跨越 tick 时的净流动性变化
2. **计算**：根据价格区间边界计算
3. **应用**：在交换过程中更新活跃流动性
4. **方向性**：根据交换方向正确应用
5. **优化**：高效管理流动性变化

理解 LiquidityNet 对于理解 Uniswap V3 的交换机制至关重要。

