// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FullMath
/// @dev 高精度数学运算库，用于避免溢出
library FullMath {
    /// @notice 计算 (a * b) / denominator，使用 512 位中间结果避免溢出
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result (a * b) / denominator
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // 计算 a * b 的 512 位结果
        uint256 prod0; // 低 256 位
        uint256 prod1; // 高 256 位
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // 处理分母为 0 的情况
        require(denominator > 0, "FullMath: DIVISION_BY_ZERO");

        // 确保结果小于 2^256
        require(denominator > prod1, "FullMath: OVERFLOW");

        // 计算 512 位除以 256 位
        assembly {
            // 计算 remainder
            let remainder := mulmod(a, b, denominator)

            // 计算 prod1 / denominator
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)

            // 计算 (prod1 * 2^256 + prod0) / denominator
            let twos := and(add(sub(0, denominator), 1), 7)
            denominator := div(denominator, shl(twos, 1))
            prod0 := div(prod0, denominator)
            prod0 := shr(twos, prod0)

            result := or(prod1, prod0)
        }
    }

    /// @notice 计算 (a * b) / denominator，向上取整
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }

    /// @notice 计算 a / b，向上取整
    function divRoundingUp(uint256 a, uint256 b) internal pure returns (uint256 result) {
        require(b > 0, "FullMath: DIVISION_BY_ZERO");
        result = a / b;
        if (a % b > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}

