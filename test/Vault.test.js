const Vault = artifacts.require("Vault");
const Vidya = artifacts.require("Vidya");
const Teller = artifacts.require("Teller");
const Lptoken = artifacts.require("Lptoken");
const { assert } = require("chai");
const timeMachine = require('ganache-time-traveler');

contract("Vault", (accounts) => {
    let vault_contract, vidya_contract, teller_contract, lptoken_contract;

    before(async () => {
        await Vidya.new(
            { from: accounts[0] }
        ).then((instance) => {
            vidya_contract = instance;
        });

        await Lptoken.new(
            { from: accounts[0] }
        ).then((instance) => {
            lptoken_contract = instance;
        });

        await Vault.new(
            vidya_contract.address,
            { from: accounts[0] }
        ).then((instance) => {
            vault_contract = instance;
        });

        await Teller.new(
            lptoken_contract.address,
            vidya_contract.address,
            { from: accounts[0] }
        ).then((instance) => {
            teller_contract = instance;
        });
    });

    describe("Add Teller", () => {
        it("Teller address is not the contract address", async () => {
            let thrownError;
            try {
                await vault_contract.addTeller(
                    "0x85f1d204292416DcBfB5F47CF708Ec06fFbA47d2",
                    123,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Address is not the contract address.',
            )
        });

        it("Priority should be more than zero", async () => {
            let thrownError;
            try {
                await vault_contract.addTeller(
                    vidya_contract.address,
                    0,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Priority should be more than zero.',
            )
        });

        it("Adding Teller is working", async () => {
            await vault_contract.addTeller(teller_contract.address, 10);
        });

        it("Currrent teller is already added.", async () => {
            let thrownError;
            try {
                await vault_contract.addTeller(
                    teller_contract.address,
                    10,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Caller is a teller already.',
            )
        });
    });

    describe("Change Priority", () => {
        it("Teller address is not the contract address", async () => {
            let thrownError;
            try {
                await vault_contract.changePriority(
                    "0x85f1d204292416DcBfB5F47CF708Ec06fFbA47d2",
                    123,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Address is not the contract address.',
            )
        });

        it("Caller is not the teller.", async () => {
            let thrownError;
            try {
                await vault_contract.changePriority(
                    vidya_contract.address,
                    10,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Caller is not the teller.',
            )
        });

        it("New priority should be more than zero", async () => {
            let thrownError;
            try {
                await vault_contract.changePriority(
                    teller_contract.address,
                    0,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Priority should be more than zero.',
            )
        });

        it("Not time to change priority", async () => {
            let thrownError;
            try {
                await vault_contract.changePriority(
                    teller_contract.address,
                    20,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Vault: Not time to change the priority.',
            )
        });

        it("Change priority is working", async () => {
            await timeMachine.advanceTimeAndBlock(604800);
            await vault_contract.changePriority(teller_contract.address, 7);
        });

    });
});
