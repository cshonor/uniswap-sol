# Uniswap V3 Cross Tick Swap 详解

本文档详细说明 Uniswap V3 中跨多个 tick 的交换（Cross Tick Swap）机制。

## 📋 概述

**Cross Tick Swap** 是指交换过程中价格跨越多个 tick 的情况。与单价格区间内的交换不同，跨 tick 交换需要处理多个价格区间和流动性的变化。

---

## 🎯 什么是 Cross Tick Swap？

### 单区间交换 vs 跨 Tick 交换

**单价格区间内的交换：**
- 价格在一个价格区间内变化
- 流动性保持不变
- 相对简单

**跨 Tick 交换：**
- 价格跨越多个 tick
- 每个 tick 对应不同的流动性
- 需要处理流动性变化

### 为什么会有 Cross Tick Swap？

**原因：**
1. **大额交换**：交换量较大，价格变化幅度大
2. **流动性分散**：流动性分布在多个价格区间
3. **价格波动**：价格本身就在多个区间内

---

## 🔄 Cross Tick Swap 流程

### 完整流程

```
1. 从当前价格开始
   ↓
2. 查找下一个有流动性的 tick
   ↓
3. 计算到下一个 tick 的交换量
   ↓
4. 执行交换到下一个 tick
   ↓
5. 跨越 tick，更新流动性
   ↓
6. 重复步骤 2-5，直到完成交换
```

### 代码实现框架

```solidity
function swap(...) external {
    // 1. 初始化
    uint128 liquidity = slot0.liquidity;
    int24 tick = slot0.tick;
    uint160 sqrtPriceX96 = slot0.sqrtPriceX96;
    
    // 2. 循环处理每个 tick
    while (amountRemaining > 0) {
        // 2.1 查找下一个 tick
        (int24 nextTick, bool initialized) = 
            TickBitmap.nextInitializedTickWithinOneWord(
                tickBitmap,
                tick,
                tickSpacing,
                zeroForOne
            );
        
        // 2.2 计算到下一个 tick 的价格
        uint160 sqrtPriceNext = TickMath.getSqrtRatioAtTick(nextTick);
        
        // 2.3 计算交换量
        (uint256 amountIn, uint256 amountOut) = 
            computeSwapStep(
                sqrtPriceX96,
                sqrtPriceNext,
                liquidity,
                amountRemaining
            );
        
        // 2.4 更新状态
        sqrtPriceX96 = sqrtPriceNext;
        amountRemaining -= amountIn;
        
        // 2.5 跨越 tick，更新流动性
        if (sqrtPriceX96 == sqrtPriceNext) {
            tick = zeroForOne ? nextTick - 1 : nextTick;
            
            if (initialized) {
                int128 liquidityNet = ticks[nextTick].liquidityNet;
                liquidity = LiquidityMath.addDelta(
                    liquidity,
                    zeroForOne ? -liquidityNet : liquidityNet
                );
            }
        }
    }
    
    // 3. 更新最终状态
    slot0.sqrtPriceX96 = sqrtPriceX96;
    slot0.tick = tick;
    slot0.liquidity = liquidity;
}
```

---

## 📊 详细步骤说明

### 步骤 1：查找下一个 Tick

**使用 Tick Bitmap：**
```solidity
(int24 nextTick, bool initialized) = 
    TickBitmap.nextInitializedTickWithinOneWord(
        tickBitmap,
        tick,
        tickSpacing,
        zeroForOne  // 交换方向
    );
```

**返回：**
- `nextTick`：下一个有流动性的 tick
- `initialized`：该 tick 是否已初始化

### 步骤 2：计算交换步长

**计算到下一个 tick 的交换：**
```solidity
function computeSwapStep(
    uint160 sqrtPriceCurrent,
    uint160 sqrtPriceTarget,
    uint128 liquidity,
    uint256 amountRemaining
) internal pure returns (
    uint256 amountIn,
    uint256 amountOut
) {
    // 计算在当前流动性下，到目标价格需要的输入量
    // ...
}
```

### 步骤 3：执行交换

**更新价格和数量：**
```solidity
sqrtPriceX96 = sqrtPriceNext;
amountRemaining -= amountIn;
amountOutTotal += amountOut;
```

### 步骤 4：跨越 Tick

**更新流动性：**
```solidity
if (sqrtPriceX96 == sqrtPriceNext) {
    // 价格到达了下一个 tick
    tick = zeroForOne ? nextTick - 1 : nextTick;
    
    if (initialized) {
        // 获取该 tick 的净流动性变化
        int128 liquidityNet = ticks[nextTick].liquidityNet;
        
        // 根据方向更新流动性
        liquidity = LiquidityMath.addDelta(
            liquidity,
            zeroForOne ? -liquidityNet : liquidityNet
        );
    }
}
```

---

## 💡 实际示例

### 示例：ETH/USDC 大额交换

**初始状态：**
- 当前价格：$2000 (tick = 76000)
- 当前流动性：L = 5000
- 交换：100 ETH → USDC（价格下降）

**价格区间分布：**
```
区间1: [75800, 76000] - L = 2000
区间2: [75900, 76100] - L = 3000
区间3: [75700, 75900] - L = 1500
当前价格: 76000
```

**交换过程：**

**第 1 步：**
- 当前 tick = 76000
- 查找下一个 tick = 75900
- 计算交换到 tick 75900
- 跨越 tick 76000：liquidity -= 2000 = 3000

**第 2 步：**
- 当前 tick = 75900
- 查找下一个 tick = 75800
- 计算交换到 tick 75800
- 跨越 tick 75900：liquidity += 3000 = 6000

**第 3 步：**
- 当前 tick = 75800
- 查找下一个 tick = 75700
- 计算交换到 tick 75700
- 跨越 tick 75800：liquidity -= 1500 = 4500

**继续直到完成交换...**

---

## 🔍 关键机制

### 1. 流动性更新

**规则：**
- 价格向上跨越 tick：`liquidity += liquidityNet`
- 价格向下跨越 tick：`liquidity -= liquidityNet`

**原因：**
- 进入新的价格区间，获得该区间的流动性
- 离开旧的价格区间，失去该区间的流动性

### 2. 价格计算

**每个 tick 对应一个价格：**
```solidity
sqrtPrice = TickMath.getSqrtRatioAtTick(tick);
```

**交换到下一个 tick：**
- 计算在当前流动性下，需要多少输入才能到达下一个价格

### 3. 交换步长

**限制因素：**
1. **剩余交换量**：还有多少需要交换
2. **价格限制**：下一个 tick 的价格
3. **流动性**：当前可用的流动性

---

## ⚡ Gas 优化

### 为什么需要优化？

**问题：**
- 跨多个 tick 需要多次查找和更新
- 每个 tick 都需要 Gas
- 大额交换可能跨越很多 tick

### 优化策略

1. **Tick Bitmap**：快速查找下一个 tick
2. **批量处理**：一次处理多个 tick（如果可能）
3. **Gas 限制**：限制单次交换跨越的 tick 数量

---

## ⚠️ 注意事项

### 1. Gas 限制

- 跨太多 tick 可能导致 Gas 不足
- 需要限制单次交换的 tick 数量
- 可能需要分多次交换

### 2. 价格滑点

- 跨多个 tick 意味着价格变化较大
- 需要设置合理的滑点保护

### 3. 流动性变化

- 每个 tick 的流动性可能不同
- 需要正确更新活跃流动性

### 4. 边界情况

- 处理最后一个 tick
- 处理没有更多 tick 的情况

---

## 🔗 相关文档

- [Tick Bitmap](./TICK_BITMAP.md) - 了解如何查找 tick
- [LiquidityNet](./LIQUIDITY_NET.md) - 了解流动性变化
- [单价格区间内的 Swap](./SINGLE_RANGE_SWAP.md) - 了解单区间交换

---

## 🎓 总结

Cross Tick Swap 是 Uniswap V3 交换机制的核心：

1. **定义**：价格跨越多个 tick 的交换
2. **流程**：查找 tick → 计算交换 → 执行交换 → 更新流动性
3. **关键机制**：流动性更新、价格计算、交换步长
4. **优化**：使用 Tick Bitmap 快速查找
5. **注意事项**：Gas 限制、价格滑点、流动性变化

理解 Cross Tick Swap 对于理解 Uniswap V3 的完整交换机制至关重要。

