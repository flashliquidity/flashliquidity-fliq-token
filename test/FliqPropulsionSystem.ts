import { ethers } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, FACTORY_ADDR, ROUTER_ADDR, DAI_ADDR } from "./utilities"

const factoryJson = require("./core-deployments/FlashLiquidityFactory.json")
const routerJson = require("./core-deployments/FlashLiquidityRouter.json")

describe("FliqPropulsionSystem", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.transferGovernanceDelay = 60
        this.bob = this.signers[1]
        this.minter = this.signers[2]
        this.farm = this.signers[3]
        this.bastion = this.signers[4]
        this.FliqToken = await ethers.getContractFactory("FliqToken", this.stationFactory)
        this.FliqPropulsionSystem = await ethers.getContractFactory("FliqPropulsionSystem")
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    })

    beforeEach(async function () {
        this.factory = new ethers.Contract(FACTORY_ADDR, factoryJson.abi, this.governor)
        this.router = new ethers.Contract(ROUTER_ADDR, routerJson.abi, this.governor)
        this.fliq = await this.FliqToken.deploy(this.governor.address)
        await this.fliq.deployed()
        this.fliqPropulsion = await this.FliqPropulsionSystem.deploy(
            this.governor.address,
            this.factory.address,
            this.fliq.address,
            DAI_ADDR,
            this.transferGovernanceDelay
        )
        await this.fliqPropulsion.deployed()
        this.token1 = await this.ERC20Mock.deploy("Mock token", "MOCK1", 1000000000)
        this.token2 = await this.ERC20Mock.deploy("Mock token", "MOCK2", 1000000000)
        await this.token1.deployed()
        await this.token2.deployed()
    })

    it("Should allow only Governor to request governance transfer", async function () {
        await expect(
            this.fliqPropulsion.connect(this.bob).setPendingGovernor(this.bob.address)
        ).to.be.revertedWith("Only Governor")
        expect(await this.fliqPropulsion.pendingGovernor()).to.not.be.equal(this.bob.address)
        await this.fliqPropulsion.connect(this.governor).setPendingGovernor(this.bob.address)
        expect(await this.fliqPropulsion.pendingGovernor()).to.be.equal(this.bob.address)
        expect(await this.fliqPropulsion.govTransferReqTimestamp()).to.not.be.equal(0)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.fliqPropulsion.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("Zero Address")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.fliqPropulsion.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.fliqPropulsion.transferGovernance()).to.be.revertedWith("Too Early")
        await time.increase(this.transferGovernanceDelay)
        await this.fliqPropulsion.transferGovernance()
        expect(await this.fliqPropulsion.governor()).to.be.equal(this.bob.address)
    })

    it("Should allow only Governor to initialize the connector to Bastion", async function () {
        await expect(
            this.fliqPropulsion.connect(this.bob).initialize(this.bastion.address)
        ).to.be.revertedWith("Only Governor")
        await this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
    })

    it("Should not allow to initialize the connector to Bastion more then once", async function () {
        await this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
        await expect(
            this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
        ).to.be.revertedWith("Already Initialized")
    })

    it("Should only allow Governor to set farm address", async function () {
        await this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
        await expect(
            this.fliqPropulsion.connect(this.bob).setFliqFarm(this.farm.address)
        ).to.be.revertedWith("Only Governor")
        await this.fliqPropulsion.connect(this.governor).setFliqFarm(this.farm.address)
        expect(await this.fliqPropulsion.fliqFarm()).to.be.equal(this.farm.address)
    })

    it("Should only allow Governor to set bridge token", async function () {
        await this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
        await expect(
            this.fliqPropulsion
                .connect(this.bob)
                .setBridge(this.token1.address, this.token2.address)
        ).to.be.revertedWith("Only Governor")
        await this.fliqPropulsion
            .connect(this.governor)
            .setBridge(this.token1.address, this.token2.address)
        expect(await this.fliqPropulsion.bridgeFor(this.token1.address)).to.be.equal(
            this.token2.address
        )
    })

    it("Should only allow Governor call convert or convertMultiple", async function () {
        await this.fliqPropulsion.connect(this.governor).initialize(this.bastion.address)
        await this.fliqPropulsion
            .connect(this.governor)
            .setBridge(this.token1.address, this.token2.address)
        await expect(
            this.fliqPropulsion.connect(this.bob).convert(this.token1.address, this.token2.address)
        ).to.be.revertedWith("Only Governor")
        await expect(
            this.fliqPropulsion
                .connect(this.bob)
                .convertMultiple(
                    [this.token1.address, this.fliq.address],
                    [this.token1.address, this.token2.address]
                )
        ).to.be.revertedWith("Only Governor")
    })
})
