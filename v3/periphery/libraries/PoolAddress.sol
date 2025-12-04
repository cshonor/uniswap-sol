// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PoolAddress
/// @dev 计算池子地址的工具库
library PoolAddress {
    /// @notice 计算池子的 CREATE2 地址
    function computeAddress(
        address factory,
        address token0,
        address token1,
        uint24 fee
    ) internal pure returns (address pool) {
        require(token0 < token1, "PoolAddress: TOKEN_ORDER");
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encode(token0, token1, fee)),
                            hex"e34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54" // UniswapV3Pool init code hash
                        )
                    )
                )
            )
        );
    }
}

