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
├── hardhat.config.js   # Hardhat 配置文件
└── package.json
```

## CPAMM 核心功能

### 1. 添加流动性 (`addLiquidity`)
向流动性池添加两种代币，获得流动性代币（LP tokens）。

```solidity
cpamm.addLiquidity(amount0, amount1);
```

### 2. 移除流动性 (`removeLiquidity`)
销毁流动性代币，取回对应的两种代币。

```solidity
cpamm.removeLiquidity(liquidity);
```

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

## 更多信息

- [Hardhat 文档](https://hardhat.org/docs)
- [Uniswap V2 文档](https://docs.uniswap.org/contracts/v2/overview)
- [恒定乘积做市商原理](https://docs.uniswap.org/protocol/V2/concepts/protocol-overview/how-uniswap-works)

