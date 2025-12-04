// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FixedPoint96
/// @dev 固定点数常量，Q96 格式表示
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000; // 2^96
}

