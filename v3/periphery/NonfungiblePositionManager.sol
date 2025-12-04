// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IERC721.sol";
import "../core/interfaces/IUniswapV3Pool.sol";
import "../core/interfaces/IERC20Minimal.sol";
import "../core/UniswapV3Factory.sol";
import "../core/libraries/TickMath.sol";
import "../core/libraries/SqrtPriceMath.sol";
import "./libraries/PoolAddress.sol";

/// @title NonfungiblePositionManager
/// @dev NFT 仓位管理器，管理流动性仓位
contract NonfungiblePositionManager is INonfungiblePositionManager {
    UniswapV3Factory public immutable factory;

    /// @dev 仓位信息
    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @dev 仓位映射
    mapping(uint256 => Position) public positions;

    /// @dev NFT 相关
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _nextTokenId = 1;
    string public name = "Uniswap V3 Positions NFT";
    string public symbol = "UNI-V3-POS";

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(address _factory) {
        factory = UniswapV3Factory(_factory);
    }

    /// @notice 创建新的流动性仓位
    function mint(MintParams calldata params)
        external
        payable
        override
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(params.deadline >= block.timestamp, "PositionManager: EXPIRED");

        IUniswapV3Pool pool;
        (pool, amount0, amount1, liquidity) = _addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        // 铸造 NFT
        tokenId = _nextTokenId++;
        _mint(params.recipient, tokenId);

        // 存储仓位信息
        positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }

    /// @notice 增加流动性
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(params.deadline >= block.timestamp, "PositionManager: EXPIRED");
        require(_owners[params.tokenId] == msg.sender, "PositionManager: NOT_AUTHORIZED");

        Position storage position = positions[params.tokenId];

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                position.token0,
                position.token1,
                position.fee
            )
        );

        (amount0, amount1, liquidity) = _addLiquidity(
            AddLiquidityParams({
                token0: position.token0,
                token1: position.token1,
                fee: position.fee,
                recipient: address(this),
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        position.liquidity += liquidity;
    }

    /// @notice 减少流动性
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "PositionManager: EXPIRED");
        require(_owners[params.tokenId] == msg.sender, "PositionManager: NOT_AUTHORIZED");

        Position storage position = positions[params.tokenId];

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                position.token0,
                position.token1,
                position.fee
            )
        );

        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "PositionManager: SLIPPAGE");

        position.liquidity -= params.liquidity;
    }

    /// @notice 收集手续费
    function collect(CollectParams calldata params) external payable override returns (uint256 amount0, uint256 amount1) {
        require(_owners[params.tokenId] == msg.sender, "PositionManager: NOT_AUTHORIZED");

        Position storage position = positions[params.tokenId];

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                position.token0,
                position.token1,
                position.fee
            )
        );

        (amount0, amount1) = pool.collect(
            params.recipient,
            position.tickLower,
            position.tickUpper,
            params.amount0Max,
            params.amount1Max
        );
    }

    /// @dev 内部函数：添加流动性
    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function _addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            IUniswapV3Pool pool,
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity
        )
    {
        // 获取或创建池子
        pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));
        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(factory.createPool(params.token0, params.token1, params.fee));
        }

        // 如果池子未初始化，需要初始化
        if (pool.slot0().sqrtPriceX96 == 0) {
            // 需要先初始化池子（这里简化处理）
            // 实际应该根据当前市场价格初始化
        }

        // 计算流动性
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

        liquidity = SqrtPriceMath.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            params.amount0Desired,
            params.amount1Desired
        );

        // 调用池子的 mint 函数
        (amount0, amount1) = pool.mint(params.recipient, params.tickLower, params.tickUpper, liquidity, "");

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "PositionManager: SLIPPAGE");
    }

    /// @dev ERC721 实现
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "ERC721: mint to zero address");
        require(_owners[tokenId] == address(0), "ERC721: token already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function approve(address to, uint256 tokenId) public override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "ERC721: approve caller is not owner nor approved for all");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_owners[tokenId] != address(0), "ERC721: approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != msg.sender, "ERC721: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_owners[tokenId] != address(0), "ERC721: operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to zero address");

        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _approve(address to, uint256 tokenId) internal {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}

