# Uniswap V3 手续费计算详解

本文档详细说明 Uniswap V3 中的手续费计算机制，包括手续费累积、分配和收集方式。

## 📋 概述

Uniswap V3 的手续费机制比 V2 更复杂，因为需要处理集中流动性和多个价格区间。手续费按流动性份额分配给 LP，并通过累积机制高效计算。

---

## 💰 手续费层级

### 三个手续费层级

Uniswap V3 提供三个手续费层级：

- **0.05%**：稳定币对（USDC/USDT、DAI/USDC）
- **0.3%**：常见交易对（ETH/USDC、WBTC/ETH）
- **1%**：非常规/高风险代币对

### 手续费率

**固定费率：**
- 每个池子只有一个手续费层级
- 在创建池子时确定
- 不可更改

---

## 🔢 手续费计算方式

### 交换时的手续费

**计算方式：**
```solidity
// 手续费 = 输入数量 × 手续费率
uint256 feeAmount = amountIn * fee / 1000000;  // fee 是基点，如 3000 = 0.3%

// 实际进入池子的数量
uint256 amountInAfterFee = amountIn - feeAmount;
```

**示例（0.3% 手续费）：**
```
输入：1000 USDC
手续费：1000 × 0.003 = 3 USDC
实际进入池子：997 USDC
```

### 手续费分配

**分配方式：**
- 手续费以两种代币的形式累积
- 按流动性份额分配给 LP
- 累积在全局变量中

---

## 📊 手续费累积机制

### 全局手续费累积

**数据结构：**
```solidity
uint256 public feeGrowthGlobal0X128;  // token0 的全局手续费累积
uint256 public feeGrowthGlobal1X128;  // token1 的全局手续费累积
```

**格式：** Q128（128 位定点数）

**更新方式：**
```solidity
// 每次交换后更新
feeGrowthGlobal0X128 += (feeAmount0 * 2^128) / liquidity;
feeGrowthGlobal1X128 += (feeAmount1 * 2^128) / liquidity;
```

### Tick 级别的手续费累积

**Tick 信息：**
```solidity
struct Info {
    uint256 feeGrowthOutside0X128;  // tick 外部的 token0 手续费累积
    uint256 feeGrowthOutside1X128;  // tick 外部的 token1 手续费累积
    // ...
}
```

**作用：**
- 记录 tick 外部的手续费累积
- 用于计算价格区间内的手续费

---

## 🔄 手续费累积流程

### 交换时的手续费累积

**步骤：**

1. **计算手续费**
   ```solidity
   uint256 feeAmount0 = amount0In * fee / 1000000;
   uint256 feeAmount1 = amount1In * fee / 1000000;
   ```

2. **更新全局累积**
   ```solidity
   feeGrowthGlobal0X128 += FullMath.mulDiv(
       feeAmount0,
       2^128,
       liquidity
   );
   feeGrowthGlobal1X128 += FullMath.mulDiv(
       feeAmount1,
       2^128,
       liquidity
   );
   ```

3. **更新 Tick 累积**
   ```solidity
   // 更新当前 tick 外部的累积
   if (tick < currentTick) {
       tick.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - tick.feeGrowthOutside0X128;
   }
   ```

### 跨越 Tick 时的更新

**当价格跨越 tick 时：**
```solidity
// 翻转 tick 的手续费累积
if (tick <= currentTick) {
    // tick 在价格下方，累积在外部
    tick.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - tick.feeGrowthOutside0X128;
} else {
    // tick 在价格上方，累积在外部（已经是外部）
    // 不需要更新
}
```

---

## 💡 手续费计算示例

### 示例 1：单次交换

**场景：**
- 交换：1000 USDC → ETH
- 手续费率：0.3%
- 当前流动性：L = 10000

**计算：**
```
1. 手续费 = 1000 × 0.003 = 3 USDC
2. 实际进入池子 = 997 USDC
3. 全局累积更新：
   feeGrowthGlobal0X128 += (3 × 2^128) / 10000
```

### 示例 2：多个价格区间

**场景：**
- 价格区间1: [75800, 76000] - L = 2000
- 价格区间2: [75900, 76100] - L = 3000
- 当前价格：76000
- 交换跨越两个区间

**手续费分配：**
```
总流动性：L = 5000
手续费：3 USDC

区间1 获得：3 × (2000 / 5000) = 1.2 USDC
区间2 获得：3 × (3000 / 5000) = 1.8 USDC
```

---

## 📈 LP 手续费收益计算

### 计算 LP 应得的手续费

**公式：**
```solidity
// 计算价格区间内的手续费累积
uint256 feeGrowthInside0X128 = feeGrowthGlobal0X128 
    - tickLower.feeGrowthOutside0X128 
    - tickUpper.feeGrowthOutside0X128;

// LP 应得的手续费
uint256 tokensOwed0 = FullMath.mulDiv(
    feeGrowthInside0X128 - position.feeGrowthInside0Last0X128,
    position.liquidity,
    2^128
);
```

### 完整计算流程

**步骤：**

1. **获取全局累积**
   ```solidity
   uint256 feeGrowthGlobal0 = pool.feeGrowthGlobal0X128();
   uint256 feeGrowthGlobal1 = pool.feeGrowthGlobal1X128();
   ```

2. **计算区间内的累积**
   ```solidity
   uint256 feeGrowthInside0 = calculateFeeGrowthInside(
       tickLower,
       tickUpper,
       currentTick,
       feeGrowthGlobal0
   );
   ```

3. **计算 LP 份额**
   ```solidity
   uint256 tokensOwed0 = FullMath.mulDiv(
       feeGrowthInside0 - feeGrowthInside0Last,
       liquidity,
       2^128
   );
   ```

---

## 🔍 手续费累积的复杂性

### 为什么复杂？

**原因：**
1. **集中流动性**：不同价格区间有不同的流动性
2. **价格变化**：价格可能在不同区间之间移动
3. **流动性变化**：LP 可能添加或移除流动性

### 解决方案

**使用累积机制：**
- 全局累积：记录总的手续费
- Tick 累积：记录 tick 外部的累积
- 位置累积：记录 LP 上次收集时的累积

**计算方式：**
```
LP 应得 = (当前累积 - 上次累积) × 流动性份额
```

---

## 💰 收集手续费

### collect 函数

**函数签名：**
```solidity
function collect(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount0Requested,
    uint128 amount1Requested
) external returns (uint256 amount0, uint256 amount1)
```

**功能：**
- 计算 LP 应得的手续费
- 转移手续费给 LP
- 更新位置的手续费累积记录

### 实现逻辑

```solidity
function collect(...) external returns (uint256 amount0, uint256 amount1) {
    // 1. 计算应得的手续费
    (uint256 fee0, uint256 fee1) = calculateFees(
        tickLower,
        tickUpper,
        position.liquidity
    );
    
    // 2. 限制请求的数量
    amount0 = fee0 < amount0Requested ? fee0 : amount0Requested;
    amount1 = fee1 < amount1Requested ? fee1 : amount1Requested;
    
    // 3. 更新位置记录
    position.tokensOwed0 -= amount0;
    position.tokensOwed1 -= amount1;
    
    // 4. 转移手续费
    if (amount0 > 0) token0.transfer(recipient, amount0);
    if (amount1 > 0) token1.transfer(recipient, amount1);
}
```

---

## 📊 手续费收益示例

### 示例：ETH/USDC 池子

**场景：**
- 价格区间：[$1900, $2100]
- LP 流动性：L = 1000
- 总流动性：L_total = 10000
- 期间手续费：30 USDC + 0.015 ETH

**计算：**
```
LP 份额 = 1000 / 10000 = 10%

LP 应得：
- USDC: 30 × 10% = 3 USDC
- ETH: 0.015 × 10% = 0.0015 ETH
```

---

## ⚠️ 注意事项

### 1. 手续费累积精度

- 使用 Q128 格式保证精度
- 累积值可能非常大
- 需要注意溢出问题

### 2. 价格区间外的手续费

- 价格超出区间时，不获得手续费
- 只有价格在区间内时才获得手续费

### 3. 流动性变化

- 添加/移除流动性时，需要更新手续费累积记录
- 确保手续费正确分配

### 4. Gas 成本

- 计算手续费需要 Gas
- 频繁收集可能不划算

---

## 🔗 相关文档

- [集中流动性](./CONCENTRATED_LIQUIDITY.md) - 理解流动性分布
- [LiquidityNet](./LIQUIDITY_NET.md) - 了解流动性变化
- [添加流动性案例](./ADD_LIQUIDITY_CASE.md) - 了解如何获得手续费

---

## 🎓 总结

Uniswap V3 的手续费计算机制：

1. **手续费层级**：三个固定费率（0.05%/0.3%/1%）
2. **累积机制**：全局累积 + Tick 累积 + 位置累积
3. **分配方式**：按流动性份额分配
4. **计算方式**：使用 Q128 格式保证精度
5. **收集方式**：通过 collect 函数收集手续费

理解手续费计算对于理解 LP 的收益机制至关重要。

