const hre = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const tokenConfig = [
        "Advanced Token",           // name
        "ADV",                      // symbol
        18,                        // decimals
        1000000,                   // initialSupply
        10000000,                  // maxSupply
        true,                      // mintable
        false,                     // pausable
        60,                        // cooldownTime
        ethers.parseEther("1000000"), // maxWalletBalance
        ethers.parseEther("100000"),  // maxTransactionAmount
        false,                     // enableTrading
        ethers.ZeroAddress         // routerAddress
    ];

    // Calculate deployment fee
    const Token = await ethers.getContractFactory("AdvancedToken");
    const deploymentFee = await Token.attach(ethers.ZeroAddress).calculateDeploymentFee(
        tokenConfig[5], // mintable
        tokenConfig[6], // pausable
        true           // limitsEnabled is always true initially
    );

    console.log("Required deployment fee:", ethers.formatEther(deploymentFee), "ETH");

    const token = await Token.deploy(
        tokenConfig,
        { value: deploymentFee }
    );
    
    await token.waitForDeployment();
    console.log("Token deployed to:", await token.getAddress());
    console.log("Total deployment fee sent:", ethers.formatEther(deploymentFee), "ETH");
    console.log("Fee sent to:", FEE_WALLET);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });