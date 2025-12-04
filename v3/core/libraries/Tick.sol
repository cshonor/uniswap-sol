// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LiquidityMath.sol";

/// @title Tick
/// @dev Tick 信息结构体
library Tick {
    struct Info {
        uint128 liquidityGross; // 该 tick 的总流动性
        int128 liquidityNet;    // 该 tick 的净流动性变化
        uint256 feeGrowthOutside0X128; // token0 的手续费累积
        uint256 feeGrowthOutside1X128; // token1 的手续费累积
        int56 tickCumulativeOutside;   // tick 累积值
        uint160 secondsPerLiquidityOutsideX128; // 每秒流动性
        uint32 secondsOutside;         // 在区间外的时间
        bool initialized;              // 是否已初始化
    }

    /// @notice 更新 tick 信息
    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int128 liquidityDelta,
        bool upper
    ) internal returns (bool flipped) {
        Info storage info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= type(uint128).max, "Tick: OVERFLOW");

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;
        info.liquidityNet = upper
            ? int128(int256(info.liquidityNet) - liquidityDelta)
            : int128(int256(info.liquidityNet) + liquidityDelta);
    }

    /// @notice 清除 tick 信息
    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }
}

