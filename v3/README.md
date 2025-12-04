# Uniswap V3 模块

本模块实现 Uniswap V3 的核心架构，包括集中流动性、NFT 仓位管理等特性。

## 📋 目录

- [核心特性](#核心特性)
- [架构概述](#架构概述)
- [文件夹结构](#文件夹结构)
- [与 V2 的区别](#与-v2-的区别)
- [快速开始](#快速开始)

## 核心特性

### 1. 集中流动性（Concentrated Liquidity）
- LP 可以选择价格区间提供流动性
- 资本效率最高可达 4000 倍
- 流动性只在选定价格区间内有效

### 2. NFT 仓位管理
- 每个流动性仓位是一个 ERC721 NFT
- 每个仓位有独立的参数（价格区间、流动性等）
- 更灵活的流动性管理

### 3. 多层级手续费
- **0.05%**：稳定币对（如 USDC/USDT）
- **0.3%**：常见交易对（如 ETH/USDC）
- **1%**：非常规/高风险代币对

### 4. Tick 系统
- 价格被离散化为 ticks
- 精确的价格计算和流动性管理
- 高效的 tick 查找算法

## 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                    Uniswap V3 架构                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │   Core（核心）    │         │  Periphery（外围）│         │
│  │                  │         │                  │         │
│  │  ┌────────────┐  │         │  ┌────────────┐  │         │
│  │  │  Factory   │  │────────▶│  │PositionMgr │  │         │
│  │  └─────┬──────┘  │         │  │  (NFT)     │  │         │
│  │        │         │         │  └────────────┘  │         │
│  │        │ 创建    │         │  ┌────────────┐  │         │
│  │        ▼         │         │  │SwapRouter  │  │         │
│  │  ┌────────────┐  │         │  └────────────┘  │         │
│  │  │    Pool    │  │         │                  │         │
│  │  │  (Tick)    │  │         │                  │         │
│  │  └────────────┘  │         │                  │         │
│  │                  │         │                  │         │
│  └──────────────────┘         └──────────────────┘         │
│                                                              │
│  不可升级、安全性高               可升级、功能丰富              │
└─────────────────────────────────────────────────────────────┘
```

## 文件夹结构

```
v3/
├── core/                              # 核心合约（Core）
│   ├── UniswapV3Pool.sol            # 交易池合约（管理流动性）
│   ├── UniswapV3Factory.sol         # 工厂合约
│   ├── libraries/                    # 工具库
│   │   ├── TickMath.sol            # Tick 和价格转换
│   │   ├── SqrtPriceMath.sol       # 平方根价格计算
│   │   ├── LiquidityMath.sol       # 流动性计算
│   │   └── FullMath.sol            # 数学运算
│   └── interfaces/
│       ├── IUniswapV3Pool.sol
│       └── IUniswapV3Factory.sol
├── periphery/                         # 外围合约（Periphery）
│   ├── NonfungiblePositionManager.sol # NFT 仓位管理器
│   ├── SwapRouter.sol                # 交换路由
│   └── libraries/
│       ├── PoolAddress.sol          # 池子地址计算
│       └── Position.sol             # 仓位管理
├── test/                              # 测试文件
│   ├── UniswapV3Pool.test.js
│   └── PositionManager.test.js
├── README.md                          # 本文件
└── UNISWAP_V3_学习指南.md            # 详细学习指南
```

## 与 V2 的区别

| 特性 | V2 | V3 |
|------|----|----|
| **流动性分布** | 全价格区间均匀分布 | 可选择价格区间集中 |
| **LP Token** | ERC20 代币 | ERC721 NFT |
| **手续费** | 单一 (0.3%) | 三个层级 (0.05%, 0.3%, 1%) |
| **价格表示** | 储备量比例 | 平方根价格 + Tick |
| **资本效率** | 基础 | 最高 4000 倍 |
| **复杂度** | 简单 | 复杂 |
| **Gas 成本** | 较低 | 较高 |

### 关键区别详解

#### 1. 流动性分布

**V2**：
```
价格: 0 ────────────────────────────────────> ∞
流动性: ████████████████████████████████
```
- LP 需要提供两种代币，比例固定
- 流动性在整个价格区间内均匀分布

**V3**：
```
价格: 0 ────────────────────────────────────> ∞
      [区间1: p1-p2]    [区间2: p3-p4]
流动性: ████                    ████
```
- LP 可以选择价格区间
- 只在选定区间内提供流动性

#### 2. 流动性代币

**V2**：使用 ERC20 LP Token
- 每个 LP 获得相同比例的代币
- 可以转账、交易

**V3**：使用 ERC721 NFT
- 每个仓位是一个独立的 NFT
- 每个仓位有独特的参数

## 核心合约说明

### Core 合约

#### UniswapV3Pool
交易池合约，管理单个交易对的所有流动性。

**核心功能**：
- 存储所有 tick 的流动性信息
- 执行代币交换
- 管理流动性添加/移除
- 累积和分配手续费

**关键数据结构**：
```solidity
struct Slot0 {
    uint160 sqrtPriceX96;  // 当前价格的平方根
    int24 tick;            // 当前 tick
}

struct Info {
    uint128 liquidity;     // tick 的流动性
}

mapping(int24 => Tick.Info) public ticks;
mapping(int16 => uint256) public tickBitmap;
```

#### UniswapV3Factory
工厂合约，创建和管理所有交易池。

**核心功能**：
- 创建新的交易池（支持多个手续费层级）
- 查询已存在的池子地址
- 管理所有池子列表

### Periphery 合约

#### NonfungiblePositionManager
NFT 仓位管理器，提供用户友好的流动性管理接口。

**核心功能**：
- 创建新的流动性仓位（mint NFT）
- 增加/减少流动性
- 收集手续费
- 管理仓位参数

#### SwapRouter
交换路由，执行代币交换。

**核心功能**：
- 精确输入/输出交换
- 多跳交换
- 滑点保护

## 快速开始

### 1. 编译合约

```bash
npx hardhat compile
```

### 2. 运行测试

```bash
npx hardhat test v3/test/
```

### 3. 部署合约

```bash
# 部署 Factory
npx hardhat run v3/scripts/deployFactory.js --network localhost

# 部署 PositionManager
npx hardhat run v3/scripts/deployPositionManager.js --network localhost
```

## 学习资源

- **[UNISWAP_V3_学习指南.md](./UNISWAP_V3_学习指南.md)** - 详细的学习指南
- [Uniswap V3 官方文档](https://docs.uniswap.org/contracts/v3/overview)
- [Uniswap V3 白皮书](https://uniswap.org/whitepaper-v3.pdf)

## 工作流程示例

### 添加流动性

```
用户调用 PositionManager.mint()
  ↓
计算价格区间对应的 ticks
  ↓
Factory.getPool() 获取/创建池子
  ↓
Pool.mint() 添加流动性
  ↓
铸造 NFT 给用户
```

### 执行交换

```
用户调用 SwapRouter.swapExactInputSingle()
  ↓
Router 查询 Factory 获取池子地址
  ↓
Pool.swap() 执行交换
  ↓
遍历 ticks，更新价格
  ↓
转移代币给用户
```

## 注意事项

1. **Gas 成本**：V3 的 Gas 成本比 V2 高，因为需要处理 ticks 和更复杂的计算
2. **价格区间选择**：LP 需要仔细选择价格区间，价格超出区间后流动性不再有效
3. **无常损失**：集中流动性可能增加无常损失的风险
4. **复杂度**：V3 的实现比 V2 复杂得多，需要深入理解 Tick 系统和数学公式

## 开发状态

- ✅ 学习指南文档
- ⏳ Core 合约实现（进行中）
- ⏳ Periphery 合约实现
- ⏳ 测试用例
- ⏳ 部署脚本

