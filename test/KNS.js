const { expect } = require("chai");
const { ethers } = require("hardhat");

const tx = async (tx) => await (await tx).wait();

describe("Kenshi", function () {
  it("Shouldn't be able to transfer more than owned", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1, addr2] = await ethers.getSigners();

    await tx(KNS.connect(_owner).transfer(addr1.address, "1"));

    await expect(
      tx(KNS.connect(addr1).transfer(addr2.address, "2"))
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
  });

  it("Shouldn't be able to transfer to address(0)", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner] = await ethers.getSigners();

    await expect(
      tx(KNS.connect(_owner).transfer(ethers.constants.AddressZero, "1"))
    ).to.be.revertedWith("ERC20: transfer to the zero address");
  });

  it("Shouldn't be able to transfer from address(0)", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner] = await ethers.getSigners();

    await expect(
      tx(
        KNS.connect(_owner).transferFrom(
          ethers.constants.AddressZero,
          _owner.address,
          "0"
        )
      )
    ).to.be.revertedWith("ERC20: approve from the zero address");
  });

  it("Shouldn't be able to approve to address(0)", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner] = await ethers.getSigners();

    await expect(
      tx(KNS.connect(_owner).approve(ethers.constants.AddressZero, "1"))
    ).to.be.revertedWith("ERC20: approve to the zero address");
  });

  it("Decrease allowance shouldn't underflow", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await expect(
      tx(KNS.connect(_owner).decreaseAllowance(addr1.address, "1"))
    ).to.be.revertedWith("ERC20: decreased allowance below zero");
  });

  it("Balances should be reported correctly", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await tx(KNS.connect(_owner).transfer(addr1.address, "100"));
    expect(await KNS.balanceOf(addr1.address)).to.equal("100");
  });

  it("Base info should be set correctly on deploy", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner] = await ethers.getSigners();

    expect(await KNS.owner()).to.be.equal(_owner.address);
    expect(await KNS.decimals()).to.be.equal(18);
    expect(await KNS.symbol()).to.be.equal("KNS");
    expect(await KNS.name()).to.be.equal("Kenshi");
    expect(await KNS.totalSupply()).to.be.equal("1000000000000000000000000000");
  });

  it("Sending BNB to the contract should fail", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner] = await ethers.getSigners();

    const tx = _owner.sendTransaction({
      to: KNS.address,
      value: ethers.utils.parseEther("1.0"),
    });

    await expect(tx).to.be.reverted;
  });

  it("Ownership transfer should work", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await KNS.transferOwnership(addr1.address);
    expect(await KNS.owner()).to.be.equal(addr1.address);

    await KNS.connect(addr1).renounceOwnership();
    expect(await KNS.owner()).to.be.equal(
      "0x0000000000000000000000000000000000000000"
    );
  });

  it("Transfer from should fail without allowance", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await expect(
      tx(KNS.connect(addr1).transferFrom(_owner.address, addr1.address, "1"))
    ).to.be.revertedWith("ERC20: insufficient allowance");
  });

  it("Approval and allowance should work", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await KNS.approve(addr1.address, "100000000000");
    expect(await KNS.allowance(_owner.address, addr1.address)).to.be.equal(
      "100000000000"
    );

    await KNS.increaseAllowance(addr1.address, "100000000000");
    expect(await KNS.allowance(_owner.address, addr1.address)).to.be.equal(
      "200000000000"
    );

    await KNS.decreaseAllowance(addr1.address, "100000000000");
    expect(await KNS.allowance(_owner.address, addr1.address)).to.be.equal(
      "100000000000"
    );
  });

  it("Transfer from should pass with correct allowance", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await KNS.approve(addr1.address, "100000000000");

    await expect(
      KNS.connect(addr1).transferFrom(_owner.address, addr1.address, "1")
    ).to.not.be.reverted;
  });

  it("Recovering tokens should work", async function () {
    const Kenshi = await ethers.getContractFactory("Kenshi");
    const KNS = await await Kenshi.deploy(10n ** 27n);
    await KNS.deployed();

    const [_owner, addr1] = await ethers.getSigners();

    await KNS.transfer(KNS.address, "100000000000");
    await KNS.recoverERC20(KNS.address, addr1.address, "100000000000");

    expect(await KNS.balanceOf(addr1.address)).to.equal("100000000000");
  });
});
