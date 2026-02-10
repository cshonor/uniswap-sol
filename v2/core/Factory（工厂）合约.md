# CPAMMFactory 合约详解

本文档详细说明 Uniswap V2 中 Factory（工厂）合约的作用、功能和实现原理。

## 📋 概述

Factory 合约是 Uniswap V2 架构中的核心组件之一，负责**创建和管理所有的交易对（Pair）合约**。它充当一个"工厂"，按需创建流动性池。

### Factory 合约与 Solidity 工厂模式

**Factory 合约是 Solidity 工厂模式（Factory Pattern）的典型应用。**

#### 什么是工厂模式？

工厂模式是一种**创建型设计模式**，其核心思想是：
- **一个合约负责创建其他合约的实例**
- **集中管理合约的创建和注册**
- **提供统一的接口来创建和查询合约**

#### 为什么使用工厂模式？

1. **集中管理**
   - 所有 Pair 合约都由 Factory 统一创建和管理
   - 便于追踪和查询所有已创建的流动性池

2. **防止重复创建**
   - Factory 维护注册表，确保每个交易对只创建一次
   - 避免浪费 Gas 和存储空间

3. **标准化创建流程**
   - 统一的创建逻辑，确保所有 Pair 合约的一致性
   - 自动处理代币排序、验证等逻辑

4. **可扩展性**
   - 可以轻松添加新的创建逻辑或验证规则
   - 便于升级和维护

#### Factory 合约如何实现工厂模式？

```solidity
contract CPAMMFactory {
    // 1. 存储已创建的合约地址（注册表）
    address[] public allPairs;
    mapping(address => mapping(address => address)) public getPair;
    
    // 2. 工厂方法：创建新合约
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // 验证和准备
        require(tokenA != tokenB, "CPAMM: IDENTICAL_ADDRESSES");
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        require(getPair[token0][token1] == address(0), "CPAMM: PAIR_EXISTS");
        
        // 创建新合约实例
        CPAMM newPair = new CPAMM(token0, token1);
        pair = address(newPair);
        
        // 注册到注册表
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        // 触发事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    // 3. 查询方法：查找已创建的合约
    function getPair(address tokenA, address tokenB) external view returns (address);
}
```

#### 工厂模式的典型特征

1. **创建方法**：`createPair()` - 工厂方法，负责创建新实例
2. **注册表**：`getPair` 映射和 `allPairs` 数组 - 存储所有已创建的实例
3. **查询方法**：`getPair()`、`pairFor()` - 查找已创建的实例
4. **验证逻辑**：创建前的验证（地址检查、重复检查等）
5. **事件记录**：`PairCreated` - 记录创建历史

#### 与其他工厂模式的对比

| 特征 | Uniswap Factory | 通用工厂模式 |
|------|----------------|------------|
| 创建对象 | Pair 合约 | 任意合约 |
| 注册表 | `getPair` 映射 | 映射或数组 |
| 唯一性检查 | 代币对排序 | 可选的唯一性检查 |
| 事件记录 | `PairCreated` | 自定义事件 |

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
    // 注意：实际 Uniswap V2 使用 CREATE2 确保地址可预测
    // 这里使用简化版本，详见下方 CREATE2 实现说明
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

---

## 🎯 Factory 创建 Pair 后，Pair 到底是什么？

### Pair 合约的本质

**Factory 创建 Pair 后，Pair 是一个独立的智能合约实例，它本质上是一个"代币保险库 + 自动做市商"的组合体。**

### Pair 合约的结构

**Pair 合约包含以下核心组件：**

#### 1. **代币储备（Token Reserves）**

Pair 合约是一个**代币保险库**，存储两种代币：

```solidity
contract CPAMM {
    address public token0;      // 第一个代币地址（地址较小的）
    address public token1;     // 第二个代币地址（地址较大的）
    
    uint256 public reserve0;   // token0 的储备量
    uint256 public reserve1;   // token1 的储备量
}
```

**示例**：
- 如果创建 DAI/USDT 交易对，Pair 合约会：
  - 存储 DAI 代币（例如：1000 DAI）
  - 存储 USDT 代币（例如：2000 USDT）
  - 这两个代币就"锁"在 Pair 合约里

#### 2. **LP Token 管理（ERC20 代币）**

Pair 合约本身也是一个 **ERC20 代币合约**，铸造 LP Token：

```solidity
contract CPAMM is ERC20 {
    // 继承 ERC20 标准
    // totalSupply: LP Token 总供应量
    // balanceOf: 每个地址持有的 LP Token 数量
}
```

**LP Token 的作用**：
- 代表流动性提供者在池子中的份额
- 可以转账、交易
- 移除流动性时需要销毁

#### 3. **恒定乘积公式（CPAMM 算法）**

Pair 合约实现了 **`x * y = k`** 恒定乘积公式：

```solidity
// 交换时必须满足：
// (reserve0 + amountIn) * (reserve1 - amountOut) = reserve0 * reserve1
```

**这个公式的作用**：
- 自动定价：根据储备量自动计算交换价格
- 无需外部价格预言机
- 保证池子始终有流动性

#### 4. **核心功能函数**

Pair 合约提供三个核心功能：

```solidity
contract CPAMM {
    // 1. 添加流动性：存入代币，获得 LP Token
    function addLiquidity(uint256 amount0, uint256 amount1) 
        external returns (uint256 liquidity);
    
    // 2. 移除流动性：销毁 LP Token，取回代币
    function removeLiquidity(uint256 liquidity) 
        external returns (uint256 amount0, uint256 amount1);
    
    // 3. 代币交换：用一种代币换另一种代币
    function swap(address tokenIn, uint256 amountIn) 
        external returns (uint256 amountOut);
}
```

### Pair 合约的完整结构图

```
┌─────────────────────────────────────┐
│         Pair 合约 (CPAMM)            │
├─────────────────────────────────────┤
│                                       │
│  📦 代币储备（保险库）                 │
│  ├── token0: DAI                     │
│  │   └── reserve0: 1000 DAI          │
│  └── token1: USDT                    │
│      └── reserve1: 2000 USDT         │
│                                       │
│  🪙 LP Token（ERC20）                 │
│  ├── totalSupply: 1414 LP            │
│  └── balanceOf[user]: 100 LP          │
│                                       │
│  🧮 恒定乘积公式                       │
│  └── k = reserve0 × reserve1         │
│      = 1000 × 2000 = 2,000,000       │
│                                       │
│  ⚙️ 核心功能                          │
│  ├── addLiquidity()                   │
│  ├── removeLiquidity()                │
│  └── swap()                           │
│                                       │
└─────────────────────────────────────┘
```

### Pair 合约的生命周期

**1. 创建阶段（Factory 创建）**
```
Factory.createPair(DAI, USDT)
  ↓
部署新的 CPAMM 合约
  ↓
Pair 合约地址：0x1234...
  ↓
初始状态：
- reserve0 = 0
- reserve1 = 0
- totalSupply = 0
```

**2. 首次添加流动性**
```
用户调用 Pair.addLiquidity(1000 DAI, 2000 USDT)
  ↓
Pair 合约状态：
- reserve0 = 1000 DAI
- reserve1 = 2000 USDT
- totalSupply = 1414 LP Token
- 价格 = 2000 / 1000 = 2 USDT/DAI
```

**3. 运行阶段（持续交易和添加流动性）**
```
用户不断：
- 添加流动性 → reserve0 和 reserve1 增加
- 移除流动性 → reserve0 和 reserve1 减少
- 交换代币 → reserve0 和 reserve1 变化，但 k 保持不变
```

**4. 销毁阶段（理论上）**
```
如果所有流动性被移除：
- totalSupply = 0
- reserve0 = 0
- reserve1 = 0
- Pair 合约仍然存在，但为空池
```

### Pair 合约的关键特性

#### 1. **独立性**
- 每个交易对都有自己独立的 Pair 合约
- DAI/USDT 的 Pair 和 WETH/USDT 的 Pair 是完全独立的
- 互不影响

#### 2. **不可升级性**
- Pair 合约一旦部署，代码不可更改
- 这是 Uniswap V2 安全模型的核心
- 用户信任的是不可变的代码

#### 3. **自包含性**
- Pair 合约包含所有必要的逻辑
- 不依赖外部合约（除了 Factory 创建它）
- 可以独立运行

#### 4. **状态存储**
- Pair 合约存储了池子的完整状态
- 包括储备量、LP Token 余额等
- 所有状态都在链上，可验证

### Pair 合约与其他组件的关系

```
用户
  ↓
Router（路由合约）
  ↓
Factory（工厂合约）→ 创建 → Pair（交易对合约）
  ↓
Pair 合约：
  ├── 存储代币储备
  ├── 管理 LP Token
  ├── 执行交换
  └── 管理流动性
```

### 实际例子

**场景：创建 DAI/USDT 交易对**

1. **Factory 创建 Pair**：
   ```solidity
   address pair = factory.createPair(DAI, USDT);
   // pair = 0x1234... (新部署的合约地址)
   ```

2. **Pair 合约的内容**：
   ```solidity
   // Pair 合约内部状态
   token0 = DAI;        // 地址较小的代币
   token1 = USDT;       // 地址较大的代币
   reserve0 = 0;        // 初始为空
   reserve1 = 0;        // 初始为空
   totalSupply = 0;     // 还没有 LP Token
   ```

3. **用户添加流动性后**：
   ```solidity
   // Pair 合约内部状态
   reserve0 = 1000;     // 1000 DAI
   reserve1 = 2000;     // 2000 USDT
   totalSupply = 1414;  // 1414 LP Token
   ```

4. **Pair 合约现在是一个"活跃的流动性池"**：
   - ✅ 持有 1000 DAI 和 2000 USDT
   - ✅ 可以执行 DAI ↔ USDT 的交换
   - ✅ 可以继续添加或移除流动性
   - ✅ 用户持有 LP Token 代表份额

### 总结

**Factory 创建 Pair 后，Pair 是：**

1. ✅ **一个独立的智能合约**：部署在链上，有独立的地址
2. ✅ **一个代币保险库**：存储两种代币的储备量
3. ✅ **一个 ERC20 代币合约**：铸造和管理 LP Token
4. ✅ **一个自动做市商**：实现恒定乘积公式，自动定价
5. ✅ **一个流动性池**：用户可以添加/移除流动性，执行交换

**简单理解**：
- Factory = 工厂，负责"生产" Pair 合约
- Pair = 产品，是一个"代币池子"，管理两种代币的交换和流动性

---

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

**详细解释：**

这一步排序的目的是**统一顺序**，无论用户传入的是 `(tokenA, tokenB)` 还是 `(tokenB, tokenA)`，都能得到一致的 `(token0, token1)` 顺序。

**工作原理：**

1. **比较地址大小**：
   - 在 Solidity 中，`address` 类型可以按字节序比较大小
   - `tokenA < tokenB` 表示 tokenA 的地址值小于 tokenB

2. **统一为 token0 < token1**：
   - 如果 `tokenA < tokenB`：`token0 = tokenA`，`token1 = tokenB`
   - 如果 `tokenA > tokenB`：`token0 = tokenB`，`token1 = tokenA`
   - **结果**：无论输入顺序如何，`token0` 总是地址较小的，`token1` 总是地址较大的

**实际例子：**

假设：
- DAI 地址：`0x6B175474E89094C44Da98b954EedeAC495271d0F`
- USDT 地址：`0xdAC17F958D2ee523a2206206994597C13D831ec7`

**情况 1：用户传入 `(DAI, USDT)`**
```solidity
tokenA = DAI
tokenB = USDT
// DAI < USDT (按地址比较)
// 结果：token0 = DAI, token1 = USDT
```

**情况 2：用户传入 `(USDT, DAI)`**
```solidity
tokenA = USDT
tokenB = DAI
// USDT > DAI (按地址比较)
// 结果：token0 = DAI, token1 = USDT
```

**关键理解：**

- ✅ **无论用户传入 ab 还是 ba，排序后都是 token0 < token1**
- ✅ **这确保了 `[DAI, USDT]` 和 `[USDT, DAI]` 被识别为同一个交易对**
- ✅ **防止重复创建：`getPair[token0][token1]` 总是唯一的**
- ✅ **一致性：所有地方都使用相同的排序规则**

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

### 4. 工厂模式的应用

**Factory 合约是 Solidity 工厂模式的经典实现：**

#### 工厂模式的核心要素

1. **工厂合约（Factory Contract）**
   - `CPAMMFactory` 就是工厂合约
   - 负责创建和管理产品合约（Pair 合约）

2. **产品合约（Product Contract）**
   - `CPAMM` 就是产品合约
   - 由工厂合约创建的具体实例

3. **创建方法（Factory Method）**
   - `createPair()` 就是工厂方法
   - 封装了创建逻辑和验证流程

4. **注册表（Registry）**
   - `getPair` 映射和 `allPairs` 数组
   - 存储所有已创建的产品实例

#### 工厂模式的优势

```
传统方式（无工厂）：
用户 → 直接部署 Pair 合约
问题：
- 每个用户都需要部署，Gas 成本高
- 无法统一管理
- 可能创建重复的交易对

工厂模式：
用户 → Factory → 创建/查询 Pair 合约
优势：
- 集中管理，避免重复
- 统一的创建逻辑
- 便于查询和追踪
```

#### 实际应用场景

1. **按需创建**
   - 只有当用户需要某个交易对时，才创建对应的 Pair 合约
   - 节省 Gas 和存储空间

2. **统一管理**
   - 所有 Pair 合约都通过 Factory 创建
   - 便于统计和查询所有流动性池

3. **标准化**
   - 确保所有 Pair 合约使用相同的创建逻辑
   - 保证一致性和安全性

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

### 4. CREATE2 实现详解

**注意：** 当前简化实现使用 `new` 关键字部署合约，地址不可预测。

**实际 Uniswap V2 使用 CREATE2：**
- 使用 CREATE2 可以预测合约地址
- 允许在链下计算交易对地址
- 提高效率和用户体验

#### CREATE2 的工作原理

CREATE2 是 EVM 的一个操作码，允许在创建合约前预测合约地址。地址计算公式为：

```
address = keccak256(0xff ++ deployerAddress ++ salt ++ keccak256(bytecode))[12:]
```

其中：
- `deployerAddress`：部署者地址（Factory 合约地址）
- `salt`：盐值（由 token0 和 token1 计算得出）
- `bytecode`：要部署的合约字节码

#### Uniswap V2 的实际实现

**完整的 `createPair` 函数（使用 CREATE2）：**

```solidity
function createPair(address tokenA, address tokenB)
    external returns (address pair)
{
    require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
    
    // 1. 排序代币地址
    (address token0, address token1) = tokenA < tokenB 
        ? (tokenA, tokenB) 
        : (tokenB, tokenA);
    
    require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
    require(getPair[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS");
    
    // 2. 获取 Pair 合约的创建字节码
    bytes memory bytecode = type(UniswapV2Pair).creationCode;
    
    // 3. 计算 salt（使用 token0 和 token1）
    bytes32 salt = keccak256(abi.encodePacked(token0, token1));
    
    // 4. 使用 CREATE2 部署合约
    assembly {
        pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }
    
    // 5. 初始化 Pair 合约
    IUniswapV2Pair(pair).initialize(token0, token1);
    
    // 6. 记录交易对地址
    getPair[token0][token1] = pair;
    getPair[token1][token0] = pair; // 双向映射
    allPairs.push(pair);
    
    emit PairCreated(token0, token1, pair, allPairs.length);
}
```

#### 关键代码解析

**1. 获取创建字节码：**
```solidity
bytes memory bytecode = type(UniswapV2Pair).creationCode;
```
- `type(UniswapV2Pair).creationCode` 返回 Pair 合约的创建字节码
- 这是部署合约所需的完整字节码

**2. 计算 salt：**
```solidity
bytes32 salt = keccak256(abi.encodePacked(token0, token1));
```
- `salt` 是 CREATE2 的关键参数
- 使用 `token0` 和 `token1` 的地址计算 salt
- 确保相同代币对总是生成相同的 salt，从而生成相同的合约地址

**3. CREATE2 汇编调用：**
```solidity
assembly {
    pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
}
```

**参数说明：**
- `0`：发送的 ETH 数量（0 wei）
- `add(bytecode, 32)`：字节码数据的起始位置
  - Solidity 的 `bytes` 类型前 32 字节存储长度
  - `add(bytecode, 32)` 跳过长度字段，指向实际字节码
- `mload(bytecode)`：字节码的长度
  - `mload(bytecode)` 读取前 32 字节，即字节码长度
- `salt`：计算出的盐值

**4. 初始化 Pair 合约：**
```solidity
IUniswapV2Pair(pair).initialize(token0, token1);
```
- CREATE2 创建的合约需要手动初始化
- `initialize` 函数设置 `token0` 和 `token1` 的值
- 这是必要的，因为构造函数参数在 CREATE2 中无法直接传递

#### CREATE2 的优势

1. **地址可预测性**：
   - 可以在链下预先计算 Pair 合约地址
   - 不需要实际部署就能知道地址

2. **链下计算地址**：
   ```solidity
   // 可以在链下计算 Pair 地址
   function pairFor(address factory, address tokenA, address tokenB) 
       internal pure returns (address pair) 
   {
       (address token0, address token1) = sortTokens(tokenA, tokenB);
       bytes32 salt = keccak256(abi.encodePacked(token0, token1));
       bytes32 bytecodeHash = keccak256(type(UniswapV2Pair).creationCode);
       pair = address(uint160(uint256(keccak256(
           abi.encodePacked(
               hex'ff',
               factory,
               salt,
               bytecodeHash
           )
       ))));
   }
   ```

3. **Gas 优化**：
   - 可以预先计算地址，避免重复查询
   - Router 合约可以使用 `pairFor` 函数直接计算地址，而不需要调用 Factory

4. **唯一性保证**：
   - 相同的 `salt` 和 `bytecode` 总是生成相同的地址
   - 如果地址已被占用，CREATE2 会失败，防止意外覆盖

#### CREATE2 vs 标准部署

| 特性 | 标准部署 (`new`) | CREATE2 |
|------|----------------|--------|
| 地址可预测 | ❌ 否 | ✅ 是 |
| 链下计算 | ❌ 否 | ✅ 是 |
| Gas 成本 | 较低 | 稍高 |
| 初始化方式 | 构造函数 | `initialize` 函数 |
| 唯一性检查 | 自动 | 需要手动检查 |

#### 为什么需要 initialize 函数？

CREATE2 创建的合约无法在创建时传递构造函数参数，因此需要单独的 `initialize` 函数：

```solidity
// Pair 合约中的 initialize 函数
function initialize(address _token0, address _token1) external {
    require(msg.sender == factory, "UniswapV2: FORBIDDEN");
    token0 = _token0;
    token1 = _token1;
}
```

**安全措施**：
- 只能由 Factory 合约调用（`msg.sender == factory`）
- 只能初始化一次（通过检查 `token0 == address(0)`）

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

