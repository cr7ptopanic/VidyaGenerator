const Vault = artifacts.require("Vault");
const Vidya = artifacts.require("Vidya");
const Teller = artifacts.require("Teller");
const Lptoken = artifacts.require("Lptoken");
const { assert } = require("chai");
const { BN } = require("web3-utils");
const timeMachine = require('ganache-time-traveler');

contract("Teller", (accounts) => {
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
            vault_contract.address,
            { from: accounts[0] }
        ).then((instance) => {
            teller_contract = instance;
        });

        await lptoken_contract.transfer(accounts[1], new BN('10000000000000000000000'), { from: accounts[0] }); // 10,000 LP token
        await lptoken_contract.transfer(accounts[2], new BN('10000000000000000000000'), { from: accounts[0] }); // 10.000 LP token


        await vault_contract.addTeller(teller_contract.address, 10);
        await vidya_contract.transfer(vault_contract.address, new BN('1000000000000000000000000'), { from: accounts[0] }); // 1,000,000 Vidya
        await teller_contract.addCommitment(new BN('500000000000000000000'), 7, new BN('100000000000000000000'), new BN('1000000000000000000000'));
        // Bonus: 50%, duration: 1 week, penalty: 10%, DeciAdjustment: 1000

        await teller_contract.addCommitment(new BN('700000000000000000000'), 365, new BN('200000000000000000000'), new BN('1000000000000000000000'));
        // Bonus: 70%, duration: 1 year, penalty: 20%, DeciAdjustment: 1000

        await lptoken_contract.approve(teller_contract.address, new BN('10000000000000000000000'), { from: accounts[1] });
        await lptoken_contract.approve(teller_contract.address, new BN('10000000000000000000000'), { from: accounts[2] });
    });

    describe("Toggle Commitmnet", () => {
        it("Current index is not listed in the commitment array.", async () => {
            let thrownError;
            try {
                await teller_contract.toggleCommitment(
                    3,
                    { from: accounts[0] }
                );
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Teller: Current index is not listed in the commitment array.',
            )
        });

        it("Toggle commitment is working", async () => {
            await teller_contract.toggleCommitment(1);
            await teller_contract.toggleCommitment(1);
        });
    });

    describe("Deposit LP token", () => {
        it("Depositing lp token is not working with closed teller.", async () => {
            let thrownError;
            try {
                await teller_contract.depositLP(new BN('1000000000000000000000'), { from: accounts[1] });
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Teller: Teller is not opened.',
            )
        });

        it("Depositing LP token is working", async () => {
            await teller_contract.toggleTeller({ from: accounts[0] });
            await teller_contract.depositLP(new BN('1000000000000000000000'), { from: accounts[2] }); // Deposit LP token: 1,000
            await teller_contract.depositLP(new BN('1000000000000000000000'), { from: accounts[2] }); // Deposit LP token: 1,000
            await teller_contract.depositLP(new BN('1000000000000000000000'), { from: accounts[1] }); // Deposit LP token: 1,000

            assert.equal(new BN(await lptoken_contract.balanceOf(teller_contract.address)).toString(), new BN('3000000000000000000000').toString());
        });
    });

    describe("Commit", () => {
        it("Current Commit is not active.", async () => {
            let thrownError;
            try {
                await teller_contract.toggleCommitment(1);
                await teller_contract.commit(new BN('100000000000000000000'), 1,  { from: accounts[1] });
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                'Teller: Current commitment is not active.',
            )
        });

        it("Provider hasn't got enough deposited LP tokens to commit.", async () => {
            await teller_contract.toggleCommitment(1);
            await teller_contract.commit(new BN('100000000000000000000'), 1,  { from: accounts[1] });
            let thrownError;
            try {
                await teller_contract.commit(new BN('1000000000000000000000'), 1,  { from: accounts[1] });
            } catch (error) {
                thrownError = error;
            }

            assert.include(
                thrownError.message,
                "Teller: Provider hasn't got enough deposited LP tokens to commit.",
            )
        });

        // it("Current commitment is not same as provider's.", async () => {
        //     let thrownError;
        //     try {
        //         await teller_contract.commit(new BN('1000000000000000000000'), 3,  { from: accounts[1] });
        //     } catch (error) {
        //         thrownError = error;
        //     }

        //     assert.include(
        //         thrownError.message,
        //         "Teller: Current commitment is not same as provider's.",
        //     )
        // });

        // it("Commit is working.", async () => {
        //     await teller_contract.commit(new BN('100000000000000000000'), 1, { from: accounts[1] }); // Deposit LP token: 100
        //     assert.equal(new BN(await lptoken_contract.balanceOf(teller_contract.address)).toString(), new BN('3000000000000000000000').toString());
        // });
    });
});
