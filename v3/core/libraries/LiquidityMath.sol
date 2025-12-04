// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LiquidityMath
/// @dev 流动性相关的数学运算
library LiquidityMath {
    /// @notice 添加流动性
    /// @param x 当前流动性
    /// @param y 要添加的流动性
    /// @return z 结果流动性
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            require((z = x - uint128(-y)) < x, "LiquidityMath: UNDERFLOW");
        } else {
            require((z = x + uint128(y)) >= x, "LiquidityMath: OVERFLOW");
        }
    }
}

