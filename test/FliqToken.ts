import { ethers } from "hardhat"
import { expect } from "chai"

describe("FliqToken", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = await this.signers[0]
        this.stationFactory = this.signers[1]
        this.bob = this.signers[2]
        this.minter = this.signers[3]
        this.bot = this.signers[4]
        this.FliqToken = await ethers.getContractFactory("FliqToken", this.stationFactory)
    })

    beforeEach(async function () {
        this.fliq = await this.FliqToken.deploy(this.governor.address)
        await this.fliq.deployed()
    })

    it("Should set name, symbol, decimals and total supply correctly", async function () {
        expect(await this.fliq.name()).to.be.equal("FlashLiquidity")
        expect(await this.fliq.symbol()).to.be.equal("FLIQ")
        expect(await this.fliq.decimals()).to.be.equal(18)
        expect(await this.fliq.totalSupply()).to.be.equal(ethers.utils.parseUnits("1.0", 26))
    })

    it("Should mint the total supply to Governor", async function () {
        expect(await this.fliq.balanceOf(this.governor.address)).to.be.equal(
            ethers.utils.parseUnits("1.0", 26)
        )
    })

    it("Should allow to burn tokens owned", async function () {
        await this.fliq.connect(this.governor).burn(ethers.utils.parseUnits("5.0", 25))
        expect(await this.fliq.balanceOf(this.governor.address)).to.be.equal(
            ethers.utils.parseUnits("5.0", 25)
        )
        await expect(
            this.fliq.connect(this.bob).burn(ethers.utils.parseUnits("1.0", 18))
        ).to.be.revertedWith("Transaction reverted: function was called with incorrect parameters")
    })
})
