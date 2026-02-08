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

**实际使用示例：**

```solidity
// 示例：用 1 WETH 兑换 USDT
// 市场价：1 WETH = 2000 USDT
// 根据池子储备量计算，实际可以得到 1990 USDT（考虑手续费和滑点）
router.swapExactTokensForTokens(
    1 * 10**18,           // amountIn: 1 WETH（精确输入）
    1950 * 10**6,         // amountOutMin: 至少 1950 USDT（滑点保护）
    [WETH, USDT],         // path: 兑换路径
    userAddress,          // to: 接收地址
    deadline             // deadline: 交易截止时间
);
```

**参数说明：**
- `amountIn = 1 WETH`：确定要花费的输入代币数量
- `amountOutMin = 1950 USDT`：滑点保护，如果实际得到少于 1950 USDT，交易会回滚
- 实际可能得到：1990 USDT（根据池子储备量计算，考虑 0.3% 手续费）

**路由合约此时执行：**
1. 验证 `deadline` 是否过期
2. 验证 `path` 是否有效（至少包含 2 个代币地址）
3. 计算输出/输入数量（使用 `_getAmountsOut` 或 `_getAmountsIn`）
4. 检查滑点保护（`amountOutMin` 或 `amountInMax`）

### 详细说明：计算输出/输入数量

路由合约需要预先计算每跳的输入和输出数量，以便：
- 验证滑点保护
- 传递给 `_swap` 函数执行实际交换

#### `_getAmountsOut`：正向计算（已知输入，求输出）

**使用场景**：`swapExactTokensForTokens`（固定输入，求输出）

```solidity
function _getAmountsOut(uint256 amountIn, address[] memory path)
    internal view returns (uint256[] memory amounts)
{
    require(path.length >= 2, "INVALID_PATH");
    amounts = new uint256[](path.length);
    amounts[0] = amountIn;  // 第一个是输入数量
    
    // 正向计算：从第一跳到最后一跳
    for (uint256 i; i < path.length - 1; i++) {
        address pair = _pairFor(path[i], path[i + 1]);
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, path[i], path[i + 1]);
        // 根据恒定乘积公式计算输出
        amounts[i + 1] = CPAMM(pair).getAmountOut(amounts[i], reserveIn, reserveOut);
    }
}
```

**计算过程示例**（DAI → USDT → MKR）：
```
输入：amountIn = 1000 DAI, path = [DAI, USDT, MKR]

第1跳：DAI → USDT
  - 输入：amounts[0] = 1000 DAI
  - 根据 DAI/USDT 池子储备量计算
  - 输出：amounts[1] = 1000 USDT（假设）

第2跳：USDT → MKR
  - 输入：amounts[1] = 1000 USDT
  - 根据 USDT/MKR 池子储备量计算
  - 输出：amounts[2] = 50 MKR（假设）

返回：amounts = [1000, 1000, 50]
```

#### `_getAmountsIn`：反向计算（已知输出，求输入）

**使用场景**：`swapTokensForExactTokens`（固定输出，求输入）

```solidity
function _getAmountsIn(uint256 amountOut, address[] memory path)
    internal view returns (uint256[] memory amounts)
{
    require(path.length >= 2, "INVALID_PATH");
    amounts = new uint256[](path.length);
    amounts[amounts.length - 1] = amountOut;  // 最后一个是输出数量
    
    // 反向计算：从最后一跳到第一跳
    for (uint256 i = path.length - 1; i > 0; i--) {
        address pair = _pairFor(path[i - 1], path[i]);
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, path[i - 1], path[i]);
        // 反向计算：已知输出，求输入
        amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
    }
}
```

**计算过程示例**（DAI → USDT → MKR）：
```
输入：amountOut = 50 MKR, path = [DAI, USDT, MKR]

第2跳：USDT → MKR（反向）
  - 输出：amounts[2] = 50 MKR
  - 根据 USDT/MKR 池子储备量反向计算
  - 输入：amounts[1] = 1000 USDT（假设）

第1跳：DAI → USDT（反向）
  - 输出：amounts[1] = 1000 USDT
  - 根据 DAI/USDT 池子储备量反向计算
  - 输入：amounts[0] = 1000 DAI（假设）

返回：amounts = [1000, 1000, 50]
```

#### 核心公式

**正向计算（`getAmountOut`）**：
```
amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
```

**反向计算（`getAmountIn`）**：
```
amountIn = (amountOut * reserveIn) / (reserveOut - amountOut) + 1
```
注意：反向计算需要 `+1` 来避免舍入误差。

#### 为什么需要预先计算？

1. **滑点保护**：在交易执行前就知道输出/输入数量，可以验证是否满足滑点要求
2. **原子性**：所有计算在一个交易中完成，要么全部成功，要么全部失败
3. **效率**：避免在交换过程中重复计算

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

## 📍 路径（Path）的概念

### 什么是路径？

路径（`path`）是一个代币地址数组，定义了从输入代币到输出代币的兑换路线。**只要存在路径，就可以转换过去**。

### 路径的基本规则

1. **路径长度**：至少包含 2 个代币地址（直接兑换）
2. **路径顺序**：第一个是输入代币，最后一个是输出代币
3. **中间代币**：路径中的每个相邻代币对必须存在流动性池

### 路径示例

#### 示例 1：直接兑换（2 跳）
```
Token A → USDT
path = [TokenA, USDT]
```
需要存在：TokenA/USDT 流动性池

#### 示例 2：通过中间代币（3 跳）
```
Token A → USDT/USDD → wBTC
path = [TokenA, USDT, wBTC]
```
需要存在：
- TokenA/USDT 流动性池
- USDT/wBTC 流动性池

#### 示例 3：多跳兑换（4 跳）
```
Token A → USDT → USDD → wBTC
path = [TokenA, USDT, USDD, wBTC]
```
需要存在：
- TokenA/USDT 流动性池
- USDT/USDD 流动性池
- USDD/wBTC 流动性池

### 路径选择的原则

**核心思想**：只要路径上的每个相邻代币对都有流动性池，就可以完成兑换。

**路径选择的考虑因素**：
1. **流动性深度**：选择流动性更好的路径，减少滑点
2. **手续费**：多跳兑换会产生多次手续费
3. **价格影响**：直接兑换可能比多跳兑换价格更好
4. **路径存在性**：必须确保路径上的每个池子都存在

### 路径不存在的处理

如果指定的路径中某个池子不存在，交易会失败并回滚。路由合约会检查：
- 每个池子是否由 Factory 创建
- 每个池子是否有足够的流动性

---

## 多跳兑换流程

当 `path` 包含多个代币时（例如 `[DAI, USDT, MKR]`），路由合约会依次在多个池子中执行交换。

### 示例：DAI → USDT → MKR

假设用户想要将 DAI 兑换成 MKR，但 DAI/MKR 池子不存在或流动性不足，可以通过 USDT 作为中间代币：

```
用户 (User)
  │
  │ ① 调用 swapExactTokensForTokens 或 swapTokensForExactTokens
  │    path = [DAI, USDT, MKR]
  ↓
Router02.sol (路由合约)
  │
  │ ② transferFrom (DAI 从用户转移到 DAI/USDT 池子)
  ↓
DAI/USDT Pair (第一个流动性池)
  │
  │ ③ Swap (DAI → USDT，执行第一次交换)
  │
  │ ④ transfer (USDT 转给路由合约)
  ↓
Router02.sol (路由合约)
  │
  │ ⑤ transferFrom (USDT 从路由合约转移到 USDT/MKR 池子)
  ↓
USDT/MKR Pair (第二个流动性池)
  │
  │ ⑥ Swap (USDT → MKR，执行第二次交换)
  │
  │ ⑦ transfer (MKR 转回用户)
  ↓
用户收到 MKR
```

### 详细步骤说明（DAI → USDT → MKR）

#### 步骤 ①：用户调用路由合约

```solidity
router.swapExactTokensForTokens(
    1000 * 10**18,        // amountIn: 1000 DAI
    50 * 10**18,          // amountOutMin: 至少 50 MKR
    [DAI, USDT, MKR],     // path: 多跳路径
    userAddress,          // to: 接收地址
    deadline             // deadline
);
```

#### 步骤 ②：DAI 转移到第一个池子

路由合约将 DAI 从用户转移到 DAI/USDT 池子：
```solidity
IERC20(DAI).transferFrom(user, daiUsdtPair, 1000 * 10**18);
```

#### 步骤 ③-④：第一次交换（DAI → USDT）

DAI/USDT 池子执行交换：
- 输入：1000 DAI
- 输出：假设 1000 USDT（根据池子储备量计算）
- USDT 转给路由合约

#### 步骤 ⑤：USDT 转移到第二个池子

路由合约将 USDT 转移到 USDT/MKR 池子：
```solidity
IERC20(USDT).transferFrom(router, usdtMkrPair, 1000 * 10**6);
```

#### 步骤 ⑥-⑦：第二次交换（USDT → MKR）

USDT/MKR 池子执行交换：
- 输入：1000 USDT
- 输出：假设 50 MKR（根据池子储备量计算）
- MKR 转回用户

### 关键点

1. **中间代币的流转**：
   - USDT 作为中间代币，会先转到路由合约，再转到下一个池子
   - 路由合约作为中间代币的临时持有者，但不长期持有
   - 整个过程在一个交易中完成，原子性保证

2. **路径要求**：
   - **只要路径存在，就可以完成兑换**：只要 DAI/USDT 和 USDT/MKR 这两个池子都存在，就可以完成 DAI → MKR 的兑换
   - 如果路径中任何一个池子不存在，整个交易会失败并回滚

3. **滑点保护**：
   - `amountOutMin` 是针对最终输出（MKR）的保护
   - 如果最终得到的 MKR 少于 `amountOutMin`，整个交易会回滚
   - 即使中间某一步价格不利，只要最终结果满足要求，交易就会成功

4. **手续费**：
   - 每跳都会产生手续费（通常为 0.3%）
   - DAI → USDT：产生手续费
   - USDT → MKR：产生手续费
   - 总手续费 = 第一跳手续费 + 第二跳手续费

### 多跳兑换的优势

1. **扩大交易对范围**：即使两个代币之间没有直接池子，也可以通过中间代币兑换
2. **可能获得更好的价格**：通过流动性更好的中间代币，有时能获得比直接兑换更好的价格
3. **灵活性**：可以选择不同的路径来优化交易结果

### 多跳兑换的劣势

1. **更高的手续费**：每跳都会产生手续费
2. **更高的滑点**：多次交换累积的滑点可能更大
3. **更复杂的计算**：需要计算每跳的输出，确保最终结果满足要求

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

## 🔧 路由合约内部实现：`_swap` 函数

`_swap` 函数是路由合约的核心内部函数，负责执行多跳兑换的实际逻辑。这是路由合约的关键实现。

### 为什么函数名前面有下划线？

在 Solidity 中，**下划线前缀（`_`）是一个命名约定**，用于标识**内部函数（internal functions）**。

**命名约定说明：**
- **`_functionName`**：表示 `internal` 函数，只能在合约内部或继承合约中调用
- **`functionName`**：通常是 `public` 或 `external` 函数，可以被外部调用

**为什么使用下划线？**
1. **代码可读性**：一眼就能看出这是内部辅助函数，不是对外接口
2. **避免命名冲突**：防止内部函数与外部函数名称冲突
3. **安全考虑**：明确标识哪些函数不应该被外部直接调用
4. **行业标准**：这是 Solidity 社区广泛采用的约定（类似 Python 的私有方法约定）

**路由合约中的内部函数示例：**
- `_swap`：执行交换的内部逻辑
- `_sortTokens`：对代币地址排序
- `_getReserves`：获取池子储备量
- `_getAmountsOut`：计算输出数量
- `_pairFor`：获取交易对地址
- `_safeTransfer`：安全转移代币

这些函数都是 `internal` 的，只能被合约内部的其他函数调用，不能直接从外部调用。

### 函数签名

```solidity
function _swap(
    uint256[] memory amounts,  // 每跳的输入/输出数量数组
    address[] memory path,     // 代币路径数组
    address _to                // 最终接收代币的地址
) internal virtual
```

### 核心实现逻辑

```solidity
function _swap(uint256[] memory amounts, address[] memory path, address _to) 
    internal virtual 
{
    // 循环处理路径中的每一跳
    for (uint256 i; i < path.length - 1; i++) {
        // 1. 提取当前跳的输入和输出代币
        (address input, address output) = (path[i], path[i + 1]);
        
        // 2. 对代币地址排序（确保 token0 < token1）
        (address token0,) = _sortTokens(input, output);
        // 注意：这里只接收 token0，忽略 token1
        // Solidity 语法：用逗号可以跳过不需要的返回值
        
        // 3. 获取当前跳的输出数量
        uint256 amountOut = amounts[i + 1];
        
        // 4. 根据代币顺序确定 amount0Out 和 amount1Out
        (uint256 amount0Out, uint256 amount1Out) = input == token0
            ? (uint256(0), amountOut)      // input 是 token0
            : (amountOut, uint256(0));      // input 是 token1
        
        // 5. 确定接收地址
        // 如果是中间跳，接收地址是下一个池子
        // 如果是最后一跳，接收地址是最终用户
        address to = i < path.length - 2 
            ? _pairFor(output, path[i + 2])  // 中间跳：下一个池子
            : _to;                            // 最后一跳：最终用户
        
        // 6. 获取当前池子地址并执行交换
        address pair = _pairFor(input, output);
        CPAMM(pair).swap(input, amounts[i], 0, to);
    }
}
```

### 关键步骤详解

#### 1. 循环处理每一跳

```solidity
for (uint256 i; i < path.length - 1; i++)
```

- 对于路径 `[DAI, USDT, MKR]`，会执行 2 次循环：
  - `i = 0`: 处理 DAI → USDT
  - `i = 1`: 处理 USDT → MKR

#### 2. 代币排序（为什么需要排序？）

```solidity
(address token0,) = _sortTokens(input, output);
```

**为什么需要对代币地址排序？**

在 Uniswap V2 中，每个流动性池（Pair）合约在创建时就确定了 `token0` 和 `token1` 的顺序：

```solidity
// CPAMM 合约中的定义
IERC20 public immutable token0;  // 地址较小的代币
IERC20 public immutable token1;  // 地址较大的代币

constructor(address _token0, address _token1) {
    require(_token0 < _token1, "token0 must be less than token1");
    token0 = IERC20(_token0);
    token1 = IERC20(_token1);
}
```

**排序的原因：**

1. **确保一致性**：
   - 池子中的储备量按 `reserve0`（对应 token0）和 `reserve1`（对应 token1）存储
   - 无论用户传入 `[DAI, USDT]` 还是 `[USDT, DAI]`，都需要知道哪个是 token0，哪个是 token1

2. **正确访问储备量**：
   ```solidity
   // 如果 input 是 token0，则 reserveIn = reserve0, reserveOut = reserve1
   // 如果 input 是 token1，则 reserveIn = reserve1, reserveOut = reserve0
   ```

3. **正确设置输出数量**：
   ```solidity
   // 如果 input 是 token0，输出的是 token1，所以 amount0Out = 0, amount1Out = amountOut
   // 如果 input 是 token1，输出的是 token0，所以 amount0Out = amountOut, amount1Out = 0
   ```

4. **防止重复创建池子**：
   - Factory 合约通过 `token0 < token1` 的规则确保同一个交易对只有一个池子
   - `[DAI, USDT]` 和 `[USDT, DAI]` 会被识别为同一个池子

**排序实现：**
```solidity
function _sortTokens(address tokenA, address tokenB)
    internal pure returns (address token0, address token1)
{
    // 按地址大小排序：地址较小的作为 token0
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "ZERO_ADDRESS");
}
```

**为什么只接收 `token0`？**

在 `_swap` 函数中，我们只需要知道 `token0` 是哪个，因为：

```solidity
(address token0,) = _sortTokens(input, output);
```

**Solidity 解构赋值语法：**
- `_sortTokens` 返回两个值：`(address token0, address token1)`
- 如果只需要第一个返回值，可以用逗号跳过第二个：`(address token0,)`
- 这等价于：`address token0 = _sortTokens(input, output).token0;`（但 Solidity 不支持这种语法）

**为什么只需要 `token0`？**

因为我们可以通过比较 `input == token0` 来判断：
- 如果 `input == token0`，则 `input` 是 token0，`output` 是 token1
- 如果 `input != token0`，则 `input` 是 token1，`output` 是 token0

所以不需要显式接收 `token1`，可以通过逻辑判断得出。

**示例：**
- 假设 `DAI` 地址 = `0x6B...`，`USDT` 地址 = `0xdA...`
- 因为 `0x6B... < 0xdA...`，所以 `token0 = DAI`，`token1 = USDT`
- 无论用户传入 `[DAI, USDT]` 还是 `[USDT, DAI]`，排序后都是 `token0 = DAI, token1 = USDT`
- 如果 `input = DAI`，则 `input == token0` 为 `true`，说明输入是 token0
- 如果 `input = USDT`，则 `input == token0` 为 `false`，说明输入是 token1

#### 3. 确定输出数量

```solidity
uint256 amountOut = amounts[i + 1];
```

- `amounts` 数组在调用 `_swap` 前已经通过 `_getAmountsOut` 或 `_getAmountsIn` 计算好
- `amounts[0]` = 输入代币数量
- `amounts[1]` = 第一跳的输出数量
- `amounts[2]` = 第二跳的输出数量（如果有）
- ...

#### 4. 设置 amount0Out 和 amount1Out

```solidity
(uint256 amount0Out, uint256 amount1Out) = input == token0
    ? (uint256(0), amountOut)
    : (amountOut, uint256(0));
```

- Pair 合约的 `swap` 函数需要知道输出的是 `token0` 还是 `token1`
- 如果输入是 `token0`，则 `amount0Out = 0, amount1Out = amountOut`
- 如果输入是 `token1`，则 `amount0Out = amountOut, amount1Out = 0`

#### 5. 确定接收地址（关键！）

```solidity
address to = i < path.length - 2 
    ? _pairFor(output, path[i + 2])  // 中间跳
    : _to;                            // 最后一跳
```

**这是多跳兑换的关键逻辑：**

- **中间跳**（`i < path.length - 2`）：
  - 接收地址是**下一个池子**
  - 例如：DAI → USDT 时，USDT 会转到 USDT/MKR 池子
- **最后一跳**（`i == path.length - 2`）：
  - 接收地址是**最终用户**（`_to`）
  - 例如：USDT → MKR 时，MKR 会转到用户地址

#### 6. 执行交换

```solidity
CPAMM(pair).swap(input, amounts[i], 0, to);
```

- 调用底层 Pair 合约的 `swap` 函数
- `amounts[i]` 是当前跳的输入数量
- `to` 是接收输出代币的地址

### 示例：DAI → USDT → MKR

假设 `path = [DAI, USDT, MKR]`，`amounts = [1000, 1000, 50]`（已计算好）：

**第一次循环（i = 0）：**
- `input = DAI`, `output = USDT`
- `amountOut = 1000` (USDT)
- `to = USDT/MKR 池子地址`（因为还有下一跳）
- 执行：DAI/USDT 池子将 1000 USDT 转到 USDT/MKR 池子

**第二次循环（i = 1）：**
- `input = USDT`, `output = MKR`
- `amountOut = 50` (MKR)
- `to = 用户地址`（这是最后一跳）
- 执行：USDT/MKR 池子将 50 MKR 转到用户地址

### 为什么这样设计？

1. **原子性**：所有跳在一个交易中完成，要么全部成功，要么全部失败
2. **效率**：中间代币不需要先转给用户再转给下一个池子
3. **安全性**：路由合约作为中间代币的临时持有者，但不长期持有

---

## 相关文档

- [Swap 函数对比](./SWAP_FUNCTIONS_COMPARISON.md) - 了解 `swapExactTokensForTokens` 和 `swapTokensForExactTokens` 的区别
- [CPAMMRouter.sol](./CPAMMRouter.sol) - 路由合约的完整实现

