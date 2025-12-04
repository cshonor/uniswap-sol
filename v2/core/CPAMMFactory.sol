// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./CPAMM.sol";

/**
 * @title CPAMMFactory - Factory Contract for Creating CPAMM Pairs
 * @dev 工厂合约，用于创建和管理多个 CPAMM 交易对
 * 类似 Uniswap V2 Factory 的核心功能
 */
contract CPAMMFactory {
    // 存储所有已创建的交易对地址
    address[] public allPairs;
    
    // 映射：tokenA => tokenB => pairAddress
    // 用于快速查找两个代币之间的交易对地址
    mapping(address => mapping(address => address)) public getPair;
    
    // 事件：当新的交易对被创建时触发
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );
    
    /**
     * @dev 获取所有已创建的交易对数量
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
    
    /**
     * @dev 创建新的交易对
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @return pair 新创建的交易对地址
     * 
     * 功能说明：
     * 1. 验证两个代币地址不同且不为零地址
     * 2. 确保代币对的顺序（token0 < token1），避免重复创建
     * 3. 检查该交易对是否已存在
     * 4. 部署新的 CPAMM 合约
     * 5. 记录交易对地址并触发事件
     */
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair)
    {
        require(tokenA != tokenB, "CPAMM: IDENTICAL_ADDRESSES");
        require(tokenA != address(0), "CPAMM: ZERO_ADDRESS");
        require(tokenB != address(0), "CPAMM: ZERO_ADDRESS");
        
        // 确保 token0 < token1，这样同一个交易对只会有一个顺序
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        
        // 检查交易对是否已存在
        require(getPair[token0][token1] == address(0), "CPAMM: PAIR_EXISTS");
        
        // 部署新的 CPAMM 合约
        // 注意：这里使用标准部署，实际 Uniswap V2 使用 CREATE2 确保地址可预测
        // 为了简化，我们先使用 new 关键字
        CPAMM newPair = new CPAMM(token0, token1);
        pair = address(newPair);
        
        // 记录交易对地址
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // 双向映射，方便查找
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    /**
     * @dev 根据两个代币地址查找交易对（支持任意顺序）
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @return pair 交易对地址，如果不存在则返回零地址
     */
    function pairFor(address tokenA, address tokenB)
        external
        view
        returns (address pair)
    {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        
        pair = getPair[token0][token1];
    }
}

