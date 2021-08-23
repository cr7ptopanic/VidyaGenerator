const Vidya = artifacts.require("Vidya");
const Vault = artifacts.require("Vault");

module.exports = async function (deployer) {

  Vidya_instance = await Vidya.deployed();

  await deployer.deploy(
    Vault,
    Vidya_instance.address
  );
  return;
};
