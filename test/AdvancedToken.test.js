const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AdvancedToken", function () {
    let token;
    let owner;
    let addr1;
    let addr2;
    let tokenConfig;
    const FEE_WALLET = "0x1BfA43fF53c667bed28231b404d025D50f1488F6";
    const BASE_DEPLOYMENT_FEE = ethers.parseEther("0.01");
    const FEATURE_FEE = ethers.parseEther("0.05");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        tokenConfig = [
            "Advanced Token",
            "ADV",
            18,
            1000000,
            10000000,
            true,                      // mintable
            false,                     // pausable
            60,
            ethers.parseEther("1000000"),
            ethers.parseEther("100000"),
            false,
            ethers.ZeroAddress
        ];
    });

    describe("Deployment Fees", function () {
        it("Should calculate correct deployment fee for different configurations", async function () {
            const Token = await ethers.getContractFactory("AdvancedToken");
            
            // Base fee + mintable + limits (no pausable)
            let fee = await Token.attach(ethers.ZeroAddress).calculateDeploymentFee(true, false, true);
            expect(fee).to.equal(BASE_DEPLOYMENT_FEE.add(FEATURE_FEE.mul(2)));

            // Base fee only (no features)
            fee = await Token.attach(ethers.ZeroAddress).calculateDeploymentFee(false, false, false);
            expect(fee).to.equal(BASE_DEPLOYMENT_FEE);

            // All features enabled
            fee = await Token.attach(ethers.ZeroAddress).calculateDeploymentFee(true, true, true);
            expect(fee).to.equal(BASE_DEPLOYMENT_FEE.add(FEATURE_FEE.mul(3)));
        });

        it("Should require correct deployment fee", async function () {
            const Token = await ethers.getContractFactory("AdvancedToken");
            
            // Calculate required fee
            const requiredFee = await Token.attach(ethers.ZeroAddress).calculateDeploymentFee(
                tokenConfig[5],
                tokenConfig[6],
                true
            );

            // Should fail with insufficient fee
            await expect(Token.deploy(tokenConfig, { value: requiredFee.sub(1) }))
                .to.be.revertedWith("Insufficient deployment fee");

            // Should succeed with exact fee
            const token = await Token.deploy(tokenConfig, { value: requiredFee });
            await token.waitForDeployment();
            expect(await ethers.provider.getBalance(FEE_WALLET)).to.equal(requiredFee);
        });
    });

    // Previous test cases remain unchanged...
    // [Previous test cases continue here...]
});