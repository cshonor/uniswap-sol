# Uniswap V3 Periphery 合约

本目录包含 Uniswap V3 的外围合约实现。

## 目录结构

```
periphery/
├── interfaces/        # 接口定义
│   ├── IERC721.sol
│   └── INonfungiblePositionManager.sol
├── libraries/         # 工具库
│   └── PoolAddress.sol    # 池子地址计算
├── NonfungiblePositionManager.sol  # NFT 仓位管理器
└── SwapRouter.sol                  # 交换路由
```

## 核心合约

### NonfungiblePositionManager

NFT 仓位管理器，用于管理流动性仓位。每个流动性仓位是一个 NFT。

**主要功能：**
- `mint(params)`: 创建新的流动性仓位（铸造 NFT）
- `increaseLiquidity(params)`: 增加现有仓位的流动性
- `decreaseLiquidity(params)`: 减少仓位的流动性
- `collect(params)`: 收集手续费

**MintParams 结构：**
```solidity
struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;      // 价格区间下限
    int24 tickUpper;      // 价格区间上限
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;   // 滑点保护
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
}
```

### SwapRouter

交换路由合约，用于执行代币交换。

**主要功能：**
- `exactInputSingle(params)`: 单跳交换
- `exactInput(params)`: 多跳交换（简化实现）

**ExactInputSingleParams 结构：**
```solidity
struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;  // 滑点保护
    uint160 sqrtPriceLimitX96;
}
```

## 使用示例

### 1. 部署合约

```solidity
UniswapV3Factory factory = new UniswapV3Factory();
NonfungiblePositionManager nftManager = new NonfungiblePositionManager(address(factory));
SwapRouter router = new SwapRouter(address(factory));
```

### 2. 创建流动性仓位

```solidity
INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
    token0: tokenA,
    token1: tokenB,
    fee: 3000,
    tickLower: -60,
    tickUpper: 60,
    amount0Desired: 1000e18,
    amount1Desired: 2000e18,
    amount0Min: 900e18,
    amount1Min: 1800e18,
    recipient: msg.sender,
    deadline: block.timestamp + 3600
});

(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
    nftManager.mint(params);
```

### 3. 增加流动性

```solidity
INonfungiblePositionManager.IncreaseLiquidityParams memory params = 
    INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: 500e18,
        amount1Desired: 1000e18,
        amount0Min: 450e18,
        amount1Min: 900e18,
        deadline: block.timestamp + 3600
    });

(uint128 liquidity, uint256 amount0, uint256 amount1) = 
    nftManager.increaseLiquidity(params);
```

### 4. 执行交换

```solidity
ISwapRouter.ExactInputSingleParams memory params = 
    ISwapRouter.ExactInputSingleParams({
        tokenIn: tokenA,
        tokenOut: tokenB,
        fee: 3000,
        recipient: msg.sender,
        deadline: block.timestamp + 3600,
        amountIn: 100e18,
        amountOutMinimum: 190e18,
        sqrtPriceLimitX96: 0
    });

uint256 amountOut = router.exactInputSingle(params);
```

### 5. 收集手续费

```solidity
INonfungiblePositionManager.CollectParams memory params = 
    INonfungiblePositionManager.CollectParams({
        tokenId: tokenId,
        recipient: msg.sender,
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
    });

(uint256 amount0, uint256 amount1) = nftManager.collect(params);
```

## 注意事项

1. **NFT 管理**：每个流动性仓位是一个 ERC721 NFT，可以转账和交易
2. **滑点保护**：所有操作都包含最小/最大数量参数，用于滑点保护
3. **截止时间**：所有操作都需要设置 deadline，防止过期交易
4. **价格区间**：LP 需要选择合适的 tickLower 和 tickUpper 来提供流动性

