# CPAMMFactory 合约详解

本文档详细说明 Uniswap V2 中 Factory（工厂）合约的作用、功能和实现原理。

## 📋 概述

Factory 合约是 Uniswap V2 架构中的核心组件之一，负责**创建和管理所有的交易对（Pair）合约**。它充当一个"工厂"，按需创建流动性池。

---

## 🎯 Factory 合约的作用

### 1. 创建交易对

Factory 合约的主要职责是创建新的交易对（Pair）合约。当用户想要为两个代币创建流动性池时，他们调用 Factory 合约的 `createPair` 函数。

### 2. 管理交易对

Factory 合约维护一个注册表，记录所有已创建的交易对，方便查询和管理。

### 3. 防止重复创建

通过代币地址排序和映射检查，确保同一个交易对不会被重复创建。

---

## 🔧 核心功能

### 1. `createPair` - 创建交易对

**函数签名：**
```solidity
function createPair(address tokenA, address tokenB)
    external returns (address pair)
```

**功能说明：**
1. 验证两个代币地址不同且不为零地址
2. 确保代币对的顺序（token0 < token1），避免重复创建
3. 检查该交易对是否已存在
4. 部署新的 CPAMM 合约
5. 记录交易对地址并触发事件

**完整实现：**
```solidity
function createPair(address tokenA, address tokenB)
    external returns (address pair)
{
    // 1. 验证代币地址
    require(tokenA != tokenB, "CPAMM: IDENTICAL_ADDRESSES");
    require(tokenA != address(0), "CPAMM: ZERO_ADDRESS");
    require(tokenB != address(0), "CPAMM: ZERO_ADDRESS");
    
    // 2. 排序代币地址（确保 token0 < token1）
    (address token0, address token1) = tokenA < tokenB
        ? (tokenA, tokenB)
        : (tokenB, tokenA);
    
    // 3. 检查交易对是否已存在
    require(getPair[token0][token1] == address(0), "CPAMM: PAIR_EXISTS");
    
    // 4. 部署新的 CPAMM 合约
    CPAMM newPair = new CPAMM(token0, token1);
    pair = address(newPair);
    
    // 5. 记录交易对地址
    getPair[token0][token1] = pair;
    getPair[token1][token0] = pair; // 双向映射，方便查找
    allPairs.push(pair);
    
    // 6. 触发事件
    emit PairCreated(token0, token1, pair, allPairs.length);
}
```

### 2. `getPair` - 查询交易对地址

**函数签名：**
```solidity
mapping(address => mapping(address => address)) public getPair;
```

**功能说明：**
- 这是一个公共映射，可以直接查询
- 输入两个代币地址，返回对应的交易对地址
- 如果交易对不存在，返回零地址

**使用示例：**
```solidity
address pair = factory.getPair(DAI, USDT);
if (pair != address(0)) {
    // 交易对存在
} else {
    // 交易对不存在，需要先创建
}
```

### 3. `pairFor` - 查询交易对（支持任意顺序）

**函数签名：**
```solidity
function pairFor(address tokenA, address tokenB)
    external view returns (address pair)
```

**功能说明：**
- 支持任意顺序的代币地址
- 内部会自动排序，然后查询映射
- 如果交易对不存在，返回零地址

**实现：**
```solidity
function pairFor(address tokenA, address tokenB)
    external view returns (address pair)
{
    // 排序代币地址
    (address token0, address token1) = tokenA < tokenB
        ? (tokenA, tokenB)
        : (tokenB, tokenA);
    
    // 查询映射
    pair = getPair[token0][token1];
}
```

### 4. `allPairs` 和 `allPairsLength` - 管理所有交易对

**函数签名：**
```solidity
address[] public allPairs;

function allPairsLength() external view returns (uint256) {
    return allPairs.length;
}
```

**功能说明：**
- `allPairs`：存储所有已创建的交易对地址数组
- `allPairsLength`：返回已创建的交易对总数
- 用于遍历所有交易对，或获取统计信息

---

## 🔑 关键设计原理

### 1. 代币排序（token0 < token1）

**为什么需要排序？**

在 Uniswap V2 中，每个交易对都有固定的 `token0` 和 `token1` 顺序（`token0 < token1`）。这确保了：

1. **防止重复创建**：
   - `[DAI, USDT]` 和 `[USDT, DAI]` 会被识别为同一个交易对
   - 只有 `token0 < token1` 的排序会被使用

2. **一致性**：
   - 所有合约和接口都使用相同的排序规则
   - 确保储备量 `reserve0` 和 `reserve1` 对应正确的代币

3. **映射效率**：
   - 只需要存储 `getPair[token0][token1]`
   - 同时存储双向映射 `getPair[token1][token0]` 方便反向查询

**排序实现：**
```solidity
(address token0, address token1) = tokenA < tokenB
    ? (tokenA, tokenB)
    : (tokenB, tokenA);
```

### 2. 双向映射

**为什么需要双向映射？**

```solidity
getPair[token0][token1] = pair;
getPair[token1][token0] = pair; // 双向映射
```

- 无论用户传入 `[DAI, USDT]` 还是 `[USDT, DAI]`，都能快速找到交易对
- 提高查询效率，避免每次都排序

### 3. 事件记录

**PairCreated 事件：**
```solidity
event PairCreated(
    address indexed token0,
    address indexed token1,
    address pair,
    uint256
);
```

**作用：**
- 记录所有新创建的交易对
- 方便链下索引和查询
- 提供交易对创建的历史记录

---

## 📊 数据结构

### 存储变量

```solidity
// 所有已创建的交易对地址数组
address[] public allPairs;

// 映射：tokenA => tokenB => pairAddress
mapping(address => mapping(address => address)) public getPair;
```

### 数据关系

```
Factory 合约
  │
  ├── allPairs[]: [pair1, pair2, pair3, ...]
  │
  └── getPair[token0][token1] = pairAddress
      ├── getPair[DAI][USDT] = 0x123...
      ├── getPair[USDT][DAI] = 0x123...  (双向映射)
      ├── getPair[WETH][USDT] = 0x456...
      └── ...
```

---

## 🔄 工作流程

### 创建交易对的完整流程

```
用户调用 createPair(DAI, USDT)
    ↓
1. 验证代币地址
   - DAI != USDT ✓
   - DAI != address(0) ✓
   - USDT != address(0) ✓
    ↓
2. 排序代币地址
   - token0 = DAI (地址较小)
   - token1 = USDT (地址较大)
    ↓
3. 检查是否已存在
   - getPair[DAI][USDT] == address(0)?
   - 如果已存在，回滚交易
    ↓
4. 部署新的 CPAMM 合约
   - new CPAMM(DAI, USDT)
   - 获得新合约地址
    ↓
5. 记录交易对地址
   - getPair[DAI][USDT] = pairAddress
   - getPair[USDT][DAI] = pairAddress (双向)
   - allPairs.push(pairAddress)
    ↓
6. 触发事件
   - emit PairCreated(DAI, USDT, pairAddress, allPairs.length)
    ↓
返回 pairAddress
```

---

## 💡 使用示例

### 示例 1：创建新交易对

```solidity
// 假设这是第一次创建 DAI/USDT 交易对
address factory = 0x...; // Factory 合约地址
address DAI = 0x6B...;
address USDT = 0xdA...;

// 创建交易对
address pair = CPAMMFactory(factory).createPair(DAI, USDT);

// 验证创建成功
require(pair != address(0), "Pair creation failed");

// 查询交易对（两种方式都可以）
address pair1 = CPAMMFactory(factory).getPair(DAI, USDT);
address pair2 = CPAMMFactory(factory).getPair(USDT, DAI);
assert(pair1 == pair2); // 双向映射，结果相同
```

### 示例 2：检查交易对是否存在

```solidity
function checkPairExists(address factory, address tokenA, address tokenB) 
    external view returns (bool exists, address pair) 
{
    pair = CPAMMFactory(factory).pairFor(tokenA, tokenB);
    exists = pair != address(0);
}
```

### 示例 3：获取所有交易对

```solidity
function getAllPairs(address factory) 
    external view returns (address[] memory pairs) 
{
    uint256 length = CPAMMFactory(factory).allPairsLength();
    pairs = new address[](length);
    
    for (uint256 i = 0; i < length; i++) {
        pairs[i] = CPAMMFactory(factory).allPairs(i);
    }
}
```

---

## ⚠️ 重要注意事项

### 1. 防止重复创建

- Factory 合约会检查交易对是否已存在
- 如果尝试创建已存在的交易对，交易会回滚
- 错误信息：`"CPAMM: PAIR_EXISTS"`

### 2. 代币地址验证

- 两个代币地址必须不同
- 代币地址不能为零地址
- 如果验证失败，交易会回滚

### 3. Gas 成本

- 创建新交易对需要部署新合约，Gas 成本较高
- 通常由第一个添加流动性的用户触发创建
- Router 合约会自动处理创建逻辑

### 4. 地址可预测性

**注意：** 当前实现使用 `new` 关键字部署合约，地址不可预测。

**实际 Uniswap V2 使用 CREATE2：**
- 使用 CREATE2 可以预测合约地址
- 允许在链下计算交易对地址
- 提高效率和用户体验

---

## 🔗 与其他合约的关系

### Factory ↔ Pair

```
Factory 合约
  │
  ├── createPair() → 部署新的 Pair 合约
  │
  └── getPair() → 查询 Pair 合约地址
```

### Factory ↔ Router

```
Router 合约
  │
  ├── 调用 factory.createPair() 创建新交易对
  │
  └── 调用 factory.getPair() 查询交易对地址
```

### 完整交互流程

```
用户 → Router → Factory → Pair
  │      │        │       │
  │      │        │       └── 新创建的流动性池
  │      │        └── 记录 Pair 地址
  │      └── 添加流动性到 Pair
  └── 获得 LP tokens
```

---

## 📚 相关文档

- [CPAMM.sol](./CPAMM.sol) - 交易对合约实现
- [CPAMMRouter.sol](../periphery/CPAMMRouter.sol) - 路由合约实现
- [代币交换执行流程](../periphery/SWAP_EXECUTION_FLOW.md) - 了解 Router 如何使用 Factory

---

## 🎓 总结

Factory 合约是 Uniswap V2 架构的基础，它：

1. **创建交易对**：按需部署新的流动性池合约
2. **管理注册表**：维护所有交易对的记录
3. **防止重复**：确保每个交易对只创建一次
4. **提供查询**：快速查找交易对地址

理解 Factory 合约的工作原理，对于理解整个 Uniswap V2 系统至关重要。

