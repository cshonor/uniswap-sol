# CPAMM (Pair) 合约详解

本文档详细说明 Uniswap V2 中 Pair（交易对）合约的作用、功能和实现原理。Pair 合约是每个流动性池的核心，实现了恒定乘积自动做市商（CPAMM）算法。

## 📋 概述

CPAMM 合约是 Uniswap V2 架构中的核心组件，每个交易对（如 DAI/USDT）都有一个独立的 CPAMM 合约实例。它负责：

1. **管理流动性池**：存储两种代币的储备量
2. **执行代币交换**：根据恒定乘积公式进行代币兑换
3. **管理流动性**：添加和移除流动性，铸造和销毁 LP tokens

---

## 🎯 Pair 合约的作用

### 1. 流动性池管理

Pair 合约是实际的流动性池，存储了两种代币的储备量：
- `reserve0`：token0 的储备量
- `reserve1`：token1 的储备量

### 2. 代币交换

Pair 合约根据恒定乘积公式 `x * y = k` 执行代币交换，自动定价。

### 3. 流动性代币（LP Tokens）

Pair 合约铸造和销毁流动性代币，代表流动性提供者在池中的份额。

---

## 🔧 核心功能

### 1. `addLiquidity` - 添加流动性

**函数签名：**
```solidity
function addLiquidity(uint256 amount0, uint256 amount1) 
    external returns (uint256 liquidity)
```

**功能说明：**
- 用户存入两种代币到池子
- 铸造流动性代币（LP tokens）给用户
- 更新储备量

**完整实现：**
```solidity
function addLiquidity(uint256 amount0, uint256 amount1) 
    external returns (uint256 liquidity) 
{
    // 1. 将代币转入合约
    token0.transferFrom(msg.sender, address(this), amount0);
    token1.transferFrom(msg.sender, address(this), amount1);
    
    uint256 _reserve0 = reserve0;
    uint256 _reserve1 = reserve1;
    
    if (_reserve0 == 0 && _reserve1 == 0) {
        // 2. 首次添加流动性
        liquidity = _sqrt(amount0 * amount1);
    } else {
        // 3. 后续添加：按比例计算，取较小值
        uint256 liquidity0 = (amount0 * totalSupply) / _reserve0;
        uint256 liquidity1 = (amount1 * totalSupply) / _reserve1;
        liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    }
    
    require(liquidity > 0, "Insufficient liquidity");
    _mint(msg.sender, liquidity);  // 铸造 LP tokens
    _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    
    emit Mint(msg.sender, amount0, amount1);
}
```

**关键点：**

1. **首次添加流动性**：
   - 使用公式：`liquidity = sqrt(amount0 * amount1)`
   - 初始流动性决定了代币价格

2. **后续添加流动性**：
   - 必须按照当前池中的比例添加
   - 计算两种代币对应的流动性，取较小值
   - 确保价格不变：`(x + dx) / (y + dy) = x / y`

3. **价格不变性**：
   - 添加流动性不能影响价格
   - 如果比例不匹配，多余的代币会被退回（在 Router 中处理）

### 2. `removeLiquidity` - 移除流动性

**函数签名：**
```solidity
function removeLiquidity(uint256 liquidity) 
    external returns (uint256 amount0, uint256 amount1)
```

**功能说明：**
- 用户销毁 LP tokens
- 按比例取回两种代币
- 更新储备量

**完整实现：**
```solidity
function removeLiquidity(uint256 liquidity) 
    external returns (uint256 amount0, uint256 amount1) 
{
    uint256 _totalSupply = totalSupply;
    require(_totalSupply > 0, "No liquidity");
    
    uint256 balance0 = token0.balanceOf(address(this));
    uint256 balance1 = token1.balanceOf(address(this));
    
    // 按比例计算返回的代币数量
    amount0 = (liquidity * balance0) / _totalSupply;
    amount1 = (liquidity * balance1) / _totalSupply;
    
    require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");
    
    _burn(msg.sender, liquidity);  // 销毁 LP tokens
    
    token0.transfer(msg.sender, amount0);
    token1.transfer(msg.sender, amount1);
    
    _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    
    emit Burn(msg.sender, amount0, amount1, msg.sender);
}
```

**关键点：**

1. **按比例移除**：
   - `amount0 = (liquidity / totalSupply) * balance0`
   - `amount1 = (liquidity / totalSupply) * balance1`
   - 确保移除后价格不变

2. **价格不变性**：
   - 移除流动性不能影响价格
   - 移除的比例与 LP tokens 的比例相同

### 3. `swap` - 代币交换

**函数签名：**
```solidity
function swap(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
) external returns (uint256 amountOut)
```

**功能说明：**
- 根据恒定乘积公式执行代币交换
- 提供滑点保护
- 更新储备量

**完整实现：**
```solidity
function swap(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
) external returns (uint256 amountOut) {
    // 1. 验证输入代币
    require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");
    require(to != address(0) && to != address(this), "Invalid recipient");
    
    // 2. 确定输入和输出代币
    bool isToken0 = tokenIn == address(token0);
    (IERC20 tokenIn_, IERC20 tokenOut_, uint256 reserveIn, uint256 reserveOut) = isToken0
        ? (token0, token1, reserve0, reserve1)
        : (token1, token0, reserve1, reserve0);
    
    // 3. 将输入代币转入合约
    tokenIn_.transferFrom(msg.sender, address(this), amountIn);
    
    // 4. 计算输出数量
    amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
    require(amountOut >= amountOutMin, "Insufficient output amount");
    
    // 5. 转出代币
    tokenOut_.transfer(to, amountOut);
    
    // 6. 更新储备量
    _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    
    emit Swap(msg.sender, ...);
}
```

**关键点：**

1. **恒定乘积公式**：
   - `(x + Δx) * (y - Δy) = x * y = k`
   - 确保交换后乘积保持不变

2. **滑点保护**：
   - `amountOutMin` 参数防止滑点过大
   - 如果实际输出少于 `amountOutMin`，交易回滚

3. **储备量更新**：
   - 交换后，储备量会发生变化
   - `reserveIn` 增加，`reserveOut` 减少

### 4. `getAmountOut` - 计算输出数量

**函数签名：**
```solidity
function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
) public pure returns (uint256 amountOut)
```

**功能说明：**
- 根据恒定乘积公式计算输出数量
- 纯函数，不修改状态

**实现：**
```solidity
function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
) public pure returns (uint256 amountOut) {
    require(amountIn > 0, "Insufficient input amount");
    require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
    
    // 恒定乘积公式: (x + Δx) * (y - Δy) = x * y
    // 推导: Δy = (y * Δx) / (x + Δx)
    uint256 numerator = amountIn * reserveOut;
    uint256 denominator = reserveIn + amountIn;
    amountOut = numerator / denominator;
}
```

**公式推导：**

```
已知：x * y = k（恒定乘积）
交换后：(x + Δx) * (y - Δy) = k

展开：x * y + y * Δx - x * Δy - Δx * Δy = x * y
简化：y * Δx = x * Δy + Δx * Δy
      y * Δx = Δy * (x + Δx)

因此：Δy = (y * Δx) / (x + Δx)
```

### 5. `getReserves` - 获取储备量

**函数签名：**
```solidity
function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1)
```

**功能说明：**
- 返回当前池中的储备量
- 用于查询和计算

---

## 📊 数据结构

### 存储变量

```solidity
// 代币地址（immutable，创建后不可更改）
IERC20 public immutable token0;  // 地址较小的代币
IERC20 public immutable token1;   // 地址较大的代币

// 储备量
uint256 public reserve0;  // token0 的储备量
uint256 public reserve1;  // token1 的储备量

// 流动性代币（LP tokens）
uint256 public totalSupply;                    // 总供应量
mapping(address => uint256) public balanceOf;  // 每个地址的余额
```

### 数据关系

```
CPAMM 合约
  │
  ├── token0: DAI (地址较小)
  ├── token1: USDT (地址较大)
  │
  ├── reserve0: 1000 DAI
  ├── reserve1: 2000 USDT
  │
  └── LP Tokens
      ├── totalSupply: 1414 (sqrt(1000 * 2000))
      └── balanceOf[user]: 100
```

---

## 📢 事件

### 1. `Mint` - 添加流动性事件

```solidity
event Mint(address indexed sender, uint256 amount0, uint256 amount1);
```

**触发时机**：用户添加流动性时

### 2. `Burn` - 移除流动性事件

```solidity
event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
```

**触发时机**：用户移除流动性时

### 3. `Swap` - 交换事件

```solidity
event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
);
```

**触发时机**：执行代币交换时

### 4. `Sync` - 同步储备量事件

```solidity
event Sync(uint256 reserve0, uint256 reserve1);
```

**触发时机**：储备量更新时（每次添加/移除流动性或交换后）

---

## 🔑 关键设计原理

### 1. 恒定乘积公式（x * y = k）

**核心公式：**
```
x * y = k
```

其中：
- `x`：token0 的储备量
- `y`：token1 的储备量
- `k`：恒定乘积

**特性：**
- 交换后乘积保持不变（或略微增加）
- 价格随交易量自动调整
- 池子永远不会被抽干（k > 0）

### 2. 价格确定

**价格公式：**
```
价格 = reserve1 / reserve0
```

例如：
- `reserve0 = 10 ETH`, `reserve1 = 20,000 USDT`
- ETH 价格 = 20,000 / 10 = 2,000 USDT/ETH

### 3. 流动性代币计算

**首次添加：**
```
liquidity = sqrt(amount0 * amount1)
```

**后续添加：**
```
liquidity0 = (amount0 * totalSupply) / reserve0
liquidity1 = (amount1 * totalSupply) / reserve1
liquidity = min(liquidity0, liquidity1)
```

**移除时：**
```
amount0 = (liquidity * balance0) / totalSupply
amount1 = (liquidity * balance1) / totalSupply
```

### 4. 价格不变性

**添加流动性时：**
- 必须按照当前比例添加：`(x + dx) / (y + dy) = x / y`
- 如果比例不匹配，多余的代币会被退回

**移除流动性时：**
- 按比例移除：`(x - dx) / (y - dy) = x / y`
- 确保价格不变

---

## 💡 使用示例

### 示例 1：添加流动性

```solidity
address pair = 0x...; // DAI/USDT 交易对地址
address DAI = 0x6B...;
address USDT = 0xdA...;

// 首次添加流动性
uint256 amount0 = 1000 * 10**18;  // 1000 DAI
uint256 amount1 = 2000 * 10**6;   // 2000 USDT

// 需要先授权
IERC20(DAI).approve(pair, amount0);
IERC20(USDT).approve(pair, amount1);

// 添加流动性
uint256 liquidity = CPAMM(pair).addLiquidity(amount0, amount1);
// liquidity = sqrt(1000 * 2000) ≈ 1414 LP tokens
```

### 示例 2：移除流动性

```solidity
address pair = 0x...;
uint256 liquidity = 100; // 要移除的 LP tokens 数量

// 移除流动性
(uint256 amount0, uint256 amount1) = CPAMM(pair).removeLiquidity(liquidity);
// 按比例返回 DAI 和 USDT
```

### 示例 3：执行交换

```solidity
address pair = 0x...;
address DAI = 0x6B...;

uint256 amountIn = 100 * 10**18;  // 100 DAI
uint256 amountOutMin = 190 * 10**6; // 至少 190 USDT

// 需要先授权
IERC20(DAI).approve(pair, amountIn);

// 执行交换
uint256 amountOut = CPAMM(pair).swap(
    DAI,           // tokenIn
    amountIn,      // amountIn
    amountOutMin,  // amountOutMin
    msg.sender     // to
);
```

### 示例 4：查询储备量

```solidity
address pair = 0x...;

(uint256 reserve0, uint256 reserve1) = CPAMM(pair).getReserves();
// reserve0: token0 的储备量
// reserve1: token1 的储备量
```

---

## ⚠️ 重要注意事项

### 1. 首次添加流动性

- 首次添加流动性时，两种代币的比例决定了初始价格
- 初始流动性 = `sqrt(amount0 * amount1)`
- 后续添加必须按照当前比例

### 2. 滑点保护

- 交换时使用 `amountOutMin` 防止滑点过大
- 如果实际输出少于 `amountOutMin`，交易会回滚

### 3. 授权要求

- 添加流动性和交换前，需要先授权 Pair 合约转移代币
- 使用 `approve(pairAddress, amount)`

### 4. 储备量更新

- 储备量在每次操作后都会更新
- 使用实际余额更新，而不是计算值（防止精度误差）

### 5. 重入攻击防护

- 合约使用 Checks-Effects-Interactions 模式
- 先更新状态，再转移代币

---

## 🔗 与其他合约的关系

### Pair ↔ Factory

```
Factory 合约
  │
  └── createPair() → 部署新的 Pair 合约
```

### Pair ↔ Router

```
Router 合约
  │
  ├── addLiquidity() → 调用 Pair.addLiquidity()
  ├── removeLiquidity() → 调用 Pair.removeLiquidity()
  └── swap() → 调用 Pair.swap()
```

### 完整交互流程

```
用户
  │
  ↓
Router (处理授权、比例计算、滑点检查)
  │
  ↓
Pair (执行实际操作：添加/移除流动性、交换)
  │
  ↓
更新储备量、铸造/销毁 LP tokens、转移代币
```

---

## 📚 相关文档

- [Factory 合约](./FACTORY_CONTRACT.md) - 了解如何创建 Pair 合约
- [Router 合约](../periphery/CPAMMRouter.sol) - 了解如何通过 Router 与 Pair 交互
- [代币交换执行流程](../periphery/SWAP_EXECUTION_FLOW.md) - 了解交换的完整流程

---

## 🎓 总结

Pair 合约是 Uniswap V2 的核心，它：

1. **管理流动性池**：存储两种代币的储备量
2. **执行代币交换**：根据恒定乘积公式自动定价
3. **管理流动性**：添加和移除流动性，铸造和销毁 LP tokens
4. **价格不变性**：添加/移除流动性时保持价格不变

理解 Pair 合约的工作原理，对于理解整个 Uniswap V2 系统至关重要。

