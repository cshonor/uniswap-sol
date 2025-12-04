// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC20Minimal
/// @dev ERC20 最小接口
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

