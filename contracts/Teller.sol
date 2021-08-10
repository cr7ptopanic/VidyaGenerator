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
        commitmentInfo.push();
        admin = msg.sender;     
        
    }

    event deposit(address sender, uint256 amount);
    event withdraw(address receiver, uint256 amount);
    event newCommitment(uint256 bonus, uint256 time, uint256 penalty, uint256 deciAdjustment);
    event commitmentLives(uint256 sender, uint256 commitedAmount);
    event commitmentBroken(uint256 sender, uint256 tokenSent);
    event tellerToggled(address teller, bool status);
    event commitmentToggle(uint256 index, bool status);
    event purposeSet(address location);

    struct Provider{
        uint256 LPdeposited;
        uint256 userWeight;
        uint256 committedAmount;
        uint256 lastCollection;
        uint256 commitmentEnds;
        uint256 commitmentIndex;

    }
    struct Commitment{    
        uint256 bonus;
        uint256 duration;
        uint256 penalty;
        uint256 deciAdjustment;
        bool isActive;
    }

    uint256 totalLP;
    uint256 totalWeight;
    uint256 closeTime;
    mapping(address=>Provider) providerInfo;
    mapping(address=> bool) provider;
    bool open;
    address dev;
    bool purpose;
    
    Commitment[] commitmentInfo;
    



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

    function toggleTeller() external isAdmin {

        open = !open; 
        closeTime = now;
        emit tellerToggled(address(this), open);
    }
    
    function addCommitment(uint256 _bonus, uint256 _days, uint256 _penalty, uint256 _deciAdjustment) external isAdmin{
        Commitment memory _holder;
        uint256 time = _days days;
        _holder.bonus = _bonus;
        _holder.duration = time;
        _holder.penalty = _penalty;
        _holder.deciAdjustment = _deciAdjustment;
        _holder.isActive = true;
        commitmentInfo.push(_holder);
        
        emit newCommitment(_bonus, time, _penalty, _deciAdjustment);
    }

    function toggleCommitment(uint256 _index) external isAdmin{

        require(_index <= commitmentInfo.length && _index > 0, "Teller: Not within bounds.")
        commitmentInfo[_index].isActive = !commitmentInfo[_index].isActive;

        emit commitmentToggle(_index, commitmentInfo[_index].isActive);

    }

    function setPurpose(address _address) external isAdmin{

        purpose = true;
        dev = _address;
        emit purposeSet(dev);
        
    }

    //provider functions

    function depositLP(uint256 _amount) external isOpen {

        require(token.balanceOf(msg.sender) >= _amount, "Not enought LP"); //could we forget this one since the next one would return false if not transferred?
        require(token.transferFrom(msg.sender, address(this), _amount), "LP not transferred");
        Provider storage user = providerInfo[msg.sender];
        if(provider[msg.sender]){
        claim();
        }else{
            user.lastcollection = now;
        }
        user.LPdeposited += _amount;
        user.userWeight += _amount;
        totalLP += _amount;
        provider[msg.sender] = true;

        emit deposit(msg.sender, _amount);
    }

    function claimExternal() external isOpen isProvider {
        claim();
    }

    function withdraw(uint256 _amount) external isProvider {

        Provider storage user = providerInfo[msg.sender];
        require(user.LPdeposited - user.commitedAmount >= _amount, "Not enough tokens");
        claim();

        user.userWeight = user.userWeight - ((amount*user.userWeight)/user.LPdeposited);
        user.LPdeposited =user.LPdeposited _amount;
        if(user.LPdeposited == 0){
            provider[msg.sender]==false;
        }
        uint256 balance = token.balanceOf(address(this));
        uint256 send = _amount;
        if(totalLP < balance){

            send = (_amount * balance)/ totalLP;

        }

        totalLP = totalLP - send;
        token.transferTo(msg.sender, send);

        emit withdraw(msg.sender, send);

    }

    function commit(uint256 _amount, uint256 _commitmentIndex)external nonReentrant, isProvider{
        require(commitmentInfo[_commitmentIndex].isActive, "Teller: Is not a valid commitment");
        Provider storage user = providerInfo[msg.sender];
        require(user.LPdeposited - user.committedAmount >= _amount, "Teller: Not enough tokens deposited");
        uint256 bonusCredit = commitBonus(_commitmentIndex, _amount);
        uint256 newEnd;
        if(user.commitmentEnds > now){
            require(_commitmentIndex == user.commitmentIndex, "Teller: Choose same commitment to extend");
            newEnd = addToCommitment(user.committedAmount, _amount, user.commitmentEnds, _commitmentIndex);

        }else{

            user.commitmentIndex;
            newEnd = now + commitmentInfo[_commitmentIndex];
        }

        user.committedAmount += _amount;
        user.commitmentEnds = newEnd;
        user.userWeight += bonusCredit;
        totalWeight += bonusCredit;

        emit commitmentLives(msg.sender, _amount);
    }

    function breakCommitment() external nonReentrant, isProvider{

        Provider storage user = providerInfo[msg.sender];
        Provider memory blank;
        require(user.commitmentEnds > now, "Teller: No commitment to break.");
        uint256 tokenToReceive = user.LPdeposited;
        Commitment memory _current = commitmentInfo[user.commitmentIndex];
        uint256 fee = (tokenToReceive * _current.penalty) / deciAdjustment;
        tokenToReceive = tokenToReceive - fee;
        totalWeight = totalWeight - user.userWeight;

        user = blank;

        if(purpose){

            uint256 devFee = fee /10;
            token.transfer(dev, devFee);

        }

        token.transfer(msg.sender, tokenToReceive);

        emit commitmentBroken(msg.sender, tokenToReceive);
        

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

    function commitBonus(uint256 _commitmentIndex, uint256 _amount) internal view return(uint256){
               
        if(commitmentInfo[_commitmentIndex].isActive){

            return commitmentInfo[_commitmentIndex].bonus * _amount / commitmentInfo[_commitmentIndex].deciAdjustment;
        
        }
        return 0;
    
    }

    function addToCommitment(uint256 _oldAmount, uint256 _extraAmount, uint256 _oldEnd, uint256 _commitmentIndex) internal{

        uint256 _placeHolder = commitmentInfo[_commitmentIndex].duration + now;
        uint256 newEnd = ((_oldAmount * _oldEnd) + (_extraAmount *_placeHolder))/(_oldAmount + _extraAmount); //weighted mean formula with amount being the weight

        return newEnd;

    }

    // Teller logic and code developed by Blastscout for use by team3d.io for their generator.
    // Teller developed and tested by ... 
 }
