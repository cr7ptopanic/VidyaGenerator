// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title Vault Interface
 */
interface IVault {
    function addTeller(address _teller, uint256 _priority) external;

    function changePriority(address _teller, uint256 _newPriority) external;

    function payProvider(
        address _provider,
        uint256 _providerWeightTime,
        uint256 _totalWeight
    ) external;
}
