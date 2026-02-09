# Uniswap V3 Tick Bitmap 详解

本文档详细说明 Uniswap V3 中的 Tick Bitmap 机制，包括如何存储和查找下一个有流动性的 tick。

## 📋 概述

**Tick Bitmap** 是 Uniswap V3 用于高效查找下一个有流动性的 tick 的数据结构。在交换过程中，需要快速找到下一个有流动性的 tick，Tick Bitmap 提供了高效的查找机制。

---

## 🎯 为什么需要 Tick Bitmap？

### 问题

在 Uniswap V3 中，交换可能跨越多个价格区间（多个 tick）：
- 每个 tick 可能有不同的流动性
- 需要找到下一个有流动性的 tick
- 如果遍历所有 tick，Gas 成本会非常高

### 解决方案

**Tick Bitmap：**
- 使用位图（bitmap）标记哪些 tick 有流动性
- 快速查找下一个有流动性的 tick
- 大幅降低 Gas 成本

---

## 🔧 Tick Bitmap 原理

### 数据结构

**存储方式：**
```solidity
mapping(int16 => uint256) public tickBitmap;
```

**结构：**
- Key：`wordPos`（word 位置，int16）
- Value：`uint256`（256 位，每个 bit 代表一个 tick）

### Word 和 Bit 位置

**计算方式：**
```solidity
function position(int24 tick, int24 tickSpacing) 
    internal pure returns (int16 wordPos, uint8 bitPos) 
{
    int24 compressed = tick / tickSpacing;
    if (tick < 0 && tick % tickSpacing != 0) compressed--; // 向下取整
    wordPos = int16(compressed >> 8);  // 每 256 个 tick 一个 word
    bitPos = uint8(uint24(compressed % 256));  // bit 在 word 中的位置
}
```

**示例（tickSpacing = 60）：**
```
tick = 120
compressed = 120 / 60 = 2
wordPos = 2 >> 8 = 0
bitPos = 2 % 256 = 2
```

### 位图操作

**翻转 tick 位（添加/移除流动性时）：**
```solidity
function flipTick(
    mapping(int16 => uint256) storage self,
    int24 tick,
    int24 tickSpacing
) internal {
    (int16 wordPos, uint8 bitPos) = position(tick, tickSpacing);
    uint256 mask = 1 << bitPos;
    self[wordPos] ^= mask;  // 异或操作，翻转 bit
}
```

**示例：**
```
tick = 120, tickSpacing = 60
wordPos = 0, bitPos = 2

初始: tickBitmap[0] = 0b...0000
翻转: tickBitmap[0] = 0b...0100  (bit 2 设为 1)
```

---

## 🔍 寻找下一个 Tick

### 核心函数

**`nextInitializedTickWithinOneWord`：**
```solidity
function nextInitializedTickWithinOneWord(
    mapping(int16 => uint256) storage self,
    int24 tick,
    int24 tickSpacing,
    bool lte  // true: 查找 <= tick, false: 查找 >= tick
) internal view returns (int24 next, bool initialized)
```

### 查找逻辑

**查找方向：**

1. **向前查找（lte = true）**：查找小于等于当前 tick 的下一个有流动性的 tick
2. **向后查找（lte = false）**：查找大于等于当前 tick 的下一个有流动性的 tick

**实现步骤：**

1. **压缩 tick**：`compressed = tick / tickSpacing`
2. **计算 word 和 bit 位置**
3. **创建掩码**：只检查当前 word 内的位
4. **查找下一个设置的 bit**
5. **返回对应的 tick**

### 示例：向前查找

**场景：**
- 当前 tick = 180
- tickSpacing = 60
- 查找下一个 <= 180 的有流动性的 tick

**步骤：**
```
1. compressed = 180 / 60 = 3
2. wordPos = 0, bitPos = 3
3. 创建掩码：检查 bit 0-3
4. tickBitmap[0] = 0b...1010 (bit 1 和 3 有流动性)
5. 找到 bit 3（最接近的）
6. next = 3 * 60 = 180
```

### 示例：向后查找

**场景：**
- 当前 tick = 180
- tickSpacing = 60
- 查找下一个 >= 180 的有流动性的 tick

**步骤：**
```
1. compressed = 180 / 60 = 3
2. wordPos = 0, bitPos = 4 (检查下一个 word)
3. 创建掩码：检查 bit 4-255
4. tickBitmap[0] = 0b...10100000 (bit 5 有流动性)
5. 找到 bit 5
6. next = (3 + 1 + 1) * 60 = 300
```

---

## 💡 在 Swap 中的应用

### 交换流程

在交换过程中，价格会跨越多个 tick：

```
当前价格 → tick1 → tick2 → tick3 → 最终价格
```

**使用 Tick Bitmap：**
1. 从当前 tick 开始
2. 使用 Bitmap 查找下一个有流动性的 tick
3. 计算到下一个 tick 的交换量
4. 更新价格和流动性
5. 重复直到完成交换

### 代码示例

```solidity
function swap(...) external {
    // 1. 获取当前 tick
    int24 tick = slot0.tick;
    
    // 2. 查找下一个有流动性的 tick
    (int24 nextTick, bool initialized) = 
        TickBitmap.nextInitializedTickWithinOneWord(
            tickBitmap,
            tick,
            tickSpacing,
            zeroForOne  // 交换方向
        );
    
    // 3. 计算到下一个 tick 的价格
    uint160 sqrtPriceNext = TickMath.getSqrtRatioAtTick(nextTick);
    
    // 4. 计算交换量
    // ...
    
    // 5. 更新价格和流动性
    // ...
}
```

---

## 📊 数据结构详解

### Word 结构

**每个 word（uint256）包含 256 个 bit：**
```
word[0]: bit 0-255   (对应 tick 0-255 * tickSpacing)
word[1]: bit 0-255   (对应 tick 256-511 * tickSpacing)
word[2]: bit 0-255   (对应 tick 512-767 * tickSpacing)
...
```

### Bit 含义

**Bit = 1：** 该 tick 有流动性（已初始化）
**Bit = 0：** 该 tick 没有流动性（未初始化）

### 存储优化

**优势：**
- 每个 tick 只占用 1 bit
- 256 个 tick 只需要 1 个 uint256
- 大幅节省存储空间

---

## 🔍 查找算法

### 向前查找（lte = true）

```solidity
// 创建掩码：检查当前 bit 及之前的所有 bit
uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
uint256 masked = self[wordPos] & mask;

// 查找最接近的已设置的 bit
if (masked != 0) {
    // 使用 BitMath.mostSignificantBit 找到最高位的 1
    next = (compressed - (bitPos - MSB(masked))) * tickSpacing;
} else {
    // 当前 word 内没有，返回 word 边界
    next = (compressed - bitPos) * tickSpacing;
}
```

### 向后查找（lte = false）

```solidity
// 创建掩码：检查当前 bit 之后的所有 bit
uint256 mask = ~((1 << bitPos) - 1);
uint256 masked = self[wordPos] & mask;

// 查找最接近的已设置的 bit
if (masked != 0) {
    // 使用 BitMath.leastSignificantBit 找到最低位的 1
    next = (compressed + 1 + (LSB(masked) - bitPos)) * tickSpacing;
} else {
    // 当前 word 内没有，返回下一个 word 的起始
    next = (compressed + 1 + (255 - bitPos)) * tickSpacing;
}
```

---

## ⚡ Gas 优化

### 为什么高效？

1. **位操作**：使用位运算，非常快速
2. **批量查找**：一次检查 256 个 tick
3. **减少存储**：每个 tick 只占 1 bit

### Gas 成本对比

**不使用 Bitmap（遍历所有 tick）：**
- 最坏情况：O(n)，n 为 tick 数量
- Gas 成本：非常高

**使用 Bitmap：**
- 平均情况：O(1)（在当前 word 内找到）
- 最坏情况：O(1)（需要检查多个 word，但通常很少）
- Gas 成本：大幅降低

---

## 💡 实际应用示例

### 示例：ETH/USDC 交换

**场景：**
- 当前 tick = 76000
- tickSpacing = 60
- 交换方向：ETH → USDC（价格下降）

**查找过程：**
```
1. compressed = 76000 / 60 = 1266
2. wordPos = 1266 >> 8 = 4
3. bitPos = 1266 % 256 = 242
4. 查找 bit 242 之前的已设置的 bit
5. 假设 bit 240 已设置
6. nextTick = (1266 - 2) * 60 = 75840
```

---

## ⚠️ 注意事项

### 1. Tick Spacing 对齐

- 只有对齐到 tickSpacing 的 tick 才会被记录
- 未对齐的 tick 不会出现在 Bitmap 中

### 2. 初始化检查

- 查找函数返回 `initialized` 标志
- 需要检查 tick 是否真的已初始化

### 3. 边界情况

- 到达 word 边界时需要检查下一个 word
- 需要处理负数 tick 的情况

### 4. Gas 成本

- 虽然优化了，但复杂交换仍需要多次查找
- 跨多个 word 的查找会增加 Gas

---

## 🔗 相关文档

- [Tick 与价格表示](./TICK_AND_PRICE.md) - 理解 Tick 系统
- [单价格区间内的 Swap](./SINGLE_RANGE_SWAP.md) - 了解交换流程
- [Cross Tick Swap](./CROSS_TICK_SWAP.md) - 了解跨 tick 交换

---

## 🎓 总结

Tick Bitmap 是 Uniswap V3 的重要优化：

1. **核心作用**：快速查找下一个有流动性的 tick
2. **数据结构**：使用位图存储 tick 初始化状态
3. **查找算法**：高效的位操作查找
4. **Gas 优化**：大幅降低交换的 Gas 成本
5. **应用场景**：交换过程中跨越多个 tick

理解 Tick Bitmap 对于理解 Uniswap V3 的交换机制至关重要。

