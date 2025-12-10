# Swap 函数对比：swapExactTokensForTokens vs swapTokensForExactTokens

## 📋 核心区别

这两个函数的核心区别，在于兑换的 **"目标逻辑"** 完全相反：
- **swapExactTokensForTokens**：定输入量，求最少输出
- **swapTokensForExactTokens**：定输出量，求最多输入

---

## 1️⃣ swapExactTokensForTokens（定输入，求输出）

### 核心逻辑
> 我要花掉**精确数量**的 A 代币，换回**至少 X 数量**的 B 代币

### 关键特点
- ✅ **输入代币的数量是"精确固定"的**（比如我确定要花 100 USDT）
- ✅ 你需要指定 **"输出代币的最小接收量"**（`amountOutMin`），防止滑点导致换到的代币太少
- ✅ **最终兑换结果**：实际换到的 B 代币 ≥ `amountOutMin`（满足则成交，否则回滚）

### 使用场景
想精准控制 **"花多少钱"**，比如：
- 我就想花 100 USDT
- 不管能换多少 ETH
- 只要不少于 0.02 ETH 就行

### 代码实现
```solidity
function swapExactTokensForTokens(
    uint256 amountIn,        // 精确的输入数量（固定值）
    uint256 amountOutMin,    // 最小输出数量（保护值）
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts) {
    // 1. 根据精确输入计算输出
    amounts = _getAmountsOut(amountIn, path);
    
    // 2. 检查输出是否满足最小要求
    require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    
    // 3. 执行交换
    _safeTransferFrom(IERC20(path[0]), msg.sender, _pairFor(path[0], path[1]), amounts[0]);
    _swap(amounts, path, to);
}
```

---

## 2️⃣ swapTokensForExactTokens（定输出，求输入）

### 核心逻辑
> 我要换到**精确数量**的 B 代币，**最多花 X 数量**的 A 代币

### 关键特点
- ✅ **输出代币的数量是"精确固定"的**（比如我确定要换 0.02 ETH）
- ✅ 你需要指定 **"输入代币的最大花费量"**（`amountInMax`），防止滑点导致花太多钱
- ✅ **最终兑换结果**：实际花的 A 代币 ≤ `amountInMax`（满足则成交，否则回滚）

### 使用场景
想精准控制 **"换到多少币"**，比如：
- 我就想要 0.02 ETH
- 不管花多少 USDT
- 只要不超过 100 USDT 就行

### 代码实现
```solidity
function swapTokensForExactTokens(
    uint256 amountOut,       // 精确的输出数量（固定值）
    uint256 amountInMax,     // 最大输入数量（保护值）
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts) {
    // 1. 根据精确输出反向计算输入
    amounts = _getAmountsIn(amountOut, path);
    
    // 2. 检查输入是否超过最大限制
    require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
    
    // 3. 执行交换
    _safeTransferFrom(IERC20(path[0]), msg.sender, _pairFor(path[0], path[1]), amounts[0]);
    _swap(amounts, path, to);
}
```

---

## 📊 核心对比表

| 维度 | swapExactTokensForTokens | swapTokensForExactTokens |
|------|-------------------------|-------------------------|
| **固定值** | 输入代币数量（精确） | 输出代币数量（精确） |
| **限制值** | 输出代币最小量（`amountOutMin`） | 输入代币最大量（`amountInMax`） |
| **核心诉求** | 花固定的钱，换至少 X 的币 | 换固定的币，最多花 X 的钱 |
| **计算方向** | 正向：输入 → 输出 | 反向：输出 → 输入 |
| **使用的辅助函数** | `_getAmountsOut()` | `_getAmountsIn()` |
| **检查条件** | `实际输出 >= amountOutMin` | `实际输入 <= amountInMax` |
| **失败原因** | 输出太少（滑点过大） | 输入太多（滑点过大） |

---

## 💡 记忆技巧

**简单记法**：
- **Exact 在 Tokens 前** → 是 **"输入精确"**（Exact Tokens For Tokens）
- **Exact 在 Tokens 后** → 是 **"输出精确"**（Tokens For Exact Tokens）

**中文理解**：
- `swapExactTokensForTokens` = 用**精确的**代币换代币
- `swapTokensForExactTokens` = 用代币换**精确的**代币

---

## 🔍 数学公式对比

### swapExactTokensForTokens
```
已知：amountIn（精确输入）
计算：amountOut = f(amountIn, reserves)
检查：amountOut >= amountOutMin
```

### swapTokensForExactTokens
```
已知：amountOut（精确输出）
计算：amountIn = f^(-1)(amountOut, reserves)
检查：amountIn <= amountInMax
```

---

## 📝 实际使用示例

### 示例 1：swapExactTokensForTokens
```javascript
// 场景：我有 100 USDT，想换成 ETH，但至少要换到 0.02 ETH
router.swapExactTokensForTokens(
    100 * 10**18,           // amountIn: 精确花 100 USDT
    0.02 * 10**18,          // amountOutMin: 至少换到 0.02 ETH
    [USDT, WETH],           // path
    myAddress,              // to
    deadline                // deadline
);
```

### 示例 2：swapTokensForExactTokens
```javascript
// 场景：我想要 0.02 ETH，用 USDT 换，但最多花 100 USDT
router.swapTokensForExactTokens(
    0.02 * 10**18,          // amountOut: 精确换到 0.02 ETH
    100 * 10**18,           // amountInMax: 最多花 100 USDT
    [USDT, WETH],           // path
    myAddress,              // to
    deadline                // deadline
);
```

---

## ⚠️ 注意事项

1. **滑点保护**：
   - `swapExactTokensForTokens` 使用 `amountOutMin` 防止输出太少
   - `swapTokensForExactTokens` 使用 `amountInMax` 防止输入太多

2. **计算方向**：
   - `swapExactTokensForTokens` 使用正向计算（`_getAmountsOut`）
   - `swapTokensForExactTokens` 使用反向计算（`_getAmountsIn`）

3. **舍入误差**：
   - 反向计算（`_getAmountIn`）需要 `+1` 来避免舍入误差
   - 正向计算（`_getAmountsOut`）直接使用公式即可

4. **选择建议**：
   - 如果你有**固定预算**（比如只有 100 USDT），用 `swapExactTokensForTokens`
   - 如果你有**固定需求**（比如需要 0.02 ETH），用 `swapTokensForExactTokens`

