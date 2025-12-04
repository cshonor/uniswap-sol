// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./FullMath.sol";
import "./FixedPoint96.sol";

/// @dev 辅助库，用于 uint256 的加法和减法
library UnsafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
}

/// @title SqrtPriceMath
/// @dev 平方根价格相关的数学计算
library SqrtPriceMath {
    using UnsafeMath for uint256;
    /// @notice 根据 token0 的数量计算流动性
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param amount0 token0 的数量
    /// @return liquidity 计算出的流动性
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice 根据 token1 的数量计算流动性
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param amount1 token1 的数量
    /// @return liquidity 计算出的流动性
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice 根据两种代币的数量计算流动性
    /// @param sqrtRatioX96 当前价格的 sqrtPrice (Q96)
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param amount0 token0 的数量
    /// @param amount1 token1 的数量
    /// @return liquidity 计算出的流动性
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            // 当前价格低于区间，全部是 token0
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            // 当前价格在区间内，需要两种代币
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            // 当前价格高于区间，全部是 token1
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @notice 根据流动性计算 token0 的数量
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param liquidity 流动性数量
    /// @return amount0 token0 的数量
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        return
            FullMath.mulDiv(
                uint256(liquidity) << 96,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /// @notice 根据流动性计算 token1 的数量
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param liquidity 流动性数量
    /// @return amount1 token1 的数量
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice 根据流动性计算两种代币的数量
    /// @param sqrtRatioX96 当前价格的 sqrtPrice (Q96)
    /// @param sqrtRatioAX96 价格区间下限的 sqrtPrice (Q96)
    /// @param sqrtRatioBX96 价格区间上限的 sqrtPrice (Q96)
    /// @param liquidity 流动性数量
    /// @return amount0 token0 的数量
    /// @return amount1 token1 的数量
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    /// @notice 根据输入数量计算下一个 sqrtPrice
    /// @param sqrtPX96 当前 sqrtPrice
    /// @param liquidity 流动性
    /// @param amountIn 输入数量
    /// @param zeroForOne 是否 token0 -> token1
    /// @return sqrtQX96 新的 sqrtPrice
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0, "SqrtPriceMath: ZERO_PRICE");
        require(liquidity > 0, "SqrtPriceMath: ZERO_LIQUIDITY");

        return zeroForOne
            ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
            : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @dev 根据 token0 输入计算下一个 sqrtPrice
    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << 96;

        if (add) {
            uint256 product;
            if ((product = amount * sqrtPX96) / amount == sqrtPX96) {
                uint256 denominator = numerator1 + product;
                if (denominator >= numerator1)
                    return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
            }

            return uint160(FullMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96).add(amount)));
        } else {
            uint256 product;
            require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
            uint256 denominator = numerator1 - product;
            return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
        }
    }

    /// @dev 根据 token1 输入计算下一个 sqrtPrice
    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (add) {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? (amount << 96) / liquidity
                    : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
            );

            return uint160(uint256(sqrtPX96).add(quotient));
        } else {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? FullMath.divRoundingUp(amount << 96, liquidity)
                    : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
            );

            require(sqrtPX96 > quotient);
            return uint160(uint256(sqrtPX96).sub(quotient));
        }
    }

    /// @dev 安全转换为 uint128
    function toUint128(uint256 x) private pure returns (uint128) {
        require(x <= type(uint128).max, "SqrtPriceMath: OVERFLOW");
        return uint128(x);
    }
}

