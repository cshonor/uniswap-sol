# Uniswap V2 模块

本模块按照 Uniswap V2 的架构模式组织，分为 **Core**（核心）和 **Periphery**（外围）两部分。

## 文件夹结构

```
v2/
├── core/                           # 核心合约（Core）
│   ├── CPAMM.sol                  # 交易对合约（类似 Uniswap V2 Pair）
│   └── CPAMMFactory.sol           # 工厂合约（类似 Uniswap V2 Factory）
├── periphery/                      # 外围合约和工具（Periphery）
│   ├── CPAMMRouter.sol           # 路由合约（类似 Uniswap V2 Router）
│   └── deployCPAMM.js            # 部署脚本
├── test/                           # 测试文件
│   └── CPAMM.test.js             # CPAMM 合约测试
├── README.md                       # 本文件
└── UNISWAP_V2_学习指南.md         # 详细学习指南
```

## 架构说明

### Core（核心）

核心合约包含系统最基础的、不可升级的智能合约逻辑。

#### 1. CPAMM.sol - 交易对合约
类似 Uniswap V2 的 `Pair` 合约，每个交易对对应一个实例。

**功能**：
- 实现 `x * y = k` 恒定乘积公式
- 管理流动性池（添加/移除流动性）
- 执行代币交换
- 铸造流动性代币（LP tokens）

**关键函数**：
- `addLiquidity()` - 添加流动性
- `removeLiquidity()` - 移除流动性
- `swap()` - 代币交换
- `getAmountOut()` - 计算输出数量

#### 2. CPAMMFactory.sol - 工厂合约
类似 Uniswap V2 的 `Factory` 合约，用于创建和管理交易对。

**功能**：
- 创建新的交易对
- 查询已存在的交易对地址
- 管理所有交易对列表

**关键函数**：
- `createPair()` - 创建新的交易对
- `getPair()` - 查询交易对地址
- `allPairs()` - 获取所有交易对列表

### Periphery（外围）

外围合约和脚本提供更高级的功能和便利接口。

#### 1. CPAMMRouter.sol - 路由合约
类似 Uniswap V2 的 `Router` 合约，提供用户友好的接口。

**功能**：
- 智能添加流动性（自动计算最优比例）
- 移除流动性（支持滑点保护）
- 代币交换（支持多跳交换）
- 查询函数（计算交换数量）

**关键函数**：
- `addLiquidity()` - 智能添加流动性
- `removeLiquidity()` - 移除流动性
- `swapExactTokensForTokens()` - 精确输入交换
- `getAmountsOut()` - 查询输出数量

#### 2. deployCPAMM.js - 部署脚本
- 部署 ERC20 测试代币
- 部署 CPAMM 合约
- 添加初始流动性

## 使用说明

### 编译合约

```bash
# 从项目根目录运行
npx hardhat compile
```

### 运行测试

```bash
# 测试 CPAMM 核心功能
npx hardhat test v2/test/CPAMM.test.js
```

### 部署合约

```bash
# 部署 CPAMM 到本地网络
npx hardhat run v2/periphery/deployCPAMM.js --network localhost
```

## 三个合约的关系

```
用户
  ↓
Router (用户友好的接口)
  ↓
Factory (创建和管理交易对)
  ↓
Pair/CPAMM (实际的流动性池)
```

### 工作流程示例

**场景：用户想要交换代币**

1. 用户调用 `Router.swapExactTokensForTokens()`
2. Router 查询 Factory 获取交易对地址
3. Router 调用 Pair 的 `swap()` 函数
4. Pair 执行交换并转移代币

**场景：用户想要添加流动性**

1. 用户调用 `Router.addLiquidity()`
2. Router 检查交易对是否存在，不存在则通过 Factory 创建
3. Router 计算最优代币比例
4. Router 调用 Pair 的 `addLiquidity()` 函数
5. Pair 铸造 LP tokens 给用户

## 学习资源

- **[UNISWAP_V2_学习指南.md](./UNISWAP_V2_学习指南.md)** - 详细的学习指南，包含：
  - 架构概述
  - 三个合约的详细说明
  - 关键概念解析
  - 交互流程示例
  - 代码解析

## 快速开始

### 1. 编译所有合约

```bash
npx hardhat compile
```

### 2. 运行测试

```bash
# 测试 CPAMM 核心功能
npx hardhat test v2/test/CPAMM.test.js
```

### 3. 部署到本地网络

```bash
# 启动本地节点
npx hardhat node

# 部署合约（另一个终端）
npx hardhat run v2/periphery/deployCPAMM.js --network localhost
```

## 合约地址说明

在部署后，你会得到：
- **Factory 地址**：用于创建和管理交易对
- **Router 地址**：用户交互的主要接口
- **Pair 地址**：每个代币对都有一个 Pair 地址（由 Factory 创建）

