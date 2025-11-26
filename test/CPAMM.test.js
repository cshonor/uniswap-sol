const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("CPAMM - Constant Product AMM", function () {
  async function deployCPAMMFixture() {
    const [deployer, user1, user2] = await ethers.getSigners();

    // 部署代币
    const TokenA = await ethers.getContractFactory("ERC20");
    const tokenA = await TokenA.deploy("Token A", "TKA", 1000000);
    await tokenA.waitForDeployment();

    const TokenB = await ethers.getContractFactory("ERC20");
    const tokenB = await TokenB.deploy("Token B", "TKB", 1000000);
    await tokenB.waitForDeployment();

    // 部署 CPAMM
    const CPAMM = await ethers.getContractFactory("CPAMM");
    const cpamm = await CPAMM.deploy(tokenA.target, tokenB.target);
    await cpamm.waitForDeployment();

    // 给用户分配代币
    const amount = ethers.parseEther("10000");
    await tokenA.transfer(user1.address, amount);
    await tokenB.transfer(user1.address, amount);
    await tokenA.transfer(user2.address, amount);
    await tokenB.transfer(user2.address, amount);

    return { cpamm, tokenA, tokenB, deployer, user1, user2 };
  }

  describe("部署", function () {
    it("应该正确设置代币地址", async function () {
      const { cpamm, tokenA, tokenB } = await loadFixture(deployCPAMMFixture);
      
      expect(await cpamm.token0()).to.equal(tokenA.target);
      expect(await cpamm.token1()).to.equal(tokenB.target);
    });

    it("初始储备量应该为0", async function () {
      const { cpamm } = await loadFixture(deployCPAMMFixture);
      
      const [reserve0, reserve1] = await cpamm.getReserves();
      expect(reserve0).to.equal(0);
      expect(reserve1).to.equal(0);
    });
  });

  describe("添加流动性", function () {
    it("应该能够首次添加流动性", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");

      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);

      await expect(cpamm.connect(user1).addLiquidity(amountA, amountB))
        .to.emit(cpamm, "Mint");

      const [reserve0, reserve1] = await cpamm.getReserves();
      expect(reserve0).to.equal(amountA);
      expect(reserve1).to.equal(amountB);

      const liquidity = await cpamm.balanceOf(user1.address);
      expect(liquidity).to.be.gt(0);
    });

    it("应该能够再次添加流动性", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      const amountA1 = ethers.parseEther("1000");
      const amountB1 = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA1);
      await tokenB.connect(user1).approve(cpamm.target, amountB1);
      await cpamm.connect(user1).addLiquidity(amountA1, amountB1);

      const liquidity1 = await cpamm.balanceOf(user1.address);

      // 再次添加流动性
      const amountA2 = ethers.parseEther("500");
      const amountB2 = ethers.parseEther("1000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA2);
      await tokenB.connect(user1).approve(cpamm.target, amountB2);
      await cpamm.connect(user1).addLiquidity(amountA2, amountB2);

      const liquidity2 = await cpamm.balanceOf(user1.address);
      expect(liquidity2).to.be.gt(liquidity1);
    });
  });

  describe("移除流动性", function () {
    it("应该能够移除流动性", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      // 添加流动性
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);
      await cpamm.connect(user1).addLiquidity(amountA, amountB);

      const liquidity = await cpamm.balanceOf(user1.address);
      const balanceABefore = await tokenA.balanceOf(user1.address);
      const balanceBBefore = await tokenB.balanceOf(user1.address);

      // 移除一半流动性
      await expect(cpamm.connect(user1).removeLiquidity(liquidity / 2n))
        .to.emit(cpamm, "Burn");

      const balanceAAfter = await tokenA.balanceOf(user1.address);
      const balanceBAfter = await tokenB.balanceOf(user1.address);
      
      expect(balanceAAfter).to.be.gt(balanceABefore);
      expect(balanceBAfter).to.be.gt(balanceBBefore);
    });
  });

  describe("交换", function () {
    it("应该能够交换代币（Token A -> Token B）", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      // 添加流动性
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);
      await cpamm.connect(user1).addLiquidity(amountA, amountB);

      // 执行交换
      const swapAmount = ethers.parseEther("100");
      await tokenA.connect(user1).approve(cpamm.target, swapAmount);
      
      const balanceBBefore = await tokenB.balanceOf(user1.address);
      
      await expect(cpamm.connect(user1).swap(tokenA.target, swapAmount, 0, user1.address))
        .to.emit(cpamm, "Swap");

      const balanceBAfter = await tokenB.balanceOf(user1.address);
      expect(balanceBAfter).to.be.gt(balanceBBefore);
    });

    it("应该能够交换代币（Token B -> Token A）", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      // 添加流动性
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);
      await cpamm.connect(user1).addLiquidity(amountA, amountB);

      // 执行交换
      const swapAmount = ethers.parseEther("100");
      await tokenB.connect(user1).approve(cpamm.target, swapAmount);
      
      const balanceABefore = await tokenA.balanceOf(user1.address);
      
      await expect(cpamm.connect(user1).swap(tokenB.target, swapAmount, 0, user1.address))
        .to.emit(cpamm, "Swap");

      const balanceAAfter = await tokenA.balanceOf(user1.address);
      expect(balanceAAfter).to.be.gt(balanceABefore);
    });

    it("应该保持恒定乘积 k = x * y", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      // 添加流动性
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);
      await cpamm.connect(user1).addLiquidity(amountA, amountB);

      const [reserve0Before, reserve1Before] = await cpamm.getReserves();
      const kBefore = reserve0Before * reserve1Before;

      // 执行交换
      const swapAmount = ethers.parseEther("100");
      await tokenA.connect(user1).approve(cpamm.target, swapAmount);
      await cpamm.connect(user1).swap(tokenA.target, swapAmount, 0, user1.address);

      const [reserve0After, reserve1After] = await cpamm.getReserves();
      const kAfter = reserve0After * reserve1After;

      // k 应该增加（因为交换有手续费效应，这里简化版本k会略微增加）
      // 在实际实现中，如果有手续费，k会保持不变或略微增加
      expect(kAfter).to.be.gte(kBefore);
    });

    it("应该拒绝滑点过大的交换", async function () {
      const { cpamm, tokenA, tokenB, user1 } = await loadFixture(deployCPAMMFixture);
      
      // 添加流动性
      const amountA = ethers.parseEther("1000");
      const amountB = ethers.parseEther("2000");
      
      await tokenA.connect(user1).approve(cpamm.target, amountA);
      await tokenB.connect(user1).approve(cpamm.target, amountB);
      await cpamm.connect(user1).addLiquidity(amountA, amountB);

      // 尝试交换，但要求过高的最小输出
      const swapAmount = ethers.parseEther("100");
      await tokenA.connect(user1).approve(cpamm.target, swapAmount);
      
      const minAmountOut = ethers.parseEther("10000"); // 不合理的滑点保护
      
      await expect(
        cpamm.connect(user1).swap(tokenA.target, swapAmount, minAmountOut, user1.address)
      ).to.be.revertedWith("Insufficient output amount");
    });
  });

  describe("getAmountOut", function () {
    it("应该正确计算输出数量", async function () {
      const { cpamm } = await loadFixture(deployCPAMMFixture);
      
      const reserveIn = ethers.parseEther("1000");
      const reserveOut = ethers.parseEther("2000");
      const amountIn = ethers.parseEther("100");

      const amountOut = await cpamm.getAmountOut(amountIn, reserveIn, reserveOut);
      
      // 根据公式: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
      // amountOut = (100 * 2000) / (1000 + 100) = 200000 / 1100 ≈ 181.81
      const expected = (amountIn * reserveOut) / (reserveIn + amountIn);
      expect(amountOut).to.equal(expected);
    });

    it("应该拒绝无效输入", async function () {
      const { cpamm } = await loadFixture(deployCPAMMFixture);
      
      await expect(
        cpamm.getAmountOut(0, ethers.parseEther("1000"), ethers.parseEther("2000"))
      ).to.be.revertedWith("Insufficient input amount");

      await expect(
        cpamm.getAmountOut(ethers.parseEther("100"), 0, ethers.parseEther("2000"))
      ).to.be.revertedWith("Insufficient liquidity");
    });
  });
});

