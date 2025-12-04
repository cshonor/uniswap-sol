// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./UniswapV3Pool.sol";

/// @title UniswapV3Factory
/// @dev 工厂合约，用于创建和管理 Uniswap V3 池子
contract UniswapV3Factory {
    /// @dev 手续费层级对应的 tick 间隔
    mapping(uint24 => int24) public feeAmountTickSpacing;
    
    /// @dev 池子地址映射: token0 => token1 => fee => pool
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
    
    /// @dev 所有池子地址列表
    address[] public allPools;

    /// @dev 池子创建事件
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    constructor() {
        // 设置手续费层级对应的 tick 间隔
        feeAmountTickSpacing[500] = 10;   // 0.05% fee
        feeAmountTickSpacing[3000] = 60;  // 0.3% fee
        feeAmountTickSpacing[10000] = 200; // 1% fee
    }

    /// @notice 获取所有池子数量
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice 创建新的池子
    /// @param tokenA 代币 A 地址
    /// @param tokenB 代币 B 地址
    /// @param fee 手续费层级 (500, 3000, 或 10000)
    /// @return pool 新创建的池子地址
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "Factory: ZERO_ADDRESS");
        require(feeAmountTickSpacing[fee] != 0, "Factory: INVALID_FEE");

        // 确保 token0 < token1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(getPool[token0][token1][fee] == address(0), "Factory: POOL_EXISTS");

        int24 tickSpacing = feeAmountTickSpacing[fee];

        // 部署新的池子
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}(
            token0,
            token1,
            fee,
            tickSpacing
        ));

        // 记录池子地址
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // 双向映射
        allPools.push(pool);

        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }
}

