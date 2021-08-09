// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
/**

    Teller Functionality:
    -Receive LP tokens from provider
    -Calling the Vault for the provider to be paid over time
    -Other stuff update once done

 */

 contract Vault{
    function payProvider(address _provider, uint256 _providerWeightTime, uint256 _totalWeight);
 }

 contract Teller{
    address public LP;
    address public vaultAddress; 
    address private admin;

    Vault vault;
    ERC20 token;

    constructor (address _LP, address _vault) {
        vaultAddress = _vault;
        LP = _LP;

        token = ERC20(_LP);
        vault = Vault(_vault);
        admin = msg.sender;

    }

    event deposit(address sender, uint256 amount);
    event withdraw(address receiver, uint256 amount);



    struct Provider{
        uint256 LPdeposited;
        uint256 userWeight;
        uint256 committedAmount;
        uint256 lastCollection;

    }

    uint256 totalLP;
    uint256 totalWeight;
    mapping(address=>Provider) providerInfo;
    mapping(address=> bool) provider;
    bool open;

    modifier isOpen(){

        require(open, "Teller is not open");
        _;

    }

    modifier isProvider(){

        require(provider[msg.sender], "Not Provider");
        _;

    }

    modifier isAdmin(){

        require(admin == msg.sender, "Admin only function");
        _;
    }

    //admin functions

    function toggleTeller() private isAdmin {

        open = !open; 

    }

    //provider functions

    function depositLP(uint256 _amount) external isOpen {

        require(token.balanceOf(msg.sender) >= _amount, "Not enought LP");
        require(token.transferFrom(msg.sender, address(this), _amount), "LP not transferred");
        Provider storage user = providerInfo[msg.sender];
        if(provider[msg.sender]){
        claim();
        }else{
            user.lastcollection = now;
        }
        user.LPdeposited += _amount;
        user.userWeight += _amount;
        provider[msg.sender] = true;

        emit deposit(msg.sender, _amount);

    }

    function claimExternal() external isOpen isProvider {
        claim();
    }

    function withdraw(uint256 _amount) external isProvider {

        Provider storage user = providerInfo[msg.sender];
        require(user.LPdeposited >= _amount, "Not enough tokens");
        claim();
        user.LPdeposited -= _amount;
        user.userWeight -= _amount;
        if(user.LPdepsoited == 0){
            provider[msg.sender]==false;
        }

        token.transferTo(msg.sender, _amount);

        emit withdraw(msg.sender, _amount);

    }

    //internal functions

    function claim() internal{
        
        Provider memory user = providerInfo[msg.sender];
        uint256 _timeGap = now - user.lastCollection;
        if(!open){
            _timeGap = closeTime - lastCollection;
        }
        if(_timeGap > 1 years){
            _timeGap = 1 years;
        }
        uint256 _weightTime = _timeGap * user.userWeight;
        providerInfo[msg.sender].lastcollection = now;
        Vault.payProvider(msg.sender, _weightTime, totalWeight);

    }

    //other
 }