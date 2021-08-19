const Lptoken = artifacts.require("Lptoken");
const Vidya = artifacts.require("Vidya");

module.exports = async function (deployer) {
  await deployer.deploy(
    Lptoken,
  );

  await deployer.deploy(
    Vidya,
  );
  return;
};
