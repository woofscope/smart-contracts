const hre = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Adding liquidity with account:", deployer.address);

    // Get the deployed token contract
    const token = await ethers.getContract("AdvancedToken");
    
    // Amount of tokens to add to liquidity (e.g., 100,000 tokens)
    const tokenAmount = ethers.parseEther("100000");
    
    // Amount of ETH to add to liquidity (e.g., 10 ETH)
    const ethAmount = ethers.parseEther("10");

    // Approve router to spend tokens
    console.log("Approving tokens...");
    await token.approve(await token.uniswapV2Router(), tokenAmount);

    // Add liquidity
    console.log("Adding liquidity...");
    await token.addLiquidity(tokenAmount, { value: ethAmount });

    console.log("Liquidity added successfully!");
    console.log("Tokens added:", ethers.formatEther(tokenAmount));
    console.log("ETH added:", ethers.formatEther(ethAmount));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });