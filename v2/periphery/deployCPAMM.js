const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // 部署两个 ERC20 代币
  console.log("\n1. Deploying ERC20 tokens...");
  const TokenA = await hre.ethers.getContractFactory("ERC20");
  const tokenA = await TokenA.deploy("Token A", "TKA", 1000000); // 100万代币
  await tokenA.waitForDeployment();
  console.log("Token A deployed to:", tokenA.target);

  const TokenB = await hre.ethers.getContractFactory("ERC20");
  const tokenB = await TokenB.deploy("Token B", "TKB", 1000000); // 100万代币
  await tokenB.waitForDeployment();
  console.log("Token B deployed to:", tokenB.target);

  // 部署 CPAMM 合约
  console.log("\n2. Deploying CPAMM...");
  const CPAMM = await hre.ethers.getContractFactory("CPAMM");
  const cpamm = await CPAMM.deploy(tokenA.target, tokenB.target);
  await cpamm.waitForDeployment();
  console.log("CPAMM deployed to:", cpamm.target);

  // 添加初始流动性
  console.log("\n3. Adding initial liquidity...");
  const amountA = hre.ethers.parseEther("1000"); // 1000 Token A
  const amountB = hre.ethers.parseEther("2000"); // 2000 Token B

  // 批准代币
  await tokenA.approve(cpamm.target, amountA);
  await tokenB.approve(cpamm.target, amountB);

  // 添加流动性
  const tx = await cpamm.addLiquidity(amountA, amountB);
  await tx.wait();
  console.log("Initial liquidity added!");
  console.log("  Token A:", hre.ethers.formatEther(amountA));
  console.log("  Token B:", hre.ethers.formatEther(amountB));

  // 获取储备量
  const [reserve0, reserve1] = await cpamm.getReserves();
  console.log("\n4. Pool reserves:");
  console.log("  Reserve0 (Token A):", hre.ethers.formatEther(reserve0));
  console.log("  Reserve1 (Token B):", hre.ethers.formatEther(reserve1));
  console.log("  Constant product (k):", (reserve0 * reserve1).toString());

  console.log("\n✅ Deployment completed!");
  console.log("\nContract addresses:");
  console.log("  Token A:", tokenA.target);
  console.log("  Token B:", tokenB.target);
  console.log("  CPAMM:", cpamm.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

