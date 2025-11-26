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

