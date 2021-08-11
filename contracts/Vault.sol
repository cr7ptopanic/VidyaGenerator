// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Vault Contract
 */
contract Vault is Ownable {
    using Address for address;

    event tellerAdded(address _teller, uint256 _priority);
    event tellerPriorityChanged(address _teller, uint256 _priority);
    event rateChange(uint256 _rate);
    event rewards(address _provider, uint256 _amount);

    IERC20 Vidya;

    mapping(address => bool) teller;
    mapping(address => uint256) tellerPriority;
    mapping(address => uint256) priorityFreeze;

    uint256 totalPriority;

    uint256 rate;
    uint256 nextRateChange;

    modifier isTeller() {
        require(teller[msg.sender], "Vault: Teller only function");
        _;
    }

    /**
     * @dev Constructor function
     * @param _Vidya Interface of Vidya 0x3D3D35bb9bEC23b06Ca00fe472b50E7A4c692C30
     */
    constructor(IERC20 _Vidya) {
        Vidya = _Vidya;
    }

    // admin functions

    function addTeller(address _teller, uint256 _priority) external onlyOwner {
        require(teller[_teller] == false, "Vault: Already a teller");
        require(_priority > 0, "Vault: Priority not greater then 0");

        teller[_teller] = true;
        tellerPriority[_teller] = _priority;
        totalPriority += _priority;
        priorityFreeze[_teller] = block.timestamp + 7 days;

        emit tellerAdded(_teller, _priority);
    }

    function changePriority(address _teller, uint256 _newPriority)
        external
        onlyOwner
    {
        require(teller[_teller], "Vault: Not a Teller");
        require(
            priorityFreeze[_teller] <= block.timestamp,
            "Vault: To soon to change Priority."
        );

        uint256 _oldPriority = tellerPriority[_teller];
        totalPriority = (totalPriority - _oldPriority) + _newPriority;
        tellerPriority[_teller] = _newPriority;

        priorityFreeze[_teller] = block.timestamp + 1 weeks;

        emit tellerPriorityChanged(_teller, _newPriority);
    }

    //Vault Functions internal

    function calculateRate() internal {
        rate = Vidya.balanceOf(address(this)) / 26 weeks; //roughly 6 months
        nextRateChange = block.timestamp + 1 weeks;

        emit rateChange(rate);
    }

    //teller functions

    function payProvider(
        address _provider,
        uint256 _providerWeightTime,
        uint256 _totalWeight
    ) external isTeller {
        uint256 _numerator = rate *
            _providerWeightTime *
            tellerPriority[msg.sender];
        uint256 _demonator = _totalWeight * totalPriority;
        uint256 _amount = _numerator / _demonator;
        if (nextRateChange <= block.timestamp) {
            calculateRate();
        }

        Vidya.transfer(_provider, _amount);

        emit rewards(_provider, _amount);
    }
}
