// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BitMath.sol";

/// @title TickBitmap
/// @dev Tick 位图，用于快速查找下一个有流动性的 tick
library TickBitmap {
    /// @notice 计算 tick 对应的 word 位置
    /// @param tick tick 值
    /// @param tickSpacing tick 间隔
    /// @return wordPos word 的位置
    /// @return bitPos bit 在 word 中的位置
    function position(int24 tick, int24 tickSpacing) internal pure returns (int16 wordPos, uint8 bitPos) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // 向下取整
        wordPos = int16(compressed >> 8);
        bitPos = uint8(uint24(compressed % 256));
    }

    /// @notice 翻转 tick 的位
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        (int16 wordPos, uint8 bitPos) = position(tick, tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice 查找下一个已初始化的 tick
    /// @param self tick 位图
    /// @param tick 起始 tick
    /// @param tickSpacing tick 间隔
    /// @param lte 是否查找小于等于的 tick
    /// @return next 下一个 tick
    /// @return initialized 是否已初始化
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed * tickSpacing, tickSpacing);
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            (int16 wordPos, uint8 bitPos) = position((compressed + 1) * tickSpacing, tickSpacing);
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
                : (compressed + 1 + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
        }
    }
}

