# 代币交换执行流程详解

本文档详细说明 Uniswap V2 中代币交换的完整执行流程，包括用户、路由合约和流动性池之间的交互。

## 📋 概述

当用户通过路由合约执行代币交换时，整个过程涉及 4 个关键步骤：
1. 用户调用路由合约的交换函数
2. 路由合约从用户转移输入代币到流动性池（transferFrom）
3. 流动性池执行交换，更新储备量（swap）
4. 流动性池将输出代币转回用户（transfer）

---

## 🔄 完整的交换流程（以 DAI/USDT 交换为例）

```
用户 (User)
  │
  │ ① 调用 swapExactTokensForTokens 或 swapTokensForExactTokens
  ↓
Router02.sol (路由合约)
  │
  │ ② transferFrom (从用户转移输入代币到池子)
  ↓
DAI/USDT Pair (流动性池合约)
  │
  │ ③ Swap (执行实际的代币交换，更新储备量)
  │
  │ ④ transfer (将输出代币转回用户)
  ↓
用户收到输出代币
```

---

## 详细步骤说明

### 步骤 ①：用户调用路由合约

用户调用路由合约的交换函数：
- `swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)`
- 或 `swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline)`

**路由合约此时执行：**
1. 验证 `deadline` 是否过期
2. 验证 `path` 是否有效（至少包含 2 个代币地址）
3. 计算输出/输入数量（使用 `_getAmountsOut` 或 `_getAmountsIn`）
4. 检查滑点保护（`amountOutMin` 或 `amountInMax`）

**代码示例：**
```solidity
// 用户调用
router.swapExactTokensForTokens(
    100 * 10**18,      // amountIn: 100 DAI
    95 * 10**6,        // amountOutMin: 至少 95 USDT
    [DAI, USDT],       // path
    userAddress,       // to
    deadline          // deadline
);
```

---

### 步骤 ②：代币转移（transferFrom）

路由合约使用 `transferFrom` 将输入代币从用户转移到流动性池：

```solidity
// 路由合约内部执行
IERC20(path[0]).transferFrom(
    msg.sender,                    // 从用户账户
    _pairFor(path[0], path[1]),   // 转移到流动性池
    amounts[0]                     // 转移的数量
);
```

**重要说明：**
- 用户需要先 `approve` 路由合约，允许它转移代币
- 路由合约本身不持有代币，只是作为中间层转移代币
- 如果用户没有提前授权，交易会失败

**授权示例：**
```solidity
// 用户需要先执行（通常在 DApp 前端自动处理）
IERC20(DAI).approve(routerAddress, 100 * 10**18);
```

---

### 步骤 ③：执行交换（Swap）

路由合约调用流动性池（Pair）合约的 `swap` 方法：

```solidity
// 路由合约内部执行
_swap(amounts, path, to);
// 最终调用 Pair 合约的 swap 函数
```

**Pair 合约执行：**
1. 验证储备量
2. 根据恒定乘积公式 `x * y = k` 计算输出数量
3. 更新储备量（增加输入代币，减少输出代币）

**恒定乘积公式：**
```
(x + Δx) * (y - Δy) = x * y = k
```

其中：
- `x`, `y`: 当前储备量
- `Δx`: 输入的代币数量
- `Δy`: 输出的代币数量
- `k`: 恒定乘积

**计算输出数量：**
```
Δy = (y * Δx) / (x + Δx)
```

---

### 步骤 ④：输出代币转移（transfer）

Pair 合约将计算好的输出代币转移到用户指定的地址：

```solidity
// Pair 合约内部执行
IERC20(tokenOut).transfer(
    to,           // 接收地址（通常是用户）
    amountOut     // 输出的代币数量
);
```

**重要说明：**
- 输出代币直接从流动性池转移到用户
- 不需要用户再次授权，因为这是池子向用户转账
- 如果 `to` 地址不是用户，代币会转到指定的地址（例如，多跳兑换中的中间地址）

---

## 关键要点

### 1. 三层架构

- **用户层**：发起交易，提供输入代币，接收输出代币
- **路由层**：处理逻辑、检查、路径规划，不持有资金
- **池子层**：执行实际的代币交换，持有所有流动性

### 2. 代币流向

- **输入代币**：用户 → 路由合约（transferFrom）→ 流动性池
- **输出代币**：流动性池 → 用户（transfer，直接转移）

### 3. 完整流程总结

1. ① 用户调用路由合约函数
2. ② 路由合约从用户转移输入代币到池子（transferFrom）
3. ③ 池子执行交换，更新储备量（swap）
4. ④ 池子将输出代币转给用户（transfer）

### 4. 路由合约的作用

- **不持有资金**：路由合约本身不直接持有资金，只是作为中间层
- **调度和检查**：处理代币授权、路径选择、滑点检查、多池兑换等复杂逻辑
- **用户友好接口**：封装复杂的底层操作，提供简单的函数调用
- **所有资金最终都在流动性池中**：路由合约只是资金的"搬运工"

---

## 多跳兑换流程

当 `path` 包含多个代币时（例如 `[USDC, WETH, DAI]`），路由合约会依次在多个池子中执行交换：

```
用户
  ↓
Router02.sol
  ↓ transferFrom (USDC)
USDC/WETH Pair
  ↓ swap (USDC → WETH)
  ↓ transfer (WETH)
Router02.sol
  ↓ transferFrom (WETH)
WETH/DAI Pair
  ↓ swap (WETH → DAI)
  ↓ transfer (DAI)
用户收到 DAI
```

**关键点：**
- 中间代币（如 WETH）会先转到路由合约，再转到下一个池子
- 路由合约作为中间代币的临时持有者，但不长期持有
- 整个过程在一个交易中完成，原子性保证

---

## 安全考虑

### 1. 滑点保护

- `swapExactTokensForTokens` 使用 `amountOutMin` 防止输出太少
- `swapTokensForExactTokens` 使用 `amountInMax` 防止输入太多
- 如果实际结果不满足条件，整个交易会回滚

### 2. 截止时间（Deadline）

- 防止交易在价格剧烈波动时执行
- 如果交易在 `deadline` 之后才被打包，交易会失败

### 3. 重入攻击防护

- Pair 合约使用 `_safeTransfer` 防止重入攻击
- 先更新储备量，再转移代币（Checks-Effects-Interactions 模式）

---

## 相关文档

- [Swap 函数对比](./SWAP_FUNCTIONS_COMPARISON.md) - 了解 `swapExactTokensForTokens` 和 `swapTokensForExactTokens` 的区别
- [CPAMMRouter.sol](./CPAMMRouter.sol) - 路由合约的完整实现

