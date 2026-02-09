# Uniswap V2 架构学习指南

本文档详细说明 Uniswap V2 的核心架构，包括三个关键合约的关系和实现。

## 📚 目录（按学习顺序）

### 第一阶段：基础理解
1. [架构概述](#架构概述) - 理解整体设计
2. [CPAMM.sol - Pair 合约](#cpammsol---pair-合约) - 理解核心 AMM 逻辑

### 第二阶段：合约管理
3. [CPAMMFactory.sol - Factory 合约](#cpammfactorysol---factory-合约) - 理解如何创建和管理交易对

### 第三阶段：用户交互
4. [CPAMMRouter.sol - Router 合约](#cpammroutersol---router-合约) - 理解用户友好的接口

### 第四阶段：实际应用
5. [合约交互流程](#合约交互流程) - 理解完整的交互流程
6. [关键概念解析](#关键概念解析) - 深入理解设计原理

---

## 架构概述

Uniswap V2 采用 **Core + Periphery** 的架构设计：

```
┌─────────────────────────────────────────────────────────────┐
│                    Uniswap V2 架构                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │   Core（核心）    │         │  Periphery（外围）│         │
│  │                  │         │                  │         │
│  │  ┌────────────┐  │         │  ┌────────────┐  │         │
│  │  │  Factory   │  │────────▶│  │   Router   │  │         │
│  │  └─────┬──────┘  │         │  └────────────┘  │         │
│  │        │         │         │                  │         │
│  │        │ 创建    │         │  提供用户友好接口  │         │
│  │        ▼         │         │  封装核心合约调用  │         │
│  │  ┌────────────┐  │         │                  │         │
│  │  │   Pair     │  │         │                  │         │
│  │  │  (CPAMM)   │  │         │                  │         │
│  │  └────────────┘  │         │                  │         │
│  │                  │         │                  │         │
│  └──────────────────┘         └──────────────────┘         │
│                                                              │
│  不可升级、安全性高               可升级、功能丰富              │
└─────────────────────────────────────────────────────────────┘
```

### 设计原则

1. **Core（核心）**：简单、安全、不可升级
   - 包含最基础的 AMM 逻辑
   - 最小化攻击面
   - 一旦部署，永不更改

2. **Periphery（外围）**：灵活、功能丰富、可升级
   - 提供用户友好的接口
   - 可以添加新功能
   - 可以修复 bug 和优化

---

## Core（核心合约）

### CPAMM.sol - Pair 合约

**作用**：每个交易对的流动性池合约，类似 Uniswap V2 的 `Pair` 合约。

#### 核心功能

1. **管理流动性池**
   - 存储两种代币的储备量（`reserve0`, `reserve1`）
   - 实现恒定乘积公式：`x * y = k`

2. **添加流动性** (`addLiquidity`)
   ```solidity
   function addLiquidity(uint256 amount0, uint256 amount1) 
       external returns (uint256 liquidity)
   ```
   - 用户存入两种代币
   - 铸造流动性代币（LP tokens）给用户
   - 首次添加：`liquidity = sqrt(amount0 * amount1)`
   - 后续添加：按比例计算，取较小值

3. **移除流动性** (`removeLiquidity`)
   ```solidity
   function removeLiquidity(uint256 liquidity) 
       external returns (uint256 amount0, uint256 amount1)
   ```
   - 用户销毁 LP tokens
   - 按比例取回两种代币

4. **代币交换** (`swap`)
   ```solidity
   function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address to)
       external returns (uint256 amountOut)
   ```
   - 实现恒定乘积公式计算输出
   - 提供滑点保护

#### 关键代码解析

**恒定乘积公式计算输出**：
```solidity
function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
    public pure returns (uint256 amountOut)
{
    // 公式: (x + Δx) * (y - Δy) = x * y
    // 推导: Δy = (y * Δx) / (x + Δx)
    uint256 numerator = amountIn * reserveOut;
    uint256 denominator = reserveIn + amountIn;
    amountOut = numerator / denominator;
}
```

---

### CPAMMFactory.sol - Factory 合约

**作用**：创建和管理所有的交易对（Pair）合约。

#### 核心功能

1. **创建交易对** (`createPair`)
   ```solidity
   function createPair(address tokenA, address tokenB)
       external returns (address pair)
   ```
   - 检查交易对是否已存在
   - 确保代币顺序（token0 < token1）
   - 部署新的 CPAMM 合约
   - 记录交易对地址

2. **查询交易对** (`getPair`, `pairFor`)
   ```solidity
   function getPair(address tokenA, address tokenB) 
       external view returns (address pair)
   ```
   - 快速查找两个代币之间的交易对地址

3. **管理所有交易对** (`allPairs`, `allPairsLength`)
   - 存储所有已创建的交易对
   - 提供查询接口

#### 关键设计点

**代币排序**：
```solidity
// 确保 token0 < token1，避免重复创建
(address token0, address token1) = tokenA < tokenB
    ? (tokenA, tokenB)
    : (tokenB, tokenA);
```

**防止重复创建**：
```solidity
require(getPair[token0][token1] == address(0), "CPAMM: PAIR_EXISTS");
```

#### 工作流程

```
用户调用 createPair(tokenA, tokenB)
    ↓
Factory 检查是否已存在
    ↓
排序代币地址 (token0 < token1)
    ↓
部署新的 CPAMM 合约
    ↓
记录交易对地址到映射
    ↓
触发 PairCreated 事件
```

---

## Periphery（外围合约）

### CPAMMRouter.sol - Router 合约

**作用**：提供用户友好的接口，封装与核心合约的交互逻辑。

#### 核心功能

1. **智能添加流动性** (`addLiquidity`)
   ```solidity
   function addLiquidity(
       address tokenA,
       address tokenB,
       uint256 amountADesired,  // 期望数量
       uint256 amountBDesired,
       uint256 amountAMin,      // 最小数量（滑点保护）
       uint256 amountBMin,
       address to,
       uint256 deadline         // 截止时间
   ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)
   ```
   
   **优势**：
   - 自动计算最优代币比例
   - 如果池子已存在，自动调整数量保持比例
   - 如果池子不存在，自动创建
   - 提供滑点保护

2. **移除流动性** (`removeLiquidity`)
   - 支持滑点保护
   - 自动处理代币顺序

3. **代币交换** (`swapExactTokensForTokens`)
   ```solidity
   function swapExactTokensForTokens(
       uint256 amountIn,        // 精确输入
       uint256 amountOutMin,    // 最小输出（滑点保护）
       address[] calldata path, // 交换路径
       address to,
       uint256 deadline
   ) external returns (uint256[] memory amounts)
   ```
   
   **功能**：
   - 支持多跳交换（通过中间代币）
   - 自动计算最优路径
   - 提供滑点保护

4. **查询函数** (`getAmountsOut`, `getAmountsIn`)
   - 计算交换前的输出/输入数量
   - 帮助用户设置合理的滑点保护

#### 关键设计点

**自动比例调整**：
```solidity
// 如果用户想添加 1000 TokenA 和 2000 TokenB
// 但池子中比例是 1:1，Router 会自动调整为 1000:1000
uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
if (amountBOptimal <= amountBDesired) {
    // 使用 amountADesired 和 amountBOptimal
} else {
    // 使用 amountAOptimal 和 amountBDesired
}
```

**多跳交换**：
```solidity
// 例如：TokenA -> TokenB -> TokenC
// path = [TokenA, TokenB, TokenC]
// Router 会依次通过两个交易对完成交换
```

**截止时间保护**：
```solidity
modifier ensure(uint256 deadline) {
    require(deadline >= block.timestamp, "CPAMMRouter: EXPIRED");
    _;
}
```

---

## 合约交互流程

### 场景 1：首次添加流动性

```
用户
  ↓
Router.addLiquidity()
  ↓
Factory.createPair()  // 如果池子不存在
  ↓
CPAMM.addLiquidity()  // 添加代币
  ↓
铸造 LP tokens 给用户
```

### 场景 2：代币交换

```
用户
  ↓
Router.swapExactTokensForTokens()
  ↓
计算路径和数量
  ↓
转移输入代币到 Pair
  ↓
CPAMM.swap()  // 执行交换
  ↓
转移输出代币给用户
```

### 场景 3：通过 Router 添加流动性（池子已存在）

```
用户
  ↓
Router.addLiquidity()
  ↓
查询池子储备量
  ↓
计算最优比例
  ↓
调整用户输入数量
  ↓
CPAMM.addLiquidity()
  ↓
铸造 LP tokens
```

---

## 关键概念解析

### 1. 为什么需要 Factory？

- **统一管理**：所有交易对由 Factory 创建，便于管理和查询
- **地址可预测**：使用 CREATE2 可以提前计算交易对地址
- **防止重复**：确保每个代币对只有一个交易对

### 2. 为什么需要 Router？

- **用户体验**：用户不需要直接与 Pair 交互
- **自动优化**：自动计算最优代币比例
- **功能丰富**：支持多跳交换、滑点保护等
- **安全保护**：截止时间、最小输出等安全检查

### 3. Core vs Periphery

| 特性 | Core | Periphery |
|------|------|-----------|
| 安全性 | 最高（不可升级） | 较高（可升级修复） |
| 功能 | 基础功能 | 丰富功能 |
| 复杂度 | 简单 | 复杂 |
| 升级性 | 不可升级 | 可升级 |
| 用户交互 | 较少 | 较多 |

### 4. 三个合约的职责划分

- **CPAMM (Pair)**：管理单个交易对的流动性
- **Factory**：管理所有交易对，创建新交易对
- **Router**：为用户提供友好的交互接口

---

## 📖 推荐学习路径

### 🟢 初学者路径（1-2 天）

**目标：** 理解 V2 的基本架构和核心机制

1. **[架构概述](#架构概述)** - 了解 Core + Periphery 设计
2. **[CPAMM.sol - Pair 合约](#cpammsol---pair-合约)** - 掌握恒定乘积公式和基础操作

**完成标志：** 能够理解 AMM 的基本原理，知道如何添加/移除流动性和执行交换

---

### 🟡 进阶路径（2-4 天）

**目标：** 理解合约管理和用户交互

3. **[CPAMMFactory.sol - Factory 合约](#cpammfactorysol---factory-合约)** - 理解如何创建和管理交易对
4. **[CPAMMRouter.sol - Router 合约](#cpammroutersol---router-合约)** - 理解用户友好的接口

**完成标志：** 能够理解三个合约的关系，知道如何使用 Router 进行操作

---

### 🔴 高级路径（4-7 天）

**目标：** 深入理解交互流程和设计原理

5. **[合约交互流程](#合约交互流程)** - 理解完整的交互流程
6. **[关键概念解析](#关键概念解析)** - 深入理解设计原理

**完成标志：** 能够理解整个系统的设计思路，能够独立分析和优化

---

### 🎯 快速参考

**只想了解概念：** 阅读 1-2
**想要实际操作：** 阅读 1-4
**深入理解机制：** 阅读全部内容

---

## 💡 学习建议

### 第一步：理解 CPAMM.sol（Pair 合约）
- ✅ 掌握恒定乘积公式：`x * y = k`
- ✅ 理解流动性添加/移除机制
- ✅ 理解代币交换逻辑
- ✅ 理解滑点保护

### 第二步：理解 CPAMMFactory.sol
- ✅ 理解 Factory 模式的作用
- ✅ 理解代币排序的重要性（token0 < token1）
- ✅ 理解交易对管理和查询

### 第三步：理解 CPAMMRouter.sol
- ✅ 理解 Router 如何封装核心合约
- ✅ 理解自动比例调整机制
- ✅ 理解多跳交换（path）
- ✅ 理解滑点保护和截止时间

### 第四步：实际应用
- ✅ 部署三个合约
- ✅ 创建交易对
- ✅ 添加流动性
- ✅ 执行交换
- ✅ 理解完整的交互流程

---

## 参考资料

- [Uniswap V2 官方文档](https://docs.uniswap.org/contracts/v2/overview)
- [Uniswap V2 核心合约代码](https://github.com/Uniswap/v2-core)
- [Uniswap V2 Router 代码](https://github.com/Uniswap/v2-periphery)

---

## 总结

Uniswap V2 的架构设计体现了**关注点分离**和**安全性优先**的原则：

- **Core 合约**：专注核心逻辑，保证安全
- **Periphery 合约**：提供丰富功能，提升体验
- **三层架构**：Pair → Factory → Router，各司其职

通过这种设计，Uniswap V2 既保证了核心逻辑的安全性，又提供了灵活的功能扩展能力。

