# Hardhat 2.0 Project - 恒定乘积自动做市商 (CPAMM)

这是一个使用 Hardhat 2.0 的以太坊开发环境项目，实现了恒定乘积自动做市商（Constant Product Automated Market Maker）算法。

## 什么是 CPAMM？

恒定乘积自动做市商使用公式 **x * y = k**，其中：
- `x` 和 `y` 是两种代币的储备量
- `k` 是常数（恒定乘积）

这是 Uniswap V2 的核心算法，用于：
- 提供流动性池
- 执行代币交换
- 自动定价

## 安装

```bash
npm install
```

## 可用命令

### 编译合约
```bash
npm run compile
# 或
npx hardhat compile
```

### 运行测试
```bash
npm run test
# 或
npx hardhat test
```

### 启动本地节点
```bash
npm run node
# 或
npx hardhat node
```

### 部署合约
```bash
npm run deploy
# 或
npx hardhat run scripts/deploy.js
```

### 部署 CPAMM
```bash
npx hardhat run scripts/deployCPAMM.js
```

### 部署到网络
```bash
npx hardhat run scripts/deploy.js --network <network-name>
npx hardhat run scripts/deployCPAMM.js --network <network-name>
```

## 项目结构

```
.
├── contracts/          # Solidity 智能合约
│   ├── CPAMM.sol      # 恒定乘积自动做市商核心合约
│   ├── ERC20.sol      # ERC20 代币合约（用于测试）
│   └── Lock.sol       # 示例合约
├── scripts/            # 部署脚本
│   ├── deploy.js      # 部署示例合约
│   └── deployCPAMM.js # 部署 CPAMM 合约
├── test/               # 测试文件
│   ├── CPAMM.test.js  # CPAMM 测试
│   └── Lock.js        # 示例合约测试
├── v2/                 # Uniswap V2 文档和实现
│   ├── core/          # 核心合约文档
│   │   ├── Factory（工厂）合约.md
│   │   └── Pair（交易对）合约.md
│   ├── periphery/     # 外围合约文档
│   │   ├── Swap 函数对比.md
│   │   └── Uniswap V2 中代币交换的完整执行流程.md
│   ├── concepts/      # 核心概念文档
│   │   ├── 手续费机制.md
│   │   ├── 添加移除流动性.md
│   │   ├── 无常损失.md
│   │   ├── 闪电交换.md
│   │   └── 时间加权平均价格.md
│   └── UNISWAP_V2_学习指南.md
├── v3/                 # Uniswap V3 文档和实现
│   └── concepts/      # 核心概念文档
│       ├── Uniswap V3 简介.md
│       ├── Uniswap V3 的核心创新——集中流动性.md
│       ├── Uniswap V3 Tick 与价格表示详解.md
│       └── ...（更多 V3 文档）
├── hardhat.config.js   # Hardhat 配置文件
└── package.json
```

## CPAMM 核心功能

### 1. 添加流动性 (`addLiquidity`)
向流动性池添加两种代币，获得流动性代币（LP tokens）。

```solidity
cpamm.addLiquidity(amount0, amount1);
```

**重要原则**：
- **初始流动性决定代币价格**：首次添加流动性时，两种代币的数量比例决定了初始价格
- **添加流动性不能影响价格**：后续添加流动性时，必须按照当前池中的代币比例添加，以保持价格不变
- **比例保持公式**：`(x + dx) / (y + dy) = x / y`，其中 `x`、`y` 是当前储备量，`dx`、`dy` 是新增的流动性

### 2. 移除流动性 (`removeLiquidity`)
销毁流动性代币，取回对应的两种代币。

```solidity
cpamm.removeLiquidity(liquidity);
```

**重要原则**：
- **移除流动性不能影响价格**：移除流动性时，按照当前池中的代币比例移除，保持价格不变
- 移除的两种代币数量与 LP tokens 的比例成正比

### 3. 代币交换 (`swap`)
使用恒定乘积公式进行代币交换。

```solidity
cpamm.swap(tokenIn, amountIn, amountOutMin, to);
```

### 4. 计算输出数量 (`getAmountOut`)
根据恒定乘积公式计算交换后的输出数量。

```solidity
uint256 amountOut = cpamm.getAmountOut(amountIn, reserveIn, reserveOut);
```

## 算法原理

### 恒定乘积公式
```
(x + Δx) * (y - Δy) = x * y = k
```

其中：
- `x`, `y`: 当前储备量
- `Δx`: 输入的代币数量
- `Δy`: 输出的代币数量
- `k`: 恒定乘积

### 计算输出数量
```
Δy = (y * Δx) / (x + Δx)
```

这个公式确保了：
- 交换后乘积保持不变（或略微增加）
- 价格随交易量自动调整
- 池子永远不会被抽干

### 价格确定机制

在 CPAMM 中，代币价格由池中的储备量比例决定：

```
价格 = reserve1 / reserve0
```

例如，如果池中有 10 ETH 和 20,000 USDT，则：
- ETH 价格 = 20,000 / 10 = 2,000 USDT/ETH
- USDT 价格 = 10 / 20,000 = 0.0005 ETH/USDT

### 流动性操作的价格不变性

**添加流动性时**：
- 必须按照当前价格比例添加：`dx / dy = x / y`
- 这确保了 `(x + dx) / (y + dy) = x / y`，价格保持不变
- 如果比例不匹配，多余的代币会被退回或要求补充

**移除流动性时**：
- 按照 LP tokens 的比例移除：`dx / x = dy / y = liquidity / totalSupply`
- 这确保了移除后 `(x - dx) / (y - dy) = x / y`，价格保持不变

## 重要概念

### 流动性 (Liquidity)

**流动性**是指能够快速、低成本地进行资产交易的能力。在 CPAMM 中，流动性特指流动性池中锁定的两种代币的总价值。

1. **流动性池 (Liquidity Pool)**：
   - 流动性池是一个智能合约，存储了两种代币的储备量（reserve0 和 reserve1）
   - 用户可以向池中添加流动性，成为流动性提供者（Liquidity Provider, LP）
   - 池中的代币用于执行代币交换

2. **流动性代币 (LP Tokens)**：
   - 当用户向池中添加流动性时，会收到流动性代币（LP tokens）作为凭证
   - LP tokens 代表用户在池中的份额比例
   - 移除流动性时，需要销毁相应数量的 LP tokens 来取回代币

3. **流动性计算公式**：
   在 CPAMM 中，流动性可以通过以下方式衡量：
   ```
   流动性深度 = reserve0 × reserve1
   总流动性价值 = reserve0 × price0 + reserve1 × price1
   ```

4. **流动性的重要性**：
   - **降低滑点**：池中流动性越多，大额交易对价格的影响越小，滑点越低
   - **提高交易效率**：充足的流动性使交易可以快速完成
   - **价格稳定性**：流动性越多，价格波动越平滑

5. **流动性提供者的收益**：
   - 流动性提供者通过提供流动性可以获得交易手续费分成
   - 但同时需要承担**无常损失**（Impermanent Loss）的风险

6. **示例**：
   - 假设池中有 10,000 个 TokenA 和 20,000 个 TokenB
   - 当前流动性深度 = 10,000 × 20,000 = 200,000,000
   - 如果用户添加 1,000 个 TokenA 和 2,000 个 TokenB
   - 新增流动性将提高池的总价值，减少后续交易的滑点

### 滑点 (Slippage)

**滑点**是指预期价格与实际执行价格之间的差异。在去中心化交易所（DEX）中，滑点通常发生在以下情况：

1. **价格影响**：当交易规模较大时，由于恒定乘积公式 `x * y = k`，较大的交易会显著影响池中的代币比例，导致实际得到的代币数量少于预期。

2. **滑点计算公式**：
   ```
   滑点 = (预期输出数量 - 实际输出数量) / 预期输出数量 × 100%
   ```

3. **示例**：
   - 假设你期望用 100 个 TokenA 换取 200 个 TokenB
   - 实际执行时只得到了 190 个 TokenB
   - 滑点 = (200 - 190) / 200 × 100% = 5%

4. **滑点保护**：
   在 `swap` 函数中，`amountOutMin` 参数用于防止滑点过大：
   ```solidity
   function swap(
       address tokenIn,
       uint256 amountIn,
       uint256 amountOutMin,  // 最小输出数量（滑点保护）
       address to
   ) external returns (uint256 amountOut);
   ```
   
   如果实际输出数量 `amountOut` 小于 `amountOutMin`，交易将被回滚，保护用户免受不利的价格变动。

5. **影响滑点的因素**：
   - **交易规模**：交易量越大，滑点通常越大
   - **流动性深度**：池中流动性越多，滑点越小
   - **市场波动**：在执行交易前，池中状态可能已发生变化

## 网络配置

在 `hardhat.config.js` 中可以配置不同的网络。默认包含：
- `hardhat`: 本地 Hardhat 网络
- `localhost`: 本地节点（端口 8545）

## 使用示例

### 1. 编译合约
```bash
npm run compile
```

### 2. 运行测试
```bash
npm run test
# 或只测试 CPAMM
npx hardhat test test/CPAMM.test.js
```

### 3. 部署并测试
```bash
# 启动本地节点（新终端）
npm run node

# 部署 CPAMM（另一个终端）
npx hardhat run scripts/deployCPAMM.js --network localhost
```

## 测试覆盖

CPAMM 测试包括：
- ✅ 合约部署和初始化
- ✅ 添加流动性（首次和后续）
- ✅ 移除流动性
- ✅ 代币交换（两个方向）
- ✅ 恒定乘积验证
- ✅ 滑点保护
- ✅ 输出数量计算

## 📚 详细文档

### Uniswap V2 文档

#### 学习指南
- [Uniswap V2 学习指南](./v2/UNISWAP_V2_学习指南.md) - 完整的架构学习指南

#### 核心概念
- [手续费机制](./v2/concepts/手续费机制.md) - 0.3% 手续费的计算和分配
- [添加移除流动性](./v2/concepts/添加移除流动性.md) - 流动性操作详解
- [无常损失](./v2/concepts/无常损失.md) - 理解 LP 的风险
- [闪电交换](./v2/concepts/闪电交换.md) - Flash Swaps 功能
- [时间加权平均价格](./v2/concepts/时间加权平均价格.md) - TWAP 机制

#### 核心合约
- [Factory（工厂）合约](./v2/core/Factory（工厂）合约.md) - 工厂合约详解
- [Pair（交易对）合约](./v2/core/Pair（交易对）合约.md) - 交易对合约详解

#### 执行流程
- [Swap 函数对比](./v2/periphery/Swap%20函数对比：swapExactTokensForTokens%20vs%20swapTokensForExactTokens.md) - 两种交换函数的区别
- [代币交换的完整执行流程](./v2/periphery/Uniswap%20V2%20中代币交换的完整执行流程.md) - 交换流程详解

#### 概念文档索引
- [V2 核心概念文档索引](./v2/concepts/README.md) - 所有概念文档的索引和学习路径

### Uniswap V3 文档

#### 学习指南
- [Uniswap V3 学习指南](./v3/UNISWAP_V3_学习指南.md) - 完整的架构学习指南

#### 核心概念
- [Uniswap V3 简介](./v3/concepts/Uniswap%20V3%20简介.md) - V3 整体介绍
- [集中流动性](./v3/concepts/Uniswap%20V3%20的核心创新——集中流动性.md) - V3 的核心创新
- [Tick 与价格表示](./v3/concepts/Uniswap%20V3%20Tick%20与价格表示详解.md) - 价格系统详解
- [流动性计算](./v3/concepts/Uniswap%20V3%20中流动性的计算方法.md) - 流动性计算方法
- [添加流动性案例](./v3/concepts/Uniswap%20V3%20添加流动性案例详解.md) - 实际操作案例
- [单价格区间内的 Swap](./v3/concepts/Uniswap%20V3%20单价格区间内的%20Swap%20详解.md) - 基础交换机制
- [LiquidityNet](./v3/concepts/Uniswap%20V3%20LiquidityNet%20详解.md) - 净流动性概念
- [跨多个 tick 的交换](./v3/concepts/Uniswap%20V3%20中跨多个%20tick%20的交换（Cross%20Tick%20Swap）.md) - 复杂交换机制
- [Tick Bitmap](./v3/concepts/Uniswap%20V3%20Tick%20Bitmap%20详解.md) - Tick 查找机制
- [手续费计算](./v3/concepts/Uniswap%20V3%20手续费计算详解.md) - V3 手续费机制

#### 概念文档索引
- [V3 核心概念文档索引](./v3/concepts/README.md) - 所有概念文档的索引和学习路径

## 🔗 外部资源

- [Hardhat 文档](https://hardhat.org/docs)
- [Uniswap V2 官方文档](https://docs.uniswap.org/contracts/v2/overview)
- [Uniswap V3 官方文档](https://docs.uniswap.org/contracts/v3/overview)
- [恒定乘积做市商原理](https://docs.uniswap.org/protocol/V2/concepts/protocol-overview/how-uniswap-works)

