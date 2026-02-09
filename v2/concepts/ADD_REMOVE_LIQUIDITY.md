# Uniswap V2 添加/移除流动性详解

本文档详细说明 Uniswap V2 中添加和移除流动性的机制、计算方式和注意事项。

## 📋 概述

流动性是 Uniswap V2 的核心，用户可以通过添加流动性成为流动性提供者（LP），获得 LP tokens 和手续费收益。

---

## ➕ 添加流动性

### 核心原则

**添加流动性的两个重要原则：**

1. **初始流动性决定代币价格**
   - 首次添加流动性时，两种代币的数量比例决定了初始价格
   - 价格 = `amount1 / amount0`

2. **添加流动性不能影响价格**
   - 后续添加流动性时，必须按照当前池中的代币比例添加
   - 保持比例：`(x + dx) / (y + dy) = x / y`

### 首次添加流动性

**公式：**
```solidity
liquidity = sqrt(amount0 * amount1)
```

**示例：**
- 添加：1000 DAI + 2000 USDT
- 初始价格：2000 / 1000 = 2 USDT/DAI
- LP tokens：`sqrt(1000 * 2000) = 1414`

**特点：**
- 初始流动性决定了代币价格
- LP tokens 数量 = 两种代币数量的几何平均数

### 后续添加流动性

**计算方式：**
```solidity
liquidity0 = (amount0 * totalSupply) / reserve0
liquidity1 = (amount1 * totalSupply) / reserve1
liquidity = min(liquidity0, liquidity1)
```

**示例：**
- 当前池子：1000 DAI + 2000 USDT
- 总 LP tokens：1414
- 添加：500 DAI + 1000 USDT（按比例）

**计算：**
```
liquidity0 = (500 * 1414) / 1000 = 707
liquidity1 = (1000 * 1414) / 2000 = 707
liquidity = min(707, 707) = 707
```

**结果：**
- 新池子：1500 DAI + 3000 USDT
- 新 LP tokens：1414 + 707 = 2121
- 价格保持不变：3000 / 1500 = 2 USDT/DAI

### 比例不匹配的处理

如果添加的代币比例不匹配，Router 合约会自动调整：

```solidity
// Router 合约中的处理
uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
if (amountBOptimal <= amountBDesired) {
    // 使用 amountADesired 和 amountBOptimal
    (amountA, amountB) = (amountADesired, amountBOptimal);
} else {
    // 使用 amountAOptimal 和 amountBDesired
    uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
    (amountA, amountB) = (amountAOptimal, amountBDesired);
}
```

**示例：**
- 期望添加：1000 DAI + 2500 USDT（比例不匹配）
- 实际添加：1000 DAI + 2000 USDT（自动调整）
- 多余的 500 USDT 会退回给用户

---

## ➖ 移除流动性

### 核心原则

**移除流动性不能影响价格**

移除时按照 LP tokens 的比例移除，确保价格不变。

### 计算公式

```solidity
amount0 = (liquidity * balance0) / totalSupply
amount1 = (liquidity * balance1) / totalSupply
```

**示例：**
- 当前池子：1500 DAI + 3000 USDT
- 总 LP tokens：2121
- 移除：707 LP tokens（33.3%）

**计算：**
```
amount0 = (707 * 1500) / 2121 = 500 DAI
amount1 = (707 * 3000) / 2121 = 1000 USDT
```

**结果：**
- 新池子：1000 DAI + 2000 USDT
- 新 LP tokens：2121 - 707 = 1414
- 价格保持不变：2000 / 1000 = 2 USDT/DAI

### 获得手续费收益

移除流动性时，会获得累积的手续费：

**示例：**
- 初始添加：1000 DAI + 2000 USDT，获得 1414 LP tokens
- 期间手续费累积：池子变为 1003 DAI + 2006 USDT
- 移除 1414 LP tokens：
  - 获得：1003 DAI + 2006 USDT
  - 手续费收益：3 DAI + 6 USDT

---

## 🔄 完整流程

### 添加流动性流程

```
用户调用 Router.addLiquidity()
    ↓
1. Router 检查池子是否存在
   - 不存在 → 调用 Factory.createPair()
    ↓
2. Router 获取当前储备量
    ↓
3. Router 计算最优数量（保持比例）
    ↓
4. Router 转移代币到 Pair 合约
    ↓
5. Pair 合约计算 LP tokens
    ↓
6. Pair 合约铸造 LP tokens 给用户
    ↓
7. Pair 合约更新储备量
```

### 移除流动性流程

```
用户调用 Router.removeLiquidity()
    ↓
1. Router 验证 LP tokens 数量
    ↓
2. Router 转移 LP tokens 到 Pair 合约
    ↓
3. Pair 合约计算返回的代币数量
    ↓
4. Pair 合约销毁 LP tokens
    ↓
5. Pair 合约转移代币给用户
    ↓
6. Pair 合约更新储备量
```

---

## 💡 使用示例

### 示例 1：首次添加流动性

```solidity
address router = 0x...;
address DAI = 0x6B...;
address USDT = 0xdA...;

// 授权
IERC20(DAI).approve(router, 1000 * 10**18);
IERC20(USDT).approve(router, 2000 * 10**6);

// 添加流动性
(uint256 amountA, uint256 amountB, uint256 liquidity) = 
    CPAMMRouter(router).addLiquidity(
        DAI,                    // tokenA
        USDT,                   // tokenB
        1000 * 10**18,          // amountADesired
        2000 * 10**6,           // amountBDesired
        950 * 10**18,           // amountAMin（滑点保护）
        1900 * 10**6,           // amountBMin（滑点保护）
        msg.sender,             // to
        deadline                // deadline
    );

// liquidity ≈ 1414 LP tokens
```

### 示例 2：后续添加流动性

```solidity
// 当前池子：1000 DAI + 2000 USDT
// 添加：500 DAI + 1000 USDT

(uint256 amountA, uint256 amountB, uint256 liquidity) = 
    CPAMMRouter(router).addLiquidity(
        DAI,
        USDT,
        500 * 10**18,           // amountADesired
        1000 * 10**6,           // amountBDesired
        450 * 10**18,           // amountAMin
        900 * 10**6,            // amountBMin
        msg.sender,
        deadline
    );

// liquidity ≈ 707 LP tokens
```

### 示例 3：移除流动性

```solidity
// 移除 707 LP tokens

(uint256 amountA, uint256 amountB) = 
    CPAMMRouter(router).removeLiquidity(
        DAI,
        USDT,
        707 * 10**18,           // liquidity
        450 * 10**18,           // amountAMin
        900 * 10**6,            // amountBMin
        msg.sender,
        deadline
    );

// 获得：约 500 DAI + 1000 USDT（包含手续费收益）
```

---

## ⚠️ 重要注意事项

### 1. 价格不变性

- **添加流动性**：必须按比例添加，否则多余的代币会被退回
- **移除流动性**：按比例移除，确保价格不变

### 2. 滑点保护

- `amountAMin` 和 `amountBMin` 用于滑点保护
- 如果实际数量少于最小值，交易会回滚

### 3. 首次添加的重要性

- 首次添加流动性决定了初始价格
- 如果价格设置不合理，可能被套利

### 4. 无常损失

- LP 需要承担无常损失风险
- 手续费收益需要覆盖无常损失才能盈利

### 5. Gas 成本

- 添加/移除流动性需要 Gas
- 频繁操作可能不划算

---

## 📊 流动性代币（LP Tokens）

### LP Tokens 的作用

1. **份额凭证**：代表在池子中的份额
2. **可转让**：可以转账给其他地址
3. **收益凭证**：移除时获得对应的代币和手续费

### LP Tokens 计算

**首次添加：**
```
LP tokens = sqrt(amount0 * amount1)
```

**后续添加：**
```
LP tokens = min(
    (amount0 * totalSupply) / reserve0,
    (amount1 * totalSupply) / reserve1
)
```

**移除时：**
```
amount0 = (liquidity * balance0) / totalSupply
amount1 = (liquidity * balance1) / totalSupply
```

---

## 🔗 相关文档

- [Pair 合约](../core/PAIR_CONTRACT.md) - 了解底层实现
- [手续费机制](./FEE_MECHANISM.md) - 了解手续费收益
- [无常损失](./IMPERMANENT_LOSS.md) - 了解 LP 的风险

---

## 🎓 总结

添加和移除流动性是 Uniswap V2 的核心功能：

1. **添加流动性**：
   - 首次添加决定价格
   - 后续添加必须按比例
   - 获得 LP tokens 作为凭证

2. **移除流动性**：
   - 按比例移除，价格不变
   - 获得代币和累积的手续费
   - 销毁 LP tokens

3. **价格不变性**：
   - 添加/移除流动性都不能影响价格
   - 这是 AMM 的核心原则

