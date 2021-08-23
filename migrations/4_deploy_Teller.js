const Lptoken = artifacts.require("Lptoken");
const Vault = artifacts.require("Vault");
const Teller = artifacts.require("Teller");

module.exports = async function (deployer) {

  Lptoken_instance = await Lptoken.deployed();
  Vault_instance = await Vault.deployed();

  await deployer.deploy(
    Teller,
    Lptoken_instance.address,
    Vault_instance.address
  );
  return;
};
